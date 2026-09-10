using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Threading.Tasks;
using HDriveWin.Models;

namespace HDriveWin.Services;

/// <summary>
/// Gerçek İki Yönlü Senkronizasyon Motoru (Two-Way Sync):
/// 1. Yerel klasörde (%USERPROFILE%\HDrive - Cloudreve) yapılan eklemeler, değişiklikler ve silmeler FileSystemWatcher ile anında Cloudreve'e iletilir.
/// 2. Cloudreve'deki yeni veya güncellenen dosyalar yerel klasöre indirilir; Cloudreve'den silinen dosyalar yerelden de kaldırılır.
/// </summary>
public class FolderSyncEngine : INotifyPropertyChanged
{
    private static FolderSyncEngine? _instance;
    public static FolderSyncEngine Instance => _instance ??= new FolderSyncEngine();

    private bool _isSyncEnabled;
    public bool IsSyncEnabled
    {
        get => _isSyncEnabled;
        set
        {
            if (SetProperty(ref _isSyncEnabled, value))
            {
                var cfg = CloudreveManager.Instance.ActiveServer;
                cfg.AutoSyncEnabled = value;
                CloudreveManager.Instance.SaveConfig(cfg);

                if (value)
                {
                    StartWatcher();
                    _ = SyncNowAsync();
                }
                else
                {
                    StopWatcher();
                    SyncStatus = "Eşitleme Duraklatıldı";
                }
            }
        }
    }

    private bool _isSyncing;
    public bool IsSyncing
    {
        get => _isSyncing;
        set => SetProperty(ref _isSyncing, value);
    }

    private string _syncStatus = "Hazır";
    public string SyncStatus
    {
        get => _syncStatus;
        set => SetProperty(ref _syncStatus, value);
    }

    public string LocalFolderPath { get; }

    private Timer? _syncTimer;
    private FileSystemWatcher? _watcher;
    private volatile bool _suppressWatcherEvents = false;

    // Yerel değişiklikleri birleştirmek (debounce) için sayaçlar
    private readonly ConcurrentDictionary<string, Timer> _pendingUploads = new();
    // Önceden eşitlenen uzak dosyaların takibi (uzaktan silinince yerelden de silmek için)
    private readonly HashSet<string> _knownRemoteFiles = new(StringComparer.OrdinalIgnoreCase);

    private FolderSyncEngine()
    {
        var userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        LocalFolderPath = Path.Combine(userProfile, "HDrive - Cloudreve");
        Directory.CreateDirectory(LocalFolderPath);

        _isSyncEnabled = CloudreveManager.Instance.ActiveServer.AutoSyncEnabled;

        if (_isSyncEnabled)
        {
            StartWatcher();
            // Her 90 saniyede bir arka planda tam çift yönlü kontrol
            _syncTimer = new Timer(async _ => await SyncNowAsync(), null, TimeSpan.FromSeconds(3), TimeSpan.FromSeconds(90));
        }
        else
        {
            _syncStatus = "Eşitleme Kapalı";
        }
    }

    public void StartWatcher()
    {
        try
        {
            if (_watcher != null) return;
            Directory.CreateDirectory(LocalFolderPath);

            _watcher = new FileSystemWatcher(LocalFolderPath)
            {
                IncludeSubdirectories = true,
                NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName | NotifyFilters.LastWrite | NotifyFilters.Size
            };

            _watcher.Created += (s, e) => OnLocalChangedOrCreated(e.FullPath, isDelete: false);
            _watcher.Changed += (s, e) => OnLocalChangedOrCreated(e.FullPath, isDelete: false);
            _watcher.Deleted += (s, e) => OnLocalChangedOrCreated(e.FullPath, isDelete: true);
            _watcher.Renamed += (s, e) =>
            {
                OnLocalChangedOrCreated(e.OldFullPath, isDelete: true);
                OnLocalChangedOrCreated(e.FullPath, isDelete: false);
            };

            _watcher.EnableRaisingEvents = true;
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Watcher start error: {ex.Message}");
        }
    }

    public void StopWatcher()
    {
        if (_watcher != null)
        {
            _watcher.EnableRaisingEvents = false;
            _watcher.Dispose();
            _watcher = null;
        }
    }

    private void OnLocalChangedOrCreated(string fullPath, bool isDelete)
    {
        if (_suppressWatcherEvents) return;

        var relPath = Path.GetRelativePath(LocalFolderPath, fullPath).Replace('\\', '/');
        if (string.IsNullOrEmpty(relPath) || relPath.StartsWith('.') || relPath.Contains("/.") || relPath.EndsWith(".tmp")) return;

        // Debounce: Dosya yazılırken arka arkaya gelen tetiklemeleri 700ms bekletip tek seferde işle
        if (_pendingUploads.TryRemove(relPath, out var oldTimer))
        {
            oldTimer.Dispose();
        }

        var timer = new Timer(async _ =>
        {
            _pendingUploads.TryRemove(relPath, out var t);
            t?.Dispose();
            await HandleLocalChangeAsync(fullPath, relPath, isDelete);
        }, null, 700, Timeout.Infinite);

        _pendingUploads[relPath] = timer;
    }

    public void SuppressWatcher(Action action)
    {
        _suppressWatcherEvents = true;
        try
        {
            action();
        }
        finally
        {
            _suppressWatcherEvents = false;
        }
    }

    public void RegisterRemoteFile(string relativePath)
    {
        var clean = relativePath.TrimStart('/').Replace('\\', '/');
        if (!string.IsNullOrEmpty(clean))
        {
            _knownRemoteFiles.Add(clean);
        }
    }

    public void UnregisterRemoteFile(string relativePath)
    {
        var clean = relativePath.TrimStart('/').Replace('\\', '/');
        if (!string.IsNullOrEmpty(clean))
        {
            _knownRemoteFiles.RemoveWhere(f => f.Equals(clean, StringComparison.OrdinalIgnoreCase) || f.StartsWith(clean + "/", StringComparison.OrdinalIgnoreCase));
        }
    }

    private async Task HandleLocalChangeAsync(string fullPath, string relPath, bool isDelete)
    {
        if (!IsSyncEnabled) return;
        var config = CloudreveManager.Instance.ActiveServer;
        if (string.IsNullOrWhiteSpace(config.ServerURL)) return;

        var client = new WebDAVClient(config);

        try
        {
            if (isDelete)
            {
                SyncStatus = $"Sunucudan siliniyor: {Path.GetFileName(relPath)}";
                await client.DeleteAsync(relPath);
                UnregisterRemoteFile(relPath);
                SyncStatus = $"Eşitlendi ({DateTime.Now:HH:mm})";
            }
            else if (Directory.Exists(fullPath))
            {
                await client.CreateFolderAsync(relPath);
                RegisterRemoteFile(relPath);
            }
            else if (File.Exists(fullPath))
            {
                SyncStatus = $"Yükleniyor: {Path.GetFileName(relPath)}";
                var remoteDir = Path.GetDirectoryName(relPath)?.Replace('\\', '/') ?? "";
                var ok = await client.UploadFileAsync(fullPath, remoteDir);
                if (ok)
                {
                    RegisterRemoteFile(relPath);
                    SyncStatus = $"Eşitlendi ({DateTime.Now:HH:mm})";
                }
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Local change sync error: {ex.Message}");
        }
    }

    public void OpenLocalFolderInExplorer()
    {
        Directory.CreateDirectory(LocalFolderPath);
        Process.Start(new ProcessStartInfo
        {
            FileName = "explorer.exe",
            Arguments = $"\"{LocalFolderPath}\"",
            UseShellExecute = true
        });
    }

    public async Task SyncNowAsync()
    {
        if (!IsSyncEnabled || IsSyncing) return;

        var config = CloudreveManager.Instance.ActiveServer;
        if (string.IsNullOrWhiteSpace(config.ServerURL))
        {
            SyncStatus = "Sunucu yapılandırılmadı";
            return;
        }

        IsSyncing = true;
        SyncStatus = "Eşitleme taranıyor...";

        try
        {
            var client = new WebDAVClient(config);
            await SyncDirectoryRecursiveAsync(client, "", LocalFolderPath);
            SyncStatus = $"Eşitlendi ({DateTime.Now:HH:mm})";
        }
        catch (Exception ex)
        {
            SyncStatus = $"Hata: {ex.Message}";
        }
        finally
        {
            IsSyncing = false;
        }
    }

    private async Task SyncDirectoryRecursiveAsync(WebDAVClient client, string remotePath, string localPath)
    {
        Directory.CreateDirectory(localPath);
        var remoteItems = await client.ListDirectoryAsync(remotePath);
        var remoteNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var item in remoteItems)
        {
            remoteNames.Add(item.Name);
            var targetLocal = Path.Combine(localPath, item.Name);
            var relPath = Path.GetRelativePath(LocalFolderPath, targetLocal).Replace('\\', '/');
            _knownRemoteFiles.Add(relPath);

            if (item.IsDirectory)
            {
                await SyncDirectoryRecursiveAsync(client, item.Path, targetLocal);
            }
            else
            {
                bool needsDownload = true;
                if (File.Exists(targetLocal))
                {
                    var fi = new FileInfo(targetLocal);
                    if (fi.Length == item.Size && item.Size > 0)
                    {
                        needsDownload = false;
                    }
                }

                if (needsDownload)
                {
                    _suppressWatcherEvents = true;
                    try
                    {
                        SyncStatus = $"İndiriliyor: {item.Name}";
                        var downloadedCache = await client.DownloadFileToCacheAsync(item.Path);
                        if (!string.IsNullOrEmpty(downloadedCache) && File.Exists(downloadedCache))
                        {
                            File.Copy(downloadedCache, targetLocal, overwrite: true);
                        }
                    }
                    finally
                    {
                        _suppressWatcherEvents = false;
                    }
                }
            }
        }

        // Uzakta silinmiş dosyaları yerelde de temizle (Yalnızca daha önce eşitlenen dosyalar)
        if (Directory.Exists(localPath))
        {
            var localFiles = Directory.GetFiles(localPath);
            foreach (var lf in localFiles)
            {
                var fileName = Path.GetFileName(lf);
                var relPath = Path.GetRelativePath(LocalFolderPath, lf).Replace('\\', '/');

                if (!remoteNames.Contains(fileName) && _knownRemoteFiles.Contains(relPath))
                {
                    _suppressWatcherEvents = true;
                    try
                    {
                        File.Delete(lf);
                        _knownRemoteFiles.Remove(relPath);
                    }
                    catch { }
                    finally
                    {
                        _suppressWatcherEvents = false;
                    }
                }
            }
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    protected bool SetProperty<T>(ref T storage, T value, [CallerMemberName] string? propertyName = null)
    {
        if (Equals(storage, value)) return false;
        storage = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        return true;
    }
}
