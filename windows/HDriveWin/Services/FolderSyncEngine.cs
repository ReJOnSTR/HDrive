using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Threading.Tasks;
using HDriveWin.Models;

namespace HDriveWin.Services;

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
                    _ = SyncNowAsync();
                }
                else
                {
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

    private FolderSyncEngine()
    {
        var userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        LocalFolderPath = Path.Combine(userProfile, "HDrive - Cloudreve");
        Directory.CreateDirectory(LocalFolderPath);

        _isSyncEnabled = CloudreveManager.Instance.ActiveServer.AutoSyncEnabled;

        if (_isSyncEnabled)
        {
            _syncTimer = new Timer(async _ => await SyncNowAsync(), null, TimeSpan.FromSeconds(3), TimeSpan.FromMinutes(2));
        }
        else
        {
            _syncStatus = "Eşitleme Kapalı";
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
        SyncStatus = "Sunucu taranıyor...";

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
        var items = await client.ListDirectoryAsync(remotePath);

        foreach (var item in items)
        {
            var targetLocal = Path.Combine(localPath, item.Name);

            if (item.IsDirectory)
            {
                await SyncDirectoryRecursiveAsync(client, item.Path, targetLocal);
            }
            else
            {
                // Dosya varsa ve boyutu aynıysa atla
                if (File.Exists(targetLocal))
                {
                    var fi = new FileInfo(targetLocal);
                    if (fi.Length == item.Size && item.Size > 0)
                    {
                        continue;
                    }
                }

                SyncStatus = $"İndiriliyor: {item.Name}";
                var downloadedCache = await client.DownloadFileToCacheAsync(item.Path);
                if (!string.IsNullOrEmpty(downloadedCache) && File.Exists(downloadedCache))
                {
                    File.Copy(downloadedCache, targetLocal, overwrite: true);
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
