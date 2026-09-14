using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO;
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
public class LiveEditWatcherService
{
    private static LiveEditWatcherService? _instance;
    public static LiveEditWatcherService Instance => _instance ??= new LiveEditWatcherService();

    private readonly ConcurrentDictionary<string, WatchedFileEntry> _watchedFiles = new(StringComparer.OrdinalIgnoreCase);
    private FileSystemWatcher? _watcher;
    private readonly object _lock = new();

    public event EventHandler<FileSyncedEventArgs>? FileAutoSynced;

    private LiveEditWatcherService() { }

    public void WatchFile(string localFilePath, string remoteFilePath, string remoteDirectory)
    {
        try
        {
            var directory = Path.GetDirectoryName(localFilePath);
            if (string.IsNullOrEmpty(directory) || !Directory.Exists(directory)) return;

            var fileName = Path.GetFileName(localFilePath);
            var lastWrite = File.GetLastWriteTimeUtc(localFilePath);

            var entry = new WatchedFileEntry
            {
                LocalPath = localFilePath,
                RemoteFilePath = remoteFilePath,
                RemoteDirectory = remoteDirectory,
                LastKnownWriteTime = lastWrite
            };

            _watchedFiles[localFilePath] = entry;

            lock (_lock)
            {
                if (_watcher == null)
                {
                    _watcher = new FileSystemWatcher(directory)
                    {
                        NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.Size | NotifyFilters.FileName,
                        IncludeSubdirectories = false,
                        EnableRaisingEvents = true
                    };

                    _watcher.Changed += OnFileChanged;
                    _watcher.Created += OnFileChanged;
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
        // Dosyanın harici program tarafından kilitlenmediğinden emin ol (3 deneme)
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
            entry.LastKnownWriteTime = File.GetLastWriteTimeUtc(entry.LocalPath);

            var config = CloudreveManager.Instance.ActiveServer;
            if (config == null) return;

            var client = new WebDAVClient(config);
            var success = await client.UploadFileAsync(entry.LocalPath, entry.RemoteDirectory);

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
            return inputStream.Length > 0;
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
