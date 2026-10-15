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

    public string DirectionGlyph => Direction == TransferDirection.Upload ? "\uE895" : "\uE896";
    public string DirectionTooltip => Direction == TransferDirection.Upload ? "Yükleme (Upload)" : "İndirme (Download)";

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
        var existing = Items.FirstOrDefault(i => i.Direction == TransferDirection.Download && i.Client?.Config.Id == client.Config.Id && i.Client?.Config.ServerURL == client.Config.ServerURL && i.LocalPath == localPath && i.RemotePath == remotePath && (i.Status == TransferStatus.Running || i.Status == TransferStatus.Queued));
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

        var acquired = false;
        try
        {
            await _semaphore.WaitAsync(ct).ConfigureAwait(false);
            acquired = true;
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
            if (acquired) _semaphore.Release();
            UpdateActiveCount();
        }
    }

    private async Task ExecuteDownloadAsync(TransferItem item, CancellationToken ct)
    {
        if (item.Client == null) throw new InvalidOperationException("İstemci bulunamadı.");
        var progress = new Progress<TransferProgress>(p => UpdateItemProgress(item, p.TransferredBytes, p.TotalBytes));
        await item.Client.DownloadToAsync(item.RemotePath, item.LocalPath, progress, ct, item.FileName).ConfigureAwait(false);
        Complete(item);
    }

    private async Task ExecuteUploadAsync(TransferItem item, CancellationToken ct)
    {
        if (item.Client == null) throw new InvalidOperationException("İstemci bulunamadı.");
        var progress = new Progress<TransferProgress>(p => UpdateItemProgress(item, p.TransferredBytes, p.TotalBytes));
        var separator = item.RemotePath.LastIndexOf('/');
        var directory = separator < 0 ? "" : item.RemotePath[..separator];
        await item.Client.UploadAsync(item.LocalPath, directory, progress, ct).ConfigureAwait(false);
        Complete(item);
    }

    private void Complete(TransferItem item) => RunOnUI(() =>
    {
        item.Status = TransferStatus.Completed;
        item.ProgressPercent = 100;
        item.SpeedBytesPerSec = 0;
    });

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
        if (item == null || item.Status is not (TransferStatus.Failed or TransferStatus.Cancelled)) return;

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
