using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO;
using System.Linq;
using HDriveWin.Models;
using System.Threading;
using System.Threading.Tasks;

namespace HDriveWin.Services;

public class FileSyncedEventArgs : EventArgs
{
    public string FileName { get; }
    public string RemoteDirectory { get; }
    public bool Success { get; }

    public FileSyncedEventArgs(string fileName, string remoteDirectory, bool success)
    {
        FileName = fileName;
        RemoteDirectory = remoteDirectory;
        Success = success;
    }
}

public class WatchedFileEntry
{
    public string ServerId { get; set; } = string.Empty;
    public string ServerURL { get; set; } = string.Empty;
    public string Username { get; set; } = string.Empty;
    public string BucketName { get; set; } = string.Empty;
    public string SmbShareName { get; set; } = string.Empty;
    public StorageProtocol Protocol { get; set; }
    public SemaphoreSlim UploadGate { get; } = new(1, 1);
    public string LocalPath { get; set; } = string.Empty;
    public string RemoteFilePath { get; set; } = string.Empty;
    public string RemoteDirectory { get; set; } = string.Empty;
    public DateTime LastKnownWriteTime { get; set; }
    public System.Threading.Timer? DebounceTimer { get; set; }
}

/// <summary>
/// Harici uygulamalarda (Excel, Word, Photoshop, VS Code, Not Defteri vb.) açılan dosyaları izler;
/// kullanıcı harici uygulamada Ctrl+S ile kaydettiği anda değişikliği yakalayıp Cloudreve'e otomatik geri yükler.
/// </summary>
public class LiveEditWatcherService : IDisposable
{
    private static LiveEditWatcherService? _instance;
    public static LiveEditWatcherService Instance => _instance ??= new LiveEditWatcherService();

    private readonly ConcurrentDictionary<string, WatchedFileEntry> _watchedFiles = new(StringComparer.OrdinalIgnoreCase);
    private readonly ConcurrentDictionary<string, FileSystemWatcher> _watchers = new(StringComparer.OrdinalIgnoreCase);
    private readonly object _lock = new();

    public event EventHandler<FileSyncedEventArgs>? FileAutoSynced;

    private readonly Func<string, ServerConfig?> _resolveServer;
    private readonly Func<ServerConfig, WebDAVClient> _createClient;
    private LiveEditWatcherService() : this(
        id => CloudreveManager.Instance.Servers.FirstOrDefault(s => s.Id == id), config => new WebDAVClient(config)) { }
    internal LiveEditWatcherService(Func<string, ServerConfig?> resolveServer, Func<ServerConfig, WebDAVClient> createClient)
    { _resolveServer = resolveServer; _createClient = createClient; }

    internal Task SyncFileAsync(string path) => _watchedFiles.TryGetValue(path, out var entry)
        ? HandleAutoUploadAsync(entry) : Task.CompletedTask;

    public void Dispose()
    {
        foreach (var watcher in _watchers.Values) watcher.Dispose();
        foreach (var entry in _watchedFiles.Values) entry.DebounceTimer?.Dispose();
        _watchers.Clear(); _watchedFiles.Clear();
    }

    public void WatchFile(string localFilePath, string remoteFilePath, string remoteDirectory, ServerConfig server)
    {
        try
        {
            var directory = Path.GetDirectoryName(localFilePath);
            if (string.IsNullOrEmpty(directory) || !Directory.Exists(directory)) return;

            var fileName = Path.GetFileName(localFilePath);
            var lastWrite = File.GetLastWriteTimeUtc(localFilePath);

            var entry = new WatchedFileEntry
            {
                ServerId = server.Id,
                ServerURL = server.ServerURL,
                Username = server.Username,
                BucketName = server.BucketName,
                SmbShareName = server.SmbShareName,
                Protocol = server.Protocol,
                LocalPath = localFilePath,
                RemoteFilePath = remoteFilePath,
                RemoteDirectory = remoteDirectory,
                LastKnownWriteTime = lastWrite
            };

            WorkingCache.Protect(localFilePath);
            _watchedFiles[localFilePath] = entry;

            lock (_lock)
            {
                var cacheRoot = Path.Combine(Path.GetTempPath(), "HDriveCache");
                var watchRoot = localFilePath.StartsWith(cacheRoot + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) ? cacheRoot : directory;
                if (!_watchers.ContainsKey(watchRoot))
                {
                    var watcher = new FileSystemWatcher(watchRoot) {
                        NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.Size | NotifyFilters.FileName,
                        IncludeSubdirectories = true
                    };
                    watcher.Changed += OnFileChanged;
                    watcher.Created += OnFileChanged;
                    watcher.Renamed += (sender, args) => OnFileChanged(sender, args);
                    _watchers[watchRoot] = watcher;
                    watcher.EnableRaisingEvents = true;
                }
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"LiveEditWatcherService.WatchFile error: {ex.Message}");
        }
    }

    private void OnFileChanged(object sender, FileSystemEventArgs e)
    {
        if (!_watchedFiles.TryGetValue(e.FullPath, out var entry)) return;

        try
        {
            var currentWrite = File.GetLastWriteTimeUtc(e.FullPath);
            if (currentWrite <= entry.LastKnownWriteTime) return;

            // Debounce: Düzenleme yazımı tamamlanana kadar 1200ms bekle
            entry.DebounceTimer?.Dispose();
            entry.DebounceTimer = new System.Threading.Timer(_ =>
            {
                _ = HandleAutoUploadAsync(entry);
            }, null, 1200, Timeout.Infinite);
        }
        catch { }
    }

    private async Task HandleAutoUploadAsync(WatchedFileEntry entry)
    {
        await entry.UploadGate.WaitAsync();
        try { await UploadWhenReadyAsync(entry); }
        finally { entry.UploadGate.Release(); }
    }

    private async Task UploadWhenReadyAsync(WatchedFileEntry entry)
    {
        // Serialize saves of the same file and wait for external writers.
        bool ready = false;
        for (int i = 0; i < 5; i++)
        {
            if (IsFileReady(entry.LocalPath))
            {
                ready = true;
                break;
            }
            await Task.Delay(300);
        }

        if (!ready) return;

        try
        {
            var written = File.GetLastWriteTimeUtc(entry.LocalPath);
            if (written <= entry.LastKnownWriteTime) return;
            var config = _resolveServer(entry.ServerId);
            if (config == null || !config.IsConnected || config.ServerURL != entry.ServerURL || config.Protocol != entry.Protocol || config.Username != entry.Username || config.BucketName != entry.BucketName || config.SmbShareName != entry.SmbShareName)
                throw new InvalidOperationException("Dosyanın ait olduğu hesabın bağlantısı kesildi.");
            var client = _createClient(config);
            await client.UploadAsync(entry.LocalPath, entry.RemoteDirectory, existingRemotePath: entry.RemoteFilePath);
            entry.LastKnownWriteTime = written;
            var success = true;

            FileAutoSynced?.Invoke(this, new FileSyncedEventArgs(Path.GetFileName(entry.LocalPath), entry.RemoteDirectory, success));
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"LiveEditWatcherService auto upload failed: {ex.Message}");
            FileAutoSynced?.Invoke(this, new FileSyncedEventArgs(Path.GetFileName(entry.LocalPath), entry.RemoteDirectory, false));
        }
    }

    private static bool IsFileReady(string filename)
    {
        try
        {
            using var inputStream = File.Open(filename, FileMode.Open, FileAccess.Read, FileShare.None);
            return true;
        }
        catch (IOException)
        {
            return false;
        }
        catch
        {
            return false;
        }
    }
}
