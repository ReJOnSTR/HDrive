using System;
using System.Diagnostics;
using System.IO;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage.Streams;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using HDriveWin.Services;

namespace HDriveWin.Views;

public sealed partial class LocalShareDialog : ContentDialog
{
    private readonly string _url;

    public LocalShareDialog()
    {
        this.InitializeComponent();

        LocalShareService.Instance.Start();
        _url = LocalShareService.Instance.GetLocalUrl();
        UrlTextBlock.Text = _url;

        LoadQrCode();
    }

    private async void LoadQrCode()
    {
        try
        {
            var svg = SimpleQrGenerator.GenerateSvg(_url, 220);
            using var stream = new InMemoryRandomAccessStream();
            using (var writer = new DataWriter(stream))
            {
                writer.WriteString(svg);
                await writer.StoreAsync();
            }
            stream.Seek(0);

            var svgSource = new SvgImageSource();
            await svgSource.SetSourceAsync(stream);
            QrImage.Source = svgSource;
        }
        catch { }
    }

    private void CopyButton_Click(object sender, RoutedEventArgs e)
    {
        var package = new DataPackage();
        package.SetText(_url);
        Clipboard.SetContent(package);
    }

    private void OpenBrowser_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = _url,
                UseShellExecute = true
            });
        }
        catch { }
    }

    private void OpenFolder_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var path = LocalShareService.Instance.SharedFolderPath;
            Directory.CreateDirectory(path);
            Process.Start(new ProcessStartInfo
            {
                FileName = "explorer.exe",
                Arguments = $"\"{path}\"",
                UseShellExecute = true
            });
        }
        catch { }
    }
}
