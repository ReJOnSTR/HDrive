using System;
using Windows.ApplicationModel.DataTransfer;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using HDriveWin.Models;

namespace HDriveWin.Views;

public sealed partial class FilePropertiesDialog : ContentDialog
{
    private readonly FileItem _item;

    public FilePropertiesDialog(FileItem item)
    {
        _item = item;
        this.InitializeComponent();

        PropFileName.Text = item.Name;
        PropFileType.Text = item.TypeDescription;
        PropLocation.Text = item.Path;
        PropSize.Text = item.IsDirectory ? "--" : $"{item.FormattedSize} ({item.Size:N0} bayt)";
        PropModified.Text = item.FormattedDate;

        if (item.IconImage != null)
        {
            PropIconImage.Source = item.IconImage;
            PropIconImage.Visibility = Visibility.Visible;
            PropGlyphIcon.Visibility = Visibility.Collapsed;
        }
        else
        {
            PropIconImage.Visibility = Visibility.Collapsed;
            PropGlyphIcon.Glyph = item.GlyphIcon;
            PropGlyphIcon.Foreground = item.IconBrush;
            PropGlyphIcon.Visibility = Visibility.Visible;
        }
    }

    private void CopyPathButton_Click(object sender, RoutedEventArgs e)
    {
        var package = new DataPackage();
        package.SetText(_item.Path);
        Clipboard.SetContent(package);

        CopyPathButton.Content = "Kopyalandı ✓";
    }
}
