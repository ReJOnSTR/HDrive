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

    private bool _isEditing;
    public bool IsEditing
    {
        get => _isEditing;
        set
        {
            if (SetProperty(ref _isEditing, value))
            {
                OnPropertyChanged(nameof(EditingVisibility));
                OnPropertyChanged(nameof(NormalVisibility));
            }
        }
    }

    private string _editingName = string.Empty;
    public string EditingName
    {
        get => _editingName;
        set => SetProperty(ref _editingName, value);
    }

    private bool _isCut;
    public bool IsCut
    {
        get => _isCut;
        set
        {
            if (SetProperty(ref _isCut, value))
            {
                OnPropertyChanged(nameof(Opacity));
            }
        }
    }

    public double Opacity => IsCut ? 0.45 : 1.0;

    public Microsoft.UI.Xaml.Visibility EditingVisibility =>
        IsEditing ? Microsoft.UI.Xaml.Visibility.Visible : Microsoft.UI.Xaml.Visibility.Collapsed;

    public Microsoft.UI.Xaml.Visibility NormalVisibility =>
        IsEditing ? Microsoft.UI.Xaml.Visibility.Collapsed : Microsoft.UI.Xaml.Visibility.Visible;

    public Microsoft.UI.Xaml.Media.Imaging.BitmapImage? IconImage =>
        Services.FileIconService.GetIcon(Name, IsDirectory, large: true);

    public Microsoft.UI.Xaml.Media.Imaging.BitmapImage? IconImageSmall =>
        Services.FileIconService.GetIcon(Name, IsDirectory, large: false);

    public Microsoft.UI.Xaml.Visibility HasIconImageVisibility =>
        IconImage != null ? Microsoft.UI.Xaml.Visibility.Visible : Microsoft.UI.Xaml.Visibility.Collapsed;

    public Microsoft.UI.Xaml.Visibility HasNoIconImageVisibility =>
        IconImage != null ? Microsoft.UI.Xaml.Visibility.Collapsed : Microsoft.UI.Xaml.Visibility.Visible;

    public string GlyphIcon => IsDirectory ? "\uE8B7" : GetFileIcon(Name); // Windows 11 Segoe Fluent Icons Fallback

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
            ".fig" or ".figjam" => Windows.UI.Color.FromArgb(255, 242, 78, 30), // Figma Turuncu/Kırmızı #F24E1E
            ".psd" or ".psb" => Windows.UI.Color.FromArgb(255, 49, 168, 255), // Photoshop Camgöbeği #31A8FF
            ".ai" or ".eps" => Windows.UI.Color.FromArgb(255, 255, 154, 0), // Illustrator Sarı/Turuncu #FF9A00
            ".sketch" => Windows.UI.Color.FromArgb(255, 253, 179, 0), // Sketch Kehribar #FDB300
            _ => Windows.UI.Color.FromArgb(255, 120, 120, 120)
        };
    }

    private static string GetFileIcon(string filename)
    {
        var ext = System.IO.Path.GetExtension(filename).ToLowerInvariant();
        return ext switch
        {
            ".pdf" => "\uEA90",
            ".docx" or ".doc" or ".rtf" => "\uE8A5",
            ".xlsx" or ".xls" or ".csv" or ".xlsm" => "\uE9F9", // Excel Tablo / Çalışma Sayfası (Segoe Fluent Icons)
            ".pptx" or ".ppt" => "\uE8B9",
            ".fig" or ".figjam" or ".sketch" => "\uE790", // Design Icon (Palette/Shape)
            ".psd" or ".psb" or ".ai" or ".eps" => "\uEB9F", // Image Design
            ".zip" or ".rar" or ".7z" or ".tar" or ".gz" => "\uE8B7",
            ".png" or ".jpg" or ".jpeg" or ".gif" or ".webp" or ".svg" or ".bmp" => "\uEB9F",
            ".mp4" or ".mov" or ".mkv" or ".avi" or ".wmv" => "\uE714",
            ".mp3" or ".wav" or ".flac" or ".m4a" => "\uEC4F",
            ".txt" or ".log" => "\uE8C4",
            ".json" or ".xml" or ".html" or ".css" or ".js" or ".ts" or ".cs" => "\uE943",
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
            ".fig" or ".figjam" => "Figma Tasarım Dosyası",
            ".psd" or ".psb" => "Adobe Photoshop Belgesi",
            ".ai" or ".eps" => "Adobe Illustrator Belgesi",
            ".sketch" => "Sketch Tasarım Dosyası",
            ".zip" or ".rar" or ".7z" => "Sıkıştırılmış Arşiv",
            ".png" or ".jpg" or ".jpeg" or ".gif" or ".webp" => "Görüntü Dosyası",
            ".mp4" or ".mkv" or ".mov" or ".avi" => "Video Dosyası",
            ".mp3" or ".wav" or ".flac" => "Ses Dosyası",
            ".txt" or ".md" => "Metin Belgesi",
            ".json" or ".xml" => "Veri Belgesi",
            _ => "Dosya"
        };
    }

    // Paylaşılan Liste Sütun Genişlikleri ve Görünürlükleri (Windows 11 Gezgin Uyumu)
    private static Microsoft.UI.Xaml.GridLength _sharedColDateWidth = new(180);
    public static Microsoft.UI.Xaml.GridLength SharedColDateWidth
    {
        get => _sharedColDateWidth;
        set => _sharedColDateWidth = value;
    }

    private static Microsoft.UI.Xaml.GridLength _sharedColTypeWidth = new(140);
    public static Microsoft.UI.Xaml.GridLength SharedColTypeWidth
    {
        get => _sharedColTypeWidth;
        set => _sharedColTypeWidth = value;
    }

    private static Microsoft.UI.Xaml.GridLength _sharedColSizeWidth = new(100);
    public static Microsoft.UI.Xaml.GridLength SharedColSizeWidth
    {
        get => _sharedColSizeWidth;
        set => _sharedColSizeWidth = value;
    }

    private static Microsoft.UI.Xaml.Visibility _sharedColDateVisibility = Microsoft.UI.Xaml.Visibility.Visible;
    public static Microsoft.UI.Xaml.Visibility SharedColDateVisibility
    {
        get => _sharedColDateVisibility;
        set => _sharedColDateVisibility = value;
    }

    private static Microsoft.UI.Xaml.Visibility _sharedColTypeVisibility = Microsoft.UI.Xaml.Visibility.Visible;
    public static Microsoft.UI.Xaml.Visibility SharedColTypeVisibility
    {
        get => _sharedColTypeVisibility;
        set => _sharedColTypeVisibility = value;
    }

    private static Microsoft.UI.Xaml.Visibility _sharedColSizeVisibility = Microsoft.UI.Xaml.Visibility.Visible;
    public static Microsoft.UI.Xaml.Visibility SharedColSizeVisibility
    {
        get => _sharedColSizeVisibility;
        set => _sharedColSizeVisibility = value;
    }

    public Microsoft.UI.Xaml.GridLength ColDateWidth => SharedColDateWidth;
    public Microsoft.UI.Xaml.GridLength ColTypeWidth => SharedColTypeWidth;
    public Microsoft.UI.Xaml.GridLength ColSizeWidth => SharedColSizeWidth;

    public Microsoft.UI.Xaml.GridLength ColDateSplitterWidth => _sharedColDateVisibility == Microsoft.UI.Xaml.Visibility.Visible ? new(6) : new(0);
    public Microsoft.UI.Xaml.GridLength ColTypeSplitterWidth => _sharedColTypeVisibility == Microsoft.UI.Xaml.Visibility.Visible ? new(6) : new(0);
    public Microsoft.UI.Xaml.GridLength ColSizeSplitterWidth => _sharedColSizeVisibility == Microsoft.UI.Xaml.Visibility.Visible ? new(6) : new(0);

    public Microsoft.UI.Xaml.Visibility ColDateVisibility => SharedColDateVisibility;
    public Microsoft.UI.Xaml.Visibility ColTypeVisibility => SharedColTypeVisibility;
    public Microsoft.UI.Xaml.Visibility ColSizeVisibility => SharedColSizeVisibility;

    public void NotifyColumnSettingsChanged()
    {
        OnPropertyChanged(nameof(ColDateWidth));
        OnPropertyChanged(nameof(ColTypeWidth));
        OnPropertyChanged(nameof(ColSizeWidth));
        OnPropertyChanged(nameof(ColDateSplitterWidth));
        OnPropertyChanged(nameof(ColTypeSplitterWidth));
        OnPropertyChanged(nameof(ColSizeSplitterWidth));
        OnPropertyChanged(nameof(ColDateVisibility));
        OnPropertyChanged(nameof(ColTypeVisibility));
        OnPropertyChanged(nameof(ColSizeVisibility));
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
