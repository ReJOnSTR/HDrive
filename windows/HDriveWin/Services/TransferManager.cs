using System;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.UI.Dispatching;
using HDriveWin.Models;

namespace HDriveWin.Services;

public enum TransferDirection
{
    Download,
    Upload
}

public enum TransferStatus
{
    Queued,
    Running,
    Paused,
    Completed,
    Failed,
    Cancelled
}

public class TransferItem : INotifyPropertyChanged
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string FileName { get; set; } = string.Empty;
    public string RemotePath { get; set; } = string.Empty;
    public string LocalPath { get; set; } = string.Empty;
    public TransferDirection Direction { get; set; }
    public WebDAVClient? Client { get; set; }

    private TransferStatus _status = TransferStatus.Queued;
    public TransferStatus Status
    {
        get => _status;
        set
        {
            if (_status != value)
            {
                _status = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(StatusText));
                OnPropertyChanged(nameof(IsRunning));
                OnPropertyChanged(nameof(IsPaused));
                OnPropertyChanged(nameof(IsFailed));
                OnPropertyChanged(nameof(IsCompleted));
            }
        }
    }

    private long _transferredBytes;
    public long TransferredBytes
    {
        get => _transferredBytes;
        set
        {
            if (_transferredBytes != value)
            {
                _transferredBytes = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(FormattedSize));
            }
        }
    }

    private long _totalBytes;
    public long TotalBytes
    {
        get => _totalBytes;
        set
        {
            if (_totalBytes != value)
            {
                _totalBytes = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(FormattedSize));
            }
        }
    }

    private double _progressPercent;
    public double ProgressPercent
    {
        get => _progressPercent;
        set
        {
            if (Math.Abs(_progressPercent - value) > 0.1)
            {
                _progressPercent = value;
                OnPropertyChanged();
            }
        }
    }

    private double _speedBytesPerSec;
    public double SpeedBytesPerSec
    {
        get => _speedBytesPerSec;
        set
        {
            if (Math.Abs(_speedBytesPerSec - value) > 100)
            {
                _speedBytesPerSec = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(FormattedSpeed));
            }
        }
    }

    private string? _errorMessage;
    public string? ErrorMessage
    {
        get => _errorMessage;
        set
        {
            if (_errorMessage != value)
            {
                _errorMessage = value;
                OnPropertyChanged();
            }
        }
    }

    public CancellationTokenSource? Cts { get; set; }
    public long LastSampleBytes { get; set; }
    public DateTime LastSampleTime { get; set; } = DateTime.UtcNow;

    public bool IsRunning => Status == TransferStatus.Running;
    public bool IsPaused => Status == TransferStatus.Paused;
    public bool IsFailed => Status == TransferStatus.Failed;
    public bool IsCompleted => Status == TransferStatus.Completed;

    public string StatusText => Status switch
    {
        TransferStatus.Queued => "Kuyrukta",
        TransferStatus.Running => "Aktarılıyor...",
        TransferStatus.Paused => "Duraklatıldı",
        TransferStatus.Completed => "Tamamlandı",
        TransferStatus.Failed => "Hata",
        TransferStatus.Cancelled => "İptal Edildi",
        _ => ""
    };

    public string FormattedSize
    {
        get
        {
            if (TotalBytes > 0)
            {
                return $"{FormatBytes(TransferredBytes)} / {FormatBytes(TotalBytes)}";
            }
            if (TransferredBytes > 0)
            {
                return FormatBytes(TransferredBytes);
            }
            return "Hesaplanıyor...";
        }
    }

    public string FormattedSpeed
    {
        get
        {
            if (Status != TransferStatus.Running || SpeedBytesPerSec < 1024)
            {
                return "";
            }
            return $"{FormatBytes((long)SpeedBytesPerSec)}/s";
        }
    }

    public static string FormatBytes(long bytes)
    {
        string[] sizes = { "B", "KB", "MB", "GB", "TB" };
        double len = bytes;
        int order = 0;
        while (len >= 1024 && order < sizes.Length - 1)
        {
            order++;
            len /= 1024;
        }
        return $"{len:0.##} {sizes[order]}";
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    protected void OnPropertyChanged([CallerMemberName] string? name = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }
}

public class TransferManager : INotifyPropertyChanged
{
    private static TransferManager? _instance;
    public static TransferManager Instance => _instance ??= new TransferManager();

    public ObservableCollection<TransferItem> Items { get; } = new();

    private readonly SemaphoreSlim _semaphore = new(3, 3);
    private readonly DispatcherQueue? _dispatcherQueue = DispatcherQueue.GetForCurrentThread();

    private int _activeTransfersCount;
    public int ActiveTransfersCount
    {
        get => _activeTransfersCount;
        private set
        {
            if (_activeTransfersCount != value)
            {
                _activeTransfersCount = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(IsTransferring));
                OnPropertyChanged(nameof(BadgeVisibility));
            }
        }
    }

    public bool IsTransferring => ActiveTransfersCount > 0;
    public bool BadgeVisibility => ActiveTransfersCount > 0;

    private TransferManager()
    {
    }

    public TransferItem EnqueueDownload(string fileName, string remotePath, string localPath, WebDAVClient client, long totalBytes = 0)
    {
        var existing = Items.FirstOrDefault(i => i.RemotePath == remotePath && (i.Status == TransferStatus.Running || i.Status == TransferStatus.Queued));
        if (existing != null)
        {
            return existing;
        }

        var item = new TransferItem
        {
            FileName = fileName,
            RemotePath = remotePath,
            LocalPath = localPath,
            Direction = TransferDirection.Download,
            TotalBytes = totalBytes,
            Client = client,
            Status = TransferStatus.Queued
        };

        RunOnUI(() => Items.Insert(0, item));
        UpdateActiveCount();

        _ = ProcessItemAsync(item);
        return item;
    }

    public TransferItem EnqueueUpload(string localPath, string remoteDir, WebDAVClient client)
    {
        var fileName = Path.GetFileName(localPath);
        var targetRemote = remoteDir.TrimEnd('/') + "/" + fileName;

        long size = 0;
        try
        {
            if (File.Exists(localPath))
            {
                size = new FileInfo(localPath).Length;
            }
        }
        catch { }

        var item = new TransferItem
        {
            FileName = fileName,
            RemotePath = targetRemote,
            LocalPath = localPath,
            Direction = TransferDirection.Upload,
            TotalBytes = size,
            Client = client,
            Status = TransferStatus.Queued
        };

        RunOnUI(() => Items.Insert(0, item));
        UpdateActiveCount();

        _ = ProcessItemAsync(item);
        return item;
    }

    private async Task ProcessItemAsync(TransferItem item)
    {
        item.Cts = new CancellationTokenSource();
        var ct = item.Cts.Token;

        await _semaphore.WaitAsync(ct).ConfigureAwait(false);

        try
        {
            if (ct.IsCancellationRequested || item.Status == TransferStatus.Paused || item.Status == TransferStatus.Cancelled)
            {
                return;
            }

            RunOnUI(() =>
            {
                item.Status = TransferStatus.Running;
                item.ErrorMessage = null;
                item.LastSampleTime = DateTime.UtcNow;
                item.LastSampleBytes = item.TransferredBytes;
            });
            UpdateActiveCount();

            if (item.Direction == TransferDirection.Download)
            {
                await ExecuteDownloadAsync(item, ct).ConfigureAwait(false);
            }
            else
            {
                await ExecuteUploadAsync(item, ct).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException)
        {
            // İptal veya duraklatma
        }
        catch (Exception ex)
        {
            RunOnUI(() =>
            {
                item.Status = TransferStatus.Failed;
                item.ErrorMessage = ex.Message;
                item.SpeedBytesPerSec = 0;
            });
        }
        finally
        {
            _semaphore.Release();
            UpdateActiveCount();
        }
    }

    private async Task ExecuteDownloadAsync(TransferItem item, CancellationToken ct)
    {
        if (item.Client == null) throw new InvalidOperationException("WebDAV istemcisi bulunamadı.");

        var parentDir = Path.GetDirectoryName(item.LocalPath);
        if (!string.IsNullOrEmpty(parentDir)) Directory.CreateDirectory(parentDir);

        var tempDest = item.LocalPath + ".part";

        if (item.Client.Config.Protocol == StorageProtocol.SMB)
        {
            var unc = item.Client.GetUncPath(item.RemotePath);
            if (!File.Exists(unc)) throw new FileNotFoundException("SMB kaynak dosyası bulunamadı.", unc);

            var fileInfo = new FileInfo(unc);
            var total = fileInfo.Length;
            RunOnUI(() => item.TotalBytes = total);

            using (var inStream = new FileStream(unc, FileMode.Open, FileAccess.Read, FileShare.Read, 81920, true))
            using (var outStream = new FileStream(tempDest, FileMode.Create, FileAccess.Write, FileShare.None, 81920, true))
            {
                var buffer = new byte[81920];
                int read;
                long transferred = 0;

                while ((read = await inStream.ReadAsync(buffer, 0, buffer.Length, ct).ConfigureAwait(false)) > 0)
                {
                    await outStream.WriteAsync(buffer, 0, read, ct).ConfigureAwait(false);
                    transferred += read;
                    UpdateItemProgress(item, transferred, total);
                }
            }

            if (File.Exists(item.LocalPath)) File.Delete(item.LocalPath);
            File.Move(tempDest, item.LocalPath);

            RunOnUI(() =>
            {
                item.Status = TransferStatus.Completed;
                item.ProgressPercent = 100.0;
                item.SpeedBytesPerSec = 0;
            });
            return;
        }

        var uri = item.Client.BuildUri(item.RemotePath);
        var req = new HttpRequestMessage(HttpMethod.Get, uri);

        using var response = await item.Client.HttpClient.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, ct).ConfigureAwait(false);
        response.EnsureSuccessStatusCode();

        var totalHttp = response.Content.Headers.ContentLength ?? item.TotalBytes;
        RunOnUI(() => item.TotalBytes = totalHttp);

        using (var inStream = await response.Content.ReadAsStreamAsync(ct).ConfigureAwait(false))
        using (var outStream = new FileStream(tempDest, FileMode.Create, FileAccess.Write, FileShare.None, 81920, true))
        {
            var buffer = new byte[81920];
            int read;
            long transferred = 0;

            while ((read = await inStream.ReadAsync(buffer, 0, buffer.Length, ct).ConfigureAwait(false)) > 0)
            {
                await outStream.WriteAsync(buffer, 0, read, ct).ConfigureAwait(false);
                transferred += read;

                UpdateItemProgress(item, transferred, totalHttp);
            }
        }

        if (File.Exists(item.LocalPath)) File.Delete(item.LocalPath);
        File.Move(tempDest, item.LocalPath);

        RunOnUI(() =>
        {
            item.Status = TransferStatus.Completed;
            item.ProgressPercent = 100.0;
            item.SpeedBytesPerSec = 0;
        });
    }

    private async Task ExecuteUploadAsync(TransferItem item, CancellationToken ct)
    {
        if (item.Client == null) throw new InvalidOperationException("WebDAV istemcisi bulunamadı.");
        if (!File.Exists(item.LocalPath)) throw new FileNotFoundException("Yüklenecek yerel dosya bulunamadı.", item.LocalPath);

        var fileInfo = new FileInfo(item.LocalPath);
        var total = fileInfo.Length;
        RunOnUI(() => item.TotalBytes = total);

        if (item.Client.Config.Protocol == StorageProtocol.SMB)
        {
            var unc = item.Client.GetUncPath(item.RemotePath);
            var targetDir = Path.GetDirectoryName(unc);
            if (!string.IsNullOrEmpty(targetDir) && !Directory.Exists(targetDir))
            {
                Directory.CreateDirectory(targetDir);
            }

            var tempDest = unc + ".part";
            using (var inStream = new FileStream(item.LocalPath, FileMode.Open, FileAccess.Read, FileShare.Read, 81920, true))
            using (var outStream = new FileStream(tempDest, FileMode.Create, FileAccess.Write, FileShare.None, 81920, true))
            {
                var buffer = new byte[81920];
                int read;
                long transferred = 0;

                while ((read = await inStream.ReadAsync(buffer, 0, buffer.Length, ct).ConfigureAwait(false)) > 0)
                {
                    await outStream.WriteAsync(buffer, 0, read, ct).ConfigureAwait(false);
                    transferred += read;
                    UpdateItemProgress(item, transferred, total);
                }
            }

            if (File.Exists(unc)) File.Delete(unc);
            File.Move(tempDest, unc);

            RunOnUI(() =>
            {
                item.Status = TransferStatus.Completed;
                item.ProgressPercent = 100.0;
                item.SpeedBytesPerSec = 0;
            });
            return;
        }

        var uri = item.Client.BuildUri(item.RemotePath);

        using var fileStream = new FileStream(item.LocalPath, FileMode.Open, FileAccess.Read, FileShare.Read, 81920, true);
        using var progressContent = new ProgressStreamContent(fileStream, (transferred) =>
        {
            UpdateItemProgress(item, transferred, total);
        }, ct);

        using var response = await item.Client.HttpClient.PutAsync(uri, progressContent, ct).ConfigureAwait(false);
        if (response.IsSuccessStatusCode)
        {
            RunOnUI(() =>
            {
                item.Status = TransferStatus.Completed;
                item.ProgressPercent = 100.0;
                item.SpeedBytesPerSec = 0;
            });
        }
        else
        {
            throw new HttpRequestException($"Sunucu HTTP {(int)response.StatusCode} döndürdü.");
        }
    }

    private void UpdateItemProgress(TransferItem item, long transferred, long total)
    {
        var now = DateTime.UtcNow;
        var dt = (now - item.LastSampleTime).TotalSeconds;

        RunOnUI(() =>
        {
            item.TransferredBytes = transferred;
            if (total > 0)
            {
                item.ProgressPercent = Math.Min(100.0, (double)transferred / total * 100.0);
            }

            if (dt >= 0.7)
            {
                var db = transferred - item.LastSampleBytes;
                if (db >= 0)
                {
                    var currentSpeed = db / dt;
                    item.SpeedBytesPerSec = (item.SpeedBytesPerSec * 0.3) + (currentSpeed * 0.7);
                }
                item.LastSampleBytes = transferred;
                item.LastSampleTime = now;
            }
        });
    }

    public void PauseTask(Guid id)
    {
        var item = Items.FirstOrDefault(i => i.Id == id);
        if (item == null || item.Status != TransferStatus.Running) return;

        item.Cts?.Cancel();
        RunOnUI(() =>
        {
            item.Status = TransferStatus.Paused;
            item.SpeedBytesPerSec = 0;
        });
        UpdateActiveCount();
    }

    public void ResumeTask(Guid id)
    {
        var item = Items.FirstOrDefault(i => i.Id == id);
        if (item == null || item.Status != TransferStatus.Paused) return;

        RunOnUI(() => item.Status = TransferStatus.Queued);
        UpdateActiveCount();
        _ = ProcessItemAsync(item);
    }

    public void CancelTask(Guid id)
    {
        var item = Items.FirstOrDefault(i => i.Id == id);
        if (item == null) return;

        item.Cts?.Cancel();
        RunOnUI(() =>
        {
            item.Status = TransferStatus.Cancelled;
            item.SpeedBytesPerSec = 0;
        });
        UpdateActiveCount();
    }

    public void RetryTask(Guid id)
    {
        var item = Items.FirstOrDefault(i => i.Id == id);
        if (item == null) return;

        RunOnUI(() =>
        {
            item.Status = TransferStatus.Queued;
            item.TransferredBytes = 0;
            item.ProgressPercent = 0;
            item.ErrorMessage = null;
        });
        UpdateActiveCount();
        _ = ProcessItemAsync(item);
    }

    public void ClearCompleted()
    {
        RunOnUI(() =>
        {
            var finished = Items.Where(i => i.Status == TransferStatus.Completed || i.Status == TransferStatus.Cancelled).ToList();
            foreach (var f in finished)
            {
                Items.Remove(f);
            }
        });
        UpdateActiveCount();
    }

    private void UpdateActiveCount()
    {
        RunOnUI(() =>
        {
            ActiveTransfersCount = Items.Count(i => i.Status == TransferStatus.Running || i.Status == TransferStatus.Queued);
        });
    }

    private void RunOnUI(Action action)
    {
        if (_dispatcherQueue != null && !_dispatcherQueue.HasThreadAccess)
        {
            _dispatcherQueue.TryEnqueue(() => action());
        }
        else
        {
            action();
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    protected void OnPropertyChanged([CallerMemberName] string? name = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }
}

/// <summary>
/// Yükleme (PUT) sırasında gerçek zamanlı ilerlemeyi izlemek için özel StreamContent
/// </summary>
public class ProgressStreamContent : HttpContent
{
    private const int BufferSize = 81920;
    private readonly Stream _content;
    private readonly Action<long> _progress;
    private readonly CancellationToken _ct;

    public ProgressStreamContent(Stream content, Action<long> progress, CancellationToken ct)
    {
        _content = content ?? throw new ArgumentNullException(nameof(content));
        _progress = progress ?? throw new ArgumentNullException(nameof(progress));
        _ct = ct;
    }

    protected override async Task SerializeToStreamAsync(Stream stream, System.Net.TransportContext? context)
    {
        var buffer = new byte[BufferSize];
        long totalUploaded = 0;
        int read;

        while ((read = await _content.ReadAsync(buffer, 0, buffer.Length, _ct).ConfigureAwait(false)) > 0)
        {
            await stream.WriteAsync(buffer, 0, read, _ct).ConfigureAwait(false);
            totalUploaded += read;
            _progress(totalUploaded);
        }
    }

    protected override bool TryComputeLength(out long length)
    {
        length = _content.Length;
        return true;
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _content.Dispose();
        }
        base.Dispose(disposing);
    }
}
