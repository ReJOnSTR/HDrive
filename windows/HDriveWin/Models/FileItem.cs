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

    public string GlyphIcon => IsDirectory ? "\uE8B7" : GetFileIcon(Name); // Windows 11 Segoe Fluent Icons

    public Microsoft.UI.Xaml.Media.SolidColorBrush IconBrush => new(GetFileColor(Name, IsDirectory));

    public string TypeDescription => IsDirectory ? "Klasör" : GetFileTypeDescription(Name);

    public string FormattedDate => ModifiedDate?.ToString("dd.MM.yyyy HH:mm") ?? "-";

    public string Extension => System.IO.Path.GetExtension(Name).ToUpperInvariant();

    public bool IsImage => System.IO.Path.GetExtension(Name).ToLowerInvariant() is ".png" or ".jpg" or ".jpeg" or ".gif" or ".webp" or ".svg" or ".bmp";

    public bool IsPdf => System.IO.Path.GetExtension(Name).ToLowerInvariant() is ".pdf";

    public bool IsText => System.IO.Path.GetExtension(Name).ToLowerInvariant() is ".txt" or ".md" or ".json" or ".xml" or ".log" or ".csv" or ".cs" or ".js" or ".ts" or ".html" or ".css";

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

    private static Windows.UI.Color GetFileColor(string filename, bool isDir)
    {
        if (isDir) return Windows.UI.Color.FromArgb(255, 234, 163, 0); // Windows 11 Warm Amber/Yellow Folder #EAA300

        var ext = System.IO.Path.GetExtension(filename).ToLowerInvariant();
        return ext switch
        {
            ".pdf" => Windows.UI.Color.FromArgb(255, 232, 17, 35), // PDF Kırmızı #E81123
            ".docx" or ".doc" => Windows.UI.Color.FromArgb(255, 24, 90, 189), // Word Mavi #185ABD
            ".xlsx" or ".xls" or ".csv" => Windows.UI.Color.FromArgb(255, 16, 124, 65), // Excel Yeşil #107C41
            ".pptx" or ".ppt" => Windows.UI.Color.FromArgb(255, 196, 62, 28), // PowerPoint Turuncu #C43E1C
            ".zip" or ".rar" or ".7z" or ".tar" or ".gz" => Windows.UI.Color.FromArgb(255, 202, 80, 16), // Zip Kehribar #CA5010
            ".png" or ".jpg" or ".jpeg" or ".gif" or ".webp" or ".svg" => Windows.UI.Color.FromArgb(255, 135, 100, 184), // Görseller Mor #8764B8
            ".mp4" or ".mov" or ".mkv" or ".avi" => Windows.UI.Color.FromArgb(255, 194, 57, 179), // Video Macenta #C239B3
            ".mp3" or ".wav" or ".flac" or ".m4a" => Windows.UI.Color.FromArgb(255, 0, 130, 114), // Müzik Deniz Yeşili #008272
            ".txt" or ".md" or ".json" or ".xml" or ".cs" or ".js" or ".ts" or ".html" or ".css" => Windows.UI.Color.FromArgb(255, 0, 120, 212), // Kod/Metin Mavi #0078D4
            _ => Windows.UI.Color.FromArgb(255, 120, 120, 120)
        };
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
            ".pptx" or ".ppt" => "PowerPoint Sunusu",
            ".zip" or ".rar" or ".7z" => "Sıkıştırılmış Arşiv",
            ".png" or ".jpg" or ".jpeg" or ".gif" or ".webp" => "Görüntü Dosyası",
            ".mp4" or ".mkv" or ".mov" or ".avi" => "Video Dosyası",
            ".mp3" or ".wav" or ".flac" => "Ses Dosyası",
            ".txt" or ".md" => "Metin Belgesi",
            ".json" or ".xml" => "Veri Belgesi",
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
