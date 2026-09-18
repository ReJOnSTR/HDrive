using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using HDriveWin.Models;

namespace HDriveWin.Views;

public sealed partial class ProviderLogoBadge : UserControl
{
    public static readonly DependencyProperty ProtocolProperty =
        DependencyProperty.Register(
            nameof(Protocol),
            typeof(StorageProtocol),
            typeof(ProviderLogoBadge),
            new PropertyMetadata(StorageProtocol.WebDAV, OnProtocolChanged));

    public static readonly DependencyProperty ProviderTagProperty =
        DependencyProperty.Register(
            nameof(ProviderTag),
            typeof(string),
            typeof(ProviderLogoBadge),
            new PropertyMetadata(null, OnProviderTagChanged));

    public static readonly DependencyProperty BadgeSizeProperty =
        DependencyProperty.Register(
            nameof(BadgeSize),
            typeof(double),
            typeof(ProviderLogoBadge),
            new PropertyMetadata(36.0, OnBadgeSizeChanged));

    public static readonly DependencyProperty ShowBadgeProperty =
        DependencyProperty.Register(
            nameof(ShowBadge),
            typeof(bool),
            typeof(ProviderLogoBadge),
            new PropertyMetadata(true, OnShowBadgeChanged));

    public StorageProtocol Protocol
    {
        get => (StorageProtocol)GetValue(ProtocolProperty);
        set => SetValue(ProtocolProperty, value);
    }

    public string? ProviderTag
    {
        get => (string?)GetValue(ProviderTagProperty);
        set => SetValue(ProviderTagProperty, value);
    }

    public double BadgeSize
    {
        get => (double)GetValue(BadgeSizeProperty);
        set => SetValue(BadgeSizeProperty, value);
    }

    public bool ShowBadge
    {
        get => (bool)GetValue(ShowBadgeProperty);
        set => SetValue(ShowBadgeProperty, value);
    }

    public ProviderLogoBadge()
    {
        this.InitializeComponent();
        UpdateSize();
        UpdateVisibility();
    }

    private static void OnProtocolChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is ProviderLogoBadge badge)
        {
            badge.UpdateVisibility();
        }
    }

    private static void OnProviderTagChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is ProviderLogoBadge badge && e.NewValue is string tagStr)
        {
            badge.Protocol = tagStr switch
            {
                "GoogleDrive" => StorageProtocol.GoogleDrive,
                "OneDrive" => StorageProtocol.OneDrive,
                "S3" => StorageProtocol.S3,
                "SMB" => StorageProtocol.SMB,
                _ => StorageProtocol.WebDAV
            };
        }
    }

    private static void OnBadgeSizeChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is ProviderLogoBadge badge)
        {
            badge.UpdateSize();
        }
    }

    private static void OnShowBadgeChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is ProviderLogoBadge badge)
        {
            badge.UpdateBadgeStyle();
        }
    }

    private void UpdateSize()
    {
        if (BadgeBorder == null || GoogleDriveLogo == null) return;

        var size = BadgeSize > 0 ? BadgeSize : 36.0;
        BadgeBorder.Width = size;
        BadgeBorder.Height = size;

        // İkon boyutu rozetin yaklaşık %65-%70'i oranında şık ve dengeli ölçeklenir
        var iconSize = ShowBadge ? size * 0.65 : size;
        GoogleDriveLogo.Width = iconSize;
        GoogleDriveLogo.Height = iconSize;
        OneDriveLogo.Width = iconSize;
        OneDriveLogo.Height = iconSize;
        WebDAVLogo.Width = iconSize;
        WebDAVLogo.Height = iconSize;
        S3Logo.Width = iconSize;
        S3Logo.Height = iconSize;
        SMBLogo.Width = iconSize;
        SMBLogo.Height = iconSize;
    }

    private void UpdateBadgeStyle()
    {
        if (BadgeBorder == null) return;

        if (!ShowBadge)
        {
            BadgeBorder.Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
            BadgeBorder.BorderBrush = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
            BadgeBorder.Padding = new Thickness(0);
        }
    }

    private void UpdateVisibility()
    {
        if (GoogleDriveLogo == null) return;

        GoogleDriveLogo.Visibility = Protocol == StorageProtocol.GoogleDrive ? Visibility.Visible : Visibility.Collapsed;
        OneDriveLogo.Visibility = Protocol == StorageProtocol.OneDrive ? Visibility.Visible : Visibility.Collapsed;
        WebDAVLogo.Visibility = Protocol == StorageProtocol.WebDAV ? Visibility.Visible : Visibility.Collapsed;
        S3Logo.Visibility = Protocol == StorageProtocol.S3 ? Visibility.Visible : Visibility.Collapsed;
        SMBLogo.Visibility = Protocol == StorageProtocol.SMB ? Visibility.Visible : Visibility.Collapsed;
    }
}
