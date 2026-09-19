using System;
using System.IO;
using System.Linq;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using HDriveWin.Models;
using HDriveWin.Services;

namespace HDriveWin.Views;

public sealed partial class SettingsDialog : ContentDialog
{
    private ServerConfig _editingServer;
    private bool _isNewServer;

    public SettingsDialog()
    {
        this.InitializeComponent();
        _editingServer = CloudreveManager.Instance.ActiveServer ?? new ServerConfig();

        ServersListView.ItemsSource = CloudreveManager.Instance.Servers;

        if (CloudreveManager.Instance.Servers.Count == 0)
        {
            AccountListPanel.Visibility = Visibility.Collapsed;
            AccountSelectProviderPanel.Visibility = Visibility.Visible;
            AccountEditPanel.Visibility = Visibility.Collapsed;
        }

        LoadViewSettings();

        this.PrimaryButtonClick += SettingsDialog_PrimaryButtonClick;
    }

    private void AddConnectionButton_Click(object sender, RoutedEventArgs e)
    {
        AccountListPanel.Visibility = Visibility.Collapsed;
        AccountSelectProviderPanel.Visibility = Visibility.Visible;
        AccountEditPanel.Visibility = Visibility.Collapsed;
    }

    private void BackToConnections_Click(object sender, RoutedEventArgs e)
    {
        AccountListPanel.Visibility = Visibility.Visible;
        AccountSelectProviderPanel.Visibility = Visibility.Collapsed;
        AccountEditPanel.Visibility = Visibility.Collapsed;
    }

    private void BackFromEdit_Click(object sender, RoutedEventArgs e)
    {
        if (_isNewServer)
        {
            AccountListPanel.Visibility = Visibility.Collapsed;
            AccountSelectProviderPanel.Visibility = Visibility.Visible;
            AccountEditPanel.Visibility = Visibility.Collapsed;
        }
        else
        {
            AccountListPanel.Visibility = Visibility.Visible;
            AccountSelectProviderPanel.Visibility = Visibility.Collapsed;
            AccountEditPanel.Visibility = Visibility.Collapsed;
        }
    }

    private void CancelEditBtn_Click(object sender, RoutedEventArgs e)
    {
        BackFromEdit_Click(sender, e);
    }

    private void ProviderTile_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is string tagStr)
        {
            _isNewServer = true;
            _editingServer = new ServerConfig();

            switch (tagStr)
            {
                case "GoogleDrive":
                    _editingServer.Protocol = StorageProtocol.GoogleDrive;
                    _editingServer.Name = "Google Drive";
                    _editingServer.ServerURL = "https://www.googleapis.com/drive/v3";
                    _editingServer.ClientId = OAuthHelper.GetDefaultGoogleClientId();
                    _editingServer.ClientSecret = OAuthHelper.GetDefaultGoogleClientSecret();
                    break;
                case "OneDrive":
                    _editingServer.Protocol = StorageProtocol.OneDrive;
                    _editingServer.Name = "OneDrive";
                    _editingServer.ServerURL = "https://graph.microsoft.com/v1.0/me/drive";
                    _editingServer.ClientId = OAuthHelper.DefaultOneDriveClientId;
                    break;
                case "S3":
                    _editingServer.Protocol = StorageProtocol.S3;
                    _editingServer.Name = "Amazon S3";
                    _editingServer.ServerURL = "https://s3.amazonaws.com";
                    break;
                case "SMB":
                    _editingServer.Protocol = StorageProtocol.SMB;
                    _editingServer.Name = "SMB Paylaşımı";
                    _editingServer.ServerURL = "smb://";
                    break;
                default:
                    _editingServer.Protocol = StorageProtocol.WebDAV;
                    _editingServer.Name = "WebDAV Sürücüsü";
                    _editingServer.ServerURL = "https://";
                    break;
            }

            LoadServerIntoForm(_editingServer);

            AccountListPanel.Visibility = Visibility.Collapsed;
            AccountSelectProviderPanel.Visibility = Visibility.Collapsed;
            AccountEditPanel.Visibility = Visibility.Visible;
        }
    }

    private void EditServer_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is string id)
        {
            var target = CloudreveManager.Instance.Servers.FirstOrDefault(s => s.Id == id);
            if (target != null)
            {
                _isNewServer = false;
                _editingServer = target;
                LoadServerIntoForm(target);

                AccountListPanel.Visibility = Visibility.Collapsed;
                AccountSelectProviderPanel.Visibility = Visibility.Collapsed;
                AccountEditPanel.Visibility = Visibility.Visible;
            }
        }
    }

    private void ConnectServer_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is string id)
        {
            var target = CloudreveManager.Instance.Servers.FirstOrDefault(s => s.Id == id);
            if (target != null)
            {
                if (CloudreveManager.Instance.ActiveServer?.Id == target.Id)
                {
                    CloudreveManager.Instance.DisconnectActiveServer();
                }
                else
                {
                    CloudreveManager.Instance.SetActiveServer(target);
                }
                // Listeyi yenile
                ServersListView.ItemsSource = null;
                ServersListView.ItemsSource = CloudreveManager.Instance.Servers;
            }
        }
    }

    private void DeleteServer_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is string id)
        {
            var target = CloudreveManager.Instance.Servers.FirstOrDefault(s => s.Id == id);
            if (target != null)
            {
                CloudreveManager.Instance.DeleteServer(target);
                ServersListView.ItemsSource = null;
                ServersListView.ItemsSource = CloudreveManager.Instance.Servers;

                if (CloudreveManager.Instance.Servers.Count == 0)
                {
                    AccountListPanel.Visibility = Visibility.Collapsed;
                    AccountSelectProviderPanel.Visibility = Visibility.Visible;
                    AccountEditPanel.Visibility = Visibility.Collapsed;
                }
            }
        }
    }

    private void LoadServerIntoForm(ServerConfig s)
    {
        EditProviderTitleText.Text = $"{s.ProviderName} Yapılandırması";
        ServerNameBox.Text = s.Name;
        ServerUrlBox.Text = s.ServerURL;
        UsernameBox.Text = s.Username;
        PasswordBox.Password = s.Password;
        BucketBox.Text = s.BucketName;
        RegionBox.Text = string.IsNullOrEmpty(s.Region) ? "us-east-1" : s.Region;
        SmbShareBox.Text = s.SmbShareName;

        S3FieldsGrid.Visibility = (s.Protocol == StorageProtocol.S3) ? Visibility.Visible : Visibility.Collapsed;
        SmbShareBox.Visibility = (s.Protocol == StorageProtocol.SMB) ? Visibility.Visible : Visibility.Collapsed;

        var isCloud = (s.Protocol == StorageProtocol.GoogleDrive || s.Protocol == StorageProtocol.OneDrive);
        OAuthFieldsGrid.Visibility = Visibility.Collapsed; // Teknik OAuth kutucukları gizlendi, arka planda hazır yüklenir
        ClientIdBox.Text = s.ClientId ?? "";
        ClientSecretBox.Password = s.ClientSecret ?? "";

        CloudInfoTipBorder.Visibility = isCloud ? Visibility.Visible : Visibility.Collapsed;
        if (isCloud)
        {
            CloudInfoTipText.Text = $"💡 {s.ProviderName} doğrudan API tokenı veya OAuth Client ID ile yetkilendirilebilir.";
        }

        TestResultInfoBar.IsOpen = false;
    }

    private void SaveAndConnectBtn_Click(object sender, RoutedEventArgs e)
    {
        _editingServer.Name = ServerNameBox.Text.Trim();
        _editingServer.ServerURL = ServerUrlBox.Text.Trim();
        _editingServer.Username = UsernameBox.Text.Trim();
        _editingServer.Password = PasswordBox.Password;
        _editingServer.BucketName = BucketBox.Text.Trim();
        _editingServer.Region = RegionBox.Text.Trim();
        _editingServer.SmbShareName = SmbShareBox.Text.Trim();
        _editingServer.ClientId = ClientIdBox.Text.Trim();
        _editingServer.ClientSecret = ClientSecretBox.Password;

        CloudreveManager.Instance.SaveServer(_editingServer);
        CloudreveManager.Instance.SetActiveServer(_editingServer);

        // Listeyi güncelle
        ServersListView.ItemsSource = null;
        ServersListView.ItemsSource = CloudreveManager.Instance.Servers;

        AccountListPanel.Visibility = Visibility.Visible;
        AccountSelectProviderPanel.Visibility = Visibility.Collapsed;
        AccountEditPanel.Visibility = Visibility.Collapsed;
    }

    private async void TestButton_Click(object sender, RoutedEventArgs e)
    {
        TestButton.IsEnabled = false;
        TestResultInfoBar.IsOpen = false;

        var tempConfig = new ServerConfig
        {
            Name = ServerNameBox.Text.Trim(),
            ServerURL = ServerUrlBox.Text.Trim(),
            Username = UsernameBox.Text.Trim(),
            Password = PasswordBox.Password,
            Protocol = _editingServer.Protocol,
            BucketName = BucketBox.Text.Trim(),
            Region = RegionBox.Text.Trim(),
            SmbShareName = SmbShareBox.Text.Trim(),
            ClientId = ClientIdBox.Text.Trim(),
            ClientSecret = ClientSecretBox.Password
        };

        if (tempConfig.Protocol == StorageProtocol.GoogleDrive || tempConfig.Protocol == StorageProtocol.OneDrive)
        {
            await System.Threading.Tasks.Task.Delay(300);
            TestResultInfoBar.Severity = InfoBarSeverity.Success;
            TestResultInfoBar.Title = "Bağlantı Profili Hazır";
            TestResultInfoBar.Message = $"{tempConfig.ProviderName} bağlantı ve kimlik doğrulama profili hazır.";
            TestResultInfoBar.IsOpen = true;
            TestButton.IsEnabled = true;
            return;
        }

        var client = new WebDAVClient(tempConfig);
        var (success, msg) = await client.TestConnectionAsync();

        TestResultInfoBar.Severity = success ? InfoBarSeverity.Success : InfoBarSeverity.Error;
        TestResultInfoBar.Title = success ? "Bağlantı Başarılı" : "Bağlantı Hatası";
        TestResultInfoBar.Message = msg;
        TestResultInfoBar.IsOpen = true;
        TestButton.IsEnabled = true;
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

        if (tag == "Account")
        {
            AccountListPanel.Visibility = Visibility.Visible;
            AccountSelectProviderPanel.Visibility = Visibility.Collapsed;
            AccountEditPanel.Visibility = Visibility.Collapsed;
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

    private void SettingsDialog_PrimaryButtonClick(ContentDialog sender, ContentDialogButtonClickEventArgs args)
    {
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
}
