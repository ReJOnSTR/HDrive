using System;
using System.IO;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using HDriveWin.Models;
using HDriveWin.Services;

namespace HDriveWin.Views;

public sealed partial class SettingsDialog : ContentDialog
{
    private readonly ServerConfig _config;

    public SettingsDialog()
    {
        this.InitializeComponent();
        _config = CloudreveManager.Instance.ActiveServer;

        ServerUrlBox.Text = _config.ServerURL;
        UsernameBox.Text = _config.Username;
        PasswordBox.Password = _config.Password;

        ProtocolComboBox.SelectedIndex = _config.Protocol switch
        {
            StorageProtocol.S3 => 1,
            StorageProtocol.SMB => 2,
            _ => 0
        };
        BucketBox.Text = _config.BucketName;
        RegionBox.Text = string.IsNullOrEmpty(_config.Region) ? "us-east-1" : _config.Region;
        SmbShareBox.Text = _config.SmbShareName;
        UpdateProtocolFieldsVisibility();

        UpdateServerStatusBadge();

        LoadViewSettings();

        this.PrimaryButtonClick += SettingsDialog_PrimaryButtonClick;
    }

    private void UpdateServerStatusBadge()
    {
        if (string.IsNullOrWhiteSpace(_config.ServerURL))
        {
            StatusDot.Fill = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 140, 140, 140));
            StatusBadgeText.Text = "Bağlantı Yok";
            AccountStatusSubtext.Text = "Henüz bir WebDAV sunucusu bağlanmadı.";
        }
        else
        {
            StatusDot.Fill = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 16, 124, 65));
            StatusBadgeText.Text = "Bağlandı";
            AccountStatusSubtext.Text = _config.ServerURL;
        }
    }

    private string GetViewSettingsFilePath()
    {
        var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HDrive");
        Directory.CreateDirectory(dir);
        return Path.Combine(dir, "view_settings.json");
    }

    private void LoadViewSettings()
    {
        try
        {
            var filePath = GetViewSettingsFilePath();
            if (File.Exists(filePath))
            {
                var json = File.ReadAllText(filePath).Trim();
                var vSettings = System.Text.Json.JsonSerializer.Deserialize<MainWindow.ViewSettingsModel>(json);
                if (vSettings != null)
                {
                    PreviewPaneToggleSwitch.IsOn = vSettings.ShowPreviewPane;
                    DefaultViewComboBox.SelectedIndex = vSettings.ViewMode switch
                    {
                        MainWindow.ExplorerViewMode.Medium => 1,
                        MainWindow.ExplorerViewMode.Details => 2,
                        _ => 0
                    };
                    return;
                }
            }
        }
        catch { }

        DefaultViewComboBox.SelectedIndex = 0;
        PreviewPaneToggleSwitch.IsOn = false;
    }

    private void TabBtn_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is string tag)
        {
            SwitchTab(tag);
        }
    }

    private void SwitchTab(string tag)
    {
        PanelAccount.Visibility = (tag == "Account") ? Visibility.Visible : Visibility.Collapsed;
        PanelView.Visibility = (tag == "View") ? Visibility.Visible : Visibility.Collapsed;
        PanelAbout.Visibility = (tag == "About") ? Visibility.Visible : Visibility.Collapsed;

        var selectedBrush = (Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"];
        var transparentBrush = new SolidColorBrush(Microsoft.UI.Colors.Transparent);

        TabBtnAccount.Background = (tag == "Account") ? selectedBrush : transparentBrush;
        TabBtnView.Background = (tag == "View") ? selectedBrush : transparentBrush;
        TabBtnAbout.Background = (tag == "About") ? selectedBrush : transparentBrush;
    }

    private void SettingsDialog_PrimaryButtonClick(ContentDialog sender, ContentDialogButtonClickEventArgs args)
    {
        _config.ServerURL = ServerUrlBox.Text.Trim();
        _config.Username = UsernameBox.Text.Trim();
        _config.Password = PasswordBox.Password;
        _config.Protocol = ProtocolComboBox.SelectedIndex switch
        {
            1 => StorageProtocol.S3,
            2 => StorageProtocol.SMB,
            _ => StorageProtocol.WebDAV
        };
        _config.BucketName = BucketBox.Text.Trim();
        _config.Region = RegionBox.Text.Trim();
        _config.SmbShareName = SmbShareBox.Text.Trim();

        CloudreveManager.Instance.SaveConfig(_config);

        // Görünüm tercihlerini de kaydet
        try
        {
            var filePath = GetViewSettingsFilePath();
            MainWindow.ViewSettingsModel vSettings;
            if (File.Exists(filePath))
            {
                var json = File.ReadAllText(filePath).Trim();
                vSettings = System.Text.Json.JsonSerializer.Deserialize<MainWindow.ViewSettingsModel>(json) ?? new MainWindow.ViewSettingsModel();
            }
            else
            {
                vSettings = new MainWindow.ViewSettingsModel();
            }

            vSettings.ShowPreviewPane = PreviewPaneToggleSwitch.IsOn;
            vSettings.ViewMode = DefaultViewComboBox.SelectedIndex switch
            {
                1 => MainWindow.ExplorerViewMode.Medium,
                2 => MainWindow.ExplorerViewMode.Details,
                _ => MainWindow.ExplorerViewMode.Large
            };

            var outJson = System.Text.Json.JsonSerializer.Serialize(vSettings, new System.Text.Json.JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(filePath, outJson);
        }
        catch { }
    }

    private async void TestButton_Click(object sender, RoutedEventArgs e)
    {
        TestButton.IsEnabled = false;
        TestResultInfoBar.IsOpen = false;

        var tempConfig = new ServerConfig
        {
            ServerURL = ServerUrlBox.Text.Trim(),
            Username = UsernameBox.Text.Trim(),
            Password = PasswordBox.Password
        };

        var client = new WebDAVClient(tempConfig);
        var (success, msg) = await client.TestConnectionAsync();

        TestResultInfoBar.Severity = success ? InfoBarSeverity.Success : InfoBarSeverity.Error;
        TestResultInfoBar.Title = success ? "Bağlantı Başarılı" : "Bağlantı Hatası";
        TestResultInfoBar.Message = msg;
        TestResultInfoBar.IsOpen = true;

        if (success)
        {
            StatusDot.Fill = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 16, 124, 65));
            StatusBadgeText.Text = "Bağlandı";
            AccountStatusSubtext.Text = tempConfig.ServerURL;
        }
        else
        {
            StatusDot.Fill = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 196, 43, 28));
            StatusBadgeText.Text = "Başarısız";
        }

        TestButton.IsEnabled = true;
    }

    private void ProtocolComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        UpdateProtocolFieldsVisibility();
    }

    private void UpdateProtocolFieldsVisibility()
    {
        if (S3FieldsGrid == null || SmbShareBox == null) return;
        var idx = ProtocolComboBox.SelectedIndex;
        S3FieldsGrid.Visibility = (idx == 1) ? Visibility.Visible : Visibility.Collapsed;
        SmbShareBox.Visibility = (idx == 2) ? Visibility.Visible : Visibility.Collapsed;
    }
}
