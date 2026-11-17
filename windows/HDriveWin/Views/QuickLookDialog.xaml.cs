using System;
using System.IO;
using System.Threading.Tasks;
using Windows.Media.Core;
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

        Title = "";
        PreviewHeaderFileName.Text = item.Name;
        PreviewHeaderMeta.Text = $"{item.TypeDescription} • {item.FormattedSize}";
        PreviewFileName.Text = item.Name;
        PreviewFileType.Text = item.TypeDescription;
        PreviewFileSize.Text = item.FormattedSize;
        PreviewFileDate.Text = item.FormattedDate;
        PreviewLocationText.Text = string.IsNullOrEmpty(item.Path) ? "" : item.Path;

        PreviewGenericGlyph.Glyph = item.GlyphIcon;
        PreviewGenericGlyph.Foreground = item.IconBrush;
        HeaderIconGlyph.Glyph = item.GlyphIcon;
        HeaderIconGlyph.Foreground = item.IconBrush;

        var headerThumb = item.ThumbnailImage ?? item.IconImage;
        if (headerThumb != null)
        {
            PreviewGenericIconImage.Source = headerThumb;
            PreviewGenericIconImage.Visibility = Visibility.Visible;
            PreviewGenericGlyph.Visibility = Visibility.Collapsed;

            HeaderIconImage.Source = headerThumb;
            HeaderIconImage.Visibility = Visibility.Visible;
            HeaderIconGlyph.Visibility = Visibility.Collapsed;
        }

        PrimaryButtonClick += (s, e) =>
        {
            ShouldOpenNatively = true;
        };

        Closing += (s, e) => CleanupMedia();
        Unloaded += (s, e) => CleanupMedia();

        LoadPreview(localFilePath);
    }

    private void CleanupMedia()
    {
        try
        {
            if (PreviewMediaPlayer?.MediaPlayer != null)
            {
                PreviewMediaPlayer.MediaPlayer.Pause();
                PreviewMediaPlayer.Source = null;
            }
        }
        catch { }

        try
        {
            PreviewWebView?.Close();
        }
        catch { }
    }

    private async void LoadPreview(string? localFilePath)
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
                PreviewWebView.Visibility = Visibility.Collapsed;
                PreviewMediaPlayer.Visibility = Visibility.Collapsed;
                return;
            }
            catch { }
        }

        // 2. PDF ve SVG Dosyaları (WebView2 ile Çok Sayfalı Yerel Önizleme)
        if (ext is ".pdf" or ".svg")
        {
            try
            {
                PreviewWebView.Visibility = Visibility.Visible;
                PreviewGenericStack.Visibility = Visibility.Collapsed;
                PreviewImage.Visibility = Visibility.Collapsed;
                PreviewTextScroll.Visibility = Visibility.Collapsed;
                PreviewMediaPlayer.Visibility = Visibility.Collapsed;
                await PreviewWebView.EnsureCoreWebView2Async();
                PreviewWebView.Source = new Uri(localFilePath);
                return;
            }
            catch
            {
                PreviewWebView.Visibility = Visibility.Collapsed;
                PreviewGenericStack.Visibility = Visibility.Visible;
            }
        }

        // 3. Video ve Ses Dosyaları (MediaPlayerElement ile Yerleşik Oynatıcı)
        if (ext is ".mp4" or ".mov" or ".mkv" or ".avi" or ".m4v" or ".wmv" or ".mp3" or ".m4a" or ".wav" or ".flac" or ".aac")
        {
            try
            {
                PreviewMediaPlayer.Source = MediaSource.CreateFromUri(new Uri(localFilePath));
                PreviewMediaPlayer.Visibility = Visibility.Visible;
                PreviewGenericStack.Visibility = Visibility.Collapsed;
                PreviewImage.Visibility = Visibility.Collapsed;
                PreviewTextScroll.Visibility = Visibility.Collapsed;
                PreviewWebView.Visibility = Visibility.Collapsed;
                return;
            }
            catch
            {
                PreviewMediaPlayer.Visibility = Visibility.Collapsed;
                PreviewGenericStack.Visibility = Visibility.Visible;
            }
        }

        // 4. Metin ve Kod Dosyaları
        if (ext is ".txt" or ".json" or ".xml" or ".md" or ".cs" or ".js" or ".ts" or ".html" or ".htm" or ".css" or ".log" or ".yaml" or ".yml" or ".csv" or ".sql" or ".py" or ".swift" or ".sh" or ".bat" or ".ini")
        {
            try
            {
                var fileInfo = new FileInfo(localFilePath);
                if (fileInfo.Length < 1024 * 1024) // 1 MB limit
                {
                    var text = File.ReadAllText(localFilePath);
                    if (text.Length > 12000)
                    {
                        text = text[..12000] + "\n\n... (Daha fazlası için dosyayı açın)";
                    }
                    PreviewTextContent.Text = text;
                    PreviewTextScroll.Visibility = Visibility.Visible;
                    PreviewImage.Visibility = Visibility.Collapsed;
                    PreviewGenericStack.Visibility = Visibility.Collapsed;
                    PreviewWebView.Visibility = Visibility.Collapsed;
                    PreviewMediaPlayer.Visibility = Visibility.Collapsed;
                    return;
                }
            }
            catch { }
        }

        // Varsayılan: Jenerik simge görünümü aktif kalır
    }
}
