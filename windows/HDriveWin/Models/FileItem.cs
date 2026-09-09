using System;
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace HDriveWin.Models;

public class FileItem : INotifyPropertyChanged
{
    private string _name = string.Empty;
    public string Name
    {
        get => _name;
        set => SetProperty(ref _name, value);
    }

    private string _path = string.Empty;
    public string Path
    {
        get => _path;
        set => SetProperty(ref _path, value);
    }

    private bool _isDirectory;
    public bool IsDirectory
    {
        get => _isDirectory;
        set
        {
            if (SetProperty(ref _isDirectory, value))
            {
                OnPropertyChanged(nameof(GlyphIcon));
                OnPropertyChanged(nameof(TypeDescription));
            }
        }
    }

    private long _size;
    public long Size
    {
        get => _size;
        set
        {
            if (SetProperty(ref _size, value))
            {
                OnPropertyChanged(nameof(FormattedSize));
            }
        }
    }

    private DateTime? _modifiedDate;
    public DateTime? ModifiedDate
    {
        get => _modifiedDate;
        set
        {
            if (SetProperty(ref _modifiedDate, value))
            {
                OnPropertyChanged(nameof(FormattedDate));
            }
        }
    }

    public string GlyphIcon => IsDirectory ? "\uE8B7" : GetFileIcon(Name); // Segoe Fluent Icons

    public string TypeDescription => IsDirectory ? "Klasör" : GetFileTypeDescription(Name);

    public string FormattedDate => ModifiedDate?.ToString("dd.MM.yyyy HH:mm") ?? "-";

    public string FormattedSize
    {
        get
        {
            if (IsDirectory) return "--";
            if (Size < 1024) return $"{Size} B";
            if (Size < 1024 * 1024) return $"{(Size / 1024.0):F1} KB";
            if (Size < 1024 * 1024 * 1024) return $"{(Size / (1024.0 * 1024.0)):F1} MB";
            return $"{(Size / (1024.0 * 1024.0 * 1024.0)):F2} GB";
        }
    }

    private static string GetFileIcon(string filename)
    {
        var ext = System.IO.Path.GetExtension(filename).ToLowerInvariant();
        return ext switch
        {
            ".pdf" => "\uEA90",
            ".docx" or ".doc" => "\uE8A5",
            ".xlsx" or ".xls" => "\uF1C5",
            ".pptx" or ".ppt" => "\uE8B9",
            ".zip" or ".rar" or ".7z" or ".tar" or ".gz" => "\uF012",
            ".png" or ".jpg" or ".jpeg" or ".gif" or ".webp" or ".svg" => "\uEB9F",
            ".mp4" or ".mov" or ".mkv" or ".avi" => "\uE714",
            ".mp3" or ".wav" or ".flac" or ".m4a" => "\uEC4F",
            ".txt" or ".md" or ".json" or ".xml" => "\uE8C4",
            _ => "\uE8A5"
        };
    }

    private static string GetFileTypeDescription(string filename)
    {
        var ext = System.IO.Path.GetExtension(filename).ToLowerInvariant();
        return ext switch
        {
            ".pdf" => "PDF Belgesi",
            ".docx" or ".doc" => "Word Belgesi",
            ".xlsx" or ".xls" => "Excel Çalışma Sayfası",
            ".zip" or ".rar" or ".7z" => "Sıkıştırılmış Arşiv",
            ".png" or ".jpg" or ".jpeg" => "Görüntü Dosyası",
            ".mp4" or ".mkv" => "Video Dosyası",
            ".mp3" => "Ses Dosyası",
            _ => "Dosya"
        };
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    protected bool SetProperty<T>(ref T storage, T value, [CallerMemberName] string? propertyName = null)
    {
        if (Equals(storage, value)) return false;
        storage = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    protected void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
