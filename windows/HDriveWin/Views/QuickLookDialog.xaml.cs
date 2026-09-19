using System;
using System.IO;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using HDriveWin.Models;

namespace HDriveWin.Views;

public sealed partial class QuickLookDialog : ContentDialog
{
    public FileItem Item { get; }
    public bool ShouldOpenNatively { get; private set; }

    public QuickLookDialog(FileItem item, string? localFilePath = null)
    {
        InitializeComponent();
        Item = item;

        Title = $"Hızlı Bakış - {item.Name}";
        PreviewFileName.Text = item.Name;
        PreviewFileType.Text = item.TypeDescription;
        PreviewFileSize.Text = $"Boyut: {item.FormattedSize}";
        PreviewFileDate.Text = $"Değiştirilme: {item.FormattedDate}";

        PreviewGenericGlyph.Glyph = item.GlyphIcon;
        PreviewGenericGlyph.Foreground = item.IconBrush;

        if (item.IconImage != null)
        {
            PreviewGenericIconImage.Source = item.IconImage;
            PreviewGenericIconImage.Visibility = Visibility.Visible;
            PreviewGenericGlyph.Visibility = Visibility.Collapsed;
        }

        PrimaryButtonClick += (s, e) =>
        {
            ShouldOpenNatively = true;
        };

        LoadPreview(localFilePath);
    }

    private void LoadPreview(string? localFilePath)
    {
        if (string.IsNullOrEmpty(localFilePath) || !File.Exists(localFilePath))
        {
            return;
        }

        var ext = Path.GetExtension(localFilePath).ToLowerInvariant();
        if (string.IsNullOrEmpty(ext))
        {
            ext = Path.GetExtension(Item.Name).ToLowerInvariant();
        }

        // 1. Resim Dosyaları
        if (ext is ".png" or ".jpg" or ".jpeg" or ".bmp" or ".gif" or ".webp" or ".ico")
        {
            try
            {
                var bitmap = new BitmapImage(new Uri(localFilePath));
                PreviewImage.Source = bitmap;
                PreviewImage.Visibility = Visibility.Visible;
                PreviewGenericStack.Visibility = Visibility.Collapsed;
                PreviewTextScroll.Visibility = Visibility.Collapsed;
                return;
            }
            catch { }
        }

        // 2. Metin ve Kod Dosyaları
        if (ext is ".txt" or ".json" or ".xml" or ".md" or ".cs" or ".js" or ".ts" or ".html" or ".css" or ".log" or ".yaml" or ".yml" or ".csv" or ".sql" or ".py" or ".swift")
        {
            try
            {
                var fileInfo = new FileInfo(localFilePath);
                if (fileInfo.Length < 1024 * 500) // 500 KB limit
                {
                    var text = File.ReadAllText(localFilePath);
                    if (text.Length > 8000)
                    {
                        text = text[..8000] + "\n\n... (Daha fazlası için dosyayı açın)";
                    }
                    PreviewTextContent.Text = text;
                    PreviewTextScroll.Visibility = Visibility.Visible;
                    PreviewImage.Visibility = Visibility.Collapsed;
                    PreviewGenericStack.Visibility = Visibility.Collapsed;
                    return;
                }
            }
            catch { }
        }

        // Varsayılan: Jenerik simge görünümü aktif kalır
    }
}
