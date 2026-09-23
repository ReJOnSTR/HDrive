using System;
using System.IO;
using System.Linq;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using HDriveWin.Models;
using HDriveWin.Services;

namespace HDriveWin.Views;

public sealed partial class SettingsView : UserControl
{
    private readonly Window? _parentWindow;
    public event EventHandler? SettingsSaved;

    public Grid? DragRegion => CustomDragRegion;

    private ServerConfig _editingServer;
    private bool _isNewServer;

    public SettingsView() : this(null)
    {
    }

    public SettingsView(Window? parentWindow)
    {
        _parentWindow = parentWindow;
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
    }

    #region Tab Navigation
    private void TabBtn_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button btn || btn.Tag is not string tag) return;

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
    #endregion

    #region Account & Provider Management
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
                    _editingServer.Region = "us-east-1";
                    break;

                case "SMB":
                    _editingServer.Protocol = StorageProtocol.SMB;
                    _editingServer.Name = "Windows Paylaşımı";
                    _editingServer.ServerURL = "smb://192.168.1.100";
                    break;

                case "WebDAV":
                default:
                    _editingServer.Protocol = StorageProtocol.WebDAV;
                    _editingServer.Name = "WebDAV Deposu";
                    _editingServer.ServerURL = "";
                    break;
            }

            SetupEditPanel();
        }
    }

    private void SetupEditPanel()
    {
        AccountListPanel.Visibility = Visibility.Collapsed;
        AccountSelectProviderPanel.Visibility = Visibility.Collapsed;
        AccountEditPanel.Visibility = Visibility.Visible;

        EditProviderTitleText.Text = _isNewServer ? $"{_editingServer.ProviderName} Kurulumu" : $"{_editingServer.Name} Düzenle";

        ServerNameBox.Text = _editingServer.Name ?? "";
        ServerUrlBox.Text = _editingServer.ServerURL ?? "";
        UsernameBox.Text = _editingServer.Username ?? "";
        PasswordBox.Password = _editingServer.Password ?? "";

        var isOAuth = (_editingServer.Protocol == StorageProtocol.GoogleDrive || _editingServer.Protocol == StorageProtocol.OneDrive);
        OAuthLoginCard.Visibility = isOAuth ? Visibility.Visible : Visibility.Collapsed;
        TraditionalCredentialsPanel.Visibility = isOAuth ? Visibility.Collapsed : Visibility.Visible;

        if (isOAuth)
        {
            OAuthCardBadge.Protocol = _editingServer.Protocol;
            OAuthCardTitle.Text = $"{_editingServer.ProviderName} Hesabınızı Bağlayın";
            OAuthLoginButtonText.Text = string.IsNullOrEmpty(_editingServer.Password) 
                ? $"{_editingServer.ProviderName} ile Giriş Yap" 
                : $"{_editingServer.ProviderName} Hesabını Yeniden Bağla";
            OAuthStatusBadge.Visibility = !string.IsNullOrEmpty(_editingServer.Password) ? Visibility.Visible : Visibility.Collapsed;
            OAuthStatusText.Text = "Oturum Açık & Bağlantı Hazır";
        }
        else
        {
            S3FieldsGrid.Visibility = (_editingServer.Protocol == StorageProtocol.S3) ? Visibility.Visible : Visibility.Collapsed;
            BucketBox.Text = _editingServer.BucketName ?? "";
            RegionBox.Text = string.IsNullOrEmpty(_editingServer.Region) ? "us-east-1" : _editingServer.Region;

            SmbShareBox.Visibility = (_editingServer.Protocol == StorageProtocol.SMB) ? Visibility.Visible : Visibility.Collapsed;
            SmbShareBox.Text = _editingServer.SmbShareName ?? "";

            if (_editingServer.Protocol == StorageProtocol.S3)
            {
                CloudInfoTipBorder.Visibility = Visibility.Visible;
                CloudInfoTipText.Text = "💡 Amazon S3 veya MinIO için Access Key (Kullanıcı Adı) ve Secret Key (Şifre) giriniz.";
            }
            else
            {
                CloudInfoTipBorder.Visibility = Visibility.Collapsed;
            }
        }

        TestResultInfoBar.IsOpen = false;
    }

    private async void OAuthLoginButton_Click(object sender, RoutedEventArgs e)
    {
        OAuthLoginButton.IsEnabled = false;
        TestResultInfoBar.IsOpen = true;
        TestResultInfoBar.Severity = InfoBarSeverity.Informational;
        TestResultInfoBar.Title = "Yetkilendirme Başlatıldı";
        TestResultInfoBar.Message = "Tarayıcınızda giriş ekranı açıldı. Lütfen hesabınızı onaylayın...";

        try
        {
            var (success, token, refreshToken, msg) = await OAuthHelper.StartOAuthLoginAsync(
                _editingServer.Protocol, 
                _editingServer.ClientId, 
                _editingServer.ClientSecret);

            if (success && !string.IsNullOrEmpty(token))
            {
                _editingServer.Password = token;
                if (!string.IsNullOrEmpty(refreshToken))
                {
                    _editingServer.RefreshToken = refreshToken;
                }
                _editingServer.IsConnected = true;

                OAuthStatusBadge.Visibility = Visibility.Visible;
                OAuthStatusText.Text = "Oturum Açık & Bağlantı Hazır";
                OAuthLoginButtonText.Text = $"{_editingServer.ProviderName} Hesabını Yeniden Bağla";

                TestResultInfoBar.Severity = InfoBarSeverity.Success;
                TestResultInfoBar.Title = "Giriş Başarılı";
                TestResultInfoBar.Message = $"✅ {msg} Oturum tokenı kaydedildi.";

                // Otomatik olarak ayarları kaydet ve listeyi güncelle
                SaveAndConnectBtn_Click(sender, e);

                // Giriş tamamlandıktan sonra ayarlar penceresini kapatıp gezginde dosyaları aç
                await Task.Delay(500);
                _parentWindow?.Close();
            }
            else
            {
                TestResultInfoBar.Severity = InfoBarSeverity.Error;
                TestResultInfoBar.Title = "Giriş Başarısız";
                TestResultInfoBar.Message = msg;
            }
        }
        catch (Exception ex)
        {
            TestResultInfoBar.Severity = InfoBarSeverity.Error;
            TestResultInfoBar.Title = "Yetkilendirme Hatası";
            TestResultInfoBar.Message = ex.Message;
        }
        finally
        {
            OAuthLoginButton.IsEnabled = true;
        }
    }

    private void EditServer_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is string serverId)
        {
            var s = CloudreveManager.Instance.Servers.FirstOrDefault(x => x.Id == serverId);
            if (s != null)
            {
                _isNewServer = false;
                _editingServer = s;
                SetupEditPanel();
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
                }

                FooterStatusText.Text = "Bağlantı silindi.";
                SettingsSaved?.Invoke(this, EventArgs.Empty);
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
                // Eğer bu sunucu halihazırda bağlıysa, kullanıcı buton ile BAĞLANTIYI KESER
                if (target.IsConnected)
                {
                    CloudreveManager.Instance.DisconnectServer(target);
                    FooterStatusText.Text = $"{target.Name} bağlantısı kesildi.";
                    ServersListView.ItemsSource = null;
                    ServersListView.ItemsSource = CloudreveManager.Instance.Servers;
                    SettingsSaved?.Invoke(this, EventArgs.Empty);
                    return;
                }

                // Bağlan: Google Drive veya OneDrive oturumu açılmamışsa kurulum formunu aç (kullanıcı butona basacak)
                if ((target.Protocol == StorageProtocol.GoogleDrive || target.Protocol == StorageProtocol.OneDrive) && string.IsNullOrEmpty(target.Password))
                {
                    _isNewServer = false;
                    _editingServer = target;
                    SetupEditPanel();
                    return;
                }

                CloudreveManager.Instance.SetActiveServer(target);
                FooterStatusText.Text = $"{target.Name} bağlandı.";
                ServersListView.ItemsSource = null;
                ServersListView.ItemsSource = CloudreveManager.Instance.Servers;
                SettingsSaved?.Invoke(this, EventArgs.Empty);
            }
        }
    }

    private void SaveAndConnectBtn_Click(object sender, RoutedEventArgs e)
    {
        _editingServer.Name = ServerNameBox.Text.Trim();

        var isOAuth = (_editingServer.Protocol == StorageProtocol.GoogleDrive || _editingServer.Protocol == StorageProtocol.OneDrive);
        if (!isOAuth)
        {
            _editingServer.ServerURL = ServerUrlBox.Text.Trim();
            _editingServer.Username = UsernameBox.Text.Trim();
            _editingServer.Password = PasswordBox.Password;

            if (_editingServer.Protocol == StorageProtocol.S3)
            {
                _editingServer.BucketName = BucketBox.Text.Trim();
                _editingServer.Region = RegionBox.Text.Trim();
            }
            else if (_editingServer.Protocol == StorageProtocol.SMB)
            {
                _editingServer.SmbShareName = SmbShareBox.Text.Trim();
            }
        }

        if (string.IsNullOrWhiteSpace(_editingServer.Name))
        {
            _editingServer.Name = _editingServer.ProviderName;
        }

        CloudreveManager.Instance.SaveServer(_editingServer);
        CloudreveManager.Instance.SetActiveServer(_editingServer);

        ServersListView.ItemsSource = null;
        ServersListView.ItemsSource = CloudreveManager.Instance.Servers;

        AccountListPanel.Visibility = Visibility.Visible;
        AccountSelectProviderPanel.Visibility = Visibility.Collapsed;
        AccountEditPanel.Visibility = Visibility.Collapsed;

        FooterStatusText.Text = $"{_editingServer.Name} kaydedildi ve bağlandı.";
        SettingsSaved?.Invoke(this, EventArgs.Empty);
    }

    private async void TestButton_Click(object sender, RoutedEventArgs e)
    {
        TestButton.IsEnabled = false;
        TestResultInfoBar.IsOpen = false;

        try
        {
            var testConfig = new ServerConfig
            {
                Name = ServerNameBox.Text.Trim(),
                ServerURL = ServerUrlBox.Text.Trim(),
                Username = UsernameBox.Text.Trim(),
                Password = PasswordBox.Password,
                Protocol = _editingServer.Protocol,
                ClientId = _editingServer.ClientId ?? "",
                ClientSecret = _editingServer.ClientSecret ?? "",
                BucketName = BucketBox.Text.Trim(),
                Region = RegionBox.Text.Trim(),
                SmbShareName = SmbShareBox.Text.Trim()
            };

            var client = new WebDAVClient(testConfig);
            var (success, msg) = await client.TestConnectionAsync();

            TestResultInfoBar.Severity = success ? InfoBarSeverity.Success : InfoBarSeverity.Error;
            TestResultInfoBar.Title = success ? "Bağlantı Başarılı" : "Bağlantı Hatası";
            TestResultInfoBar.Message = msg;
            TestResultInfoBar.IsOpen = true;
        }
        catch (Exception ex)
        {
            TestResultInfoBar.Severity = InfoBarSeverity.Error;
            TestResultInfoBar.Title = "Bağlantı Hatası";
            TestResultInfoBar.Message = ex.Message;
            TestResultInfoBar.IsOpen = true;
        }
        finally
        {
            TestButton.IsEnabled = true;
        }
    }
    #endregion

    #region View Settings & Persistence
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

    private void SaveViewSettings()
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
    #endregion

    #region Classic Windows Folder Settings Footer Buttons (Tamam, İptal, Uygula)
    private void OkButton_Click(object sender, RoutedEventArgs e)
    {
        SaveViewSettings();
        SettingsSaved?.Invoke(this, EventArgs.Empty);
        _parentWindow?.Close();
    }

    private void CancelButton_Click(object sender, RoutedEventArgs e)
    {
        _parentWindow?.Close();
    }

    private void ApplyButton_Click(object sender, RoutedEventArgs e)
    {
        SaveViewSettings();
        SettingsSaved?.Invoke(this, EventArgs.Empty);
        FooterStatusText.Text = "Ayarlar başarıyla uygulandı.";
    }
    #endregion
}

/// <summary>
/// Standalone native Windows 11 window hosting SettingsView with custom titlebar, Mica backdrop, and geometry
/// </summary>
public sealed class SettingsWindow : Window
{
    private readonly SettingsView _view;

    public event EventHandler? SettingsSaved
    {
        add => _view.SettingsSaved += value;
        remove => _view.SettingsSaved -= value;
    }

    public SettingsWindow()
    {
        this.Title = "HDrive - Ayarlar";
        _view = new SettingsView(this);
        this.Content = _view;

        SetupWindowGeometry();
        SetupTitleBar();
    }

    private void SetupWindowGeometry()
    {
        try
        {
            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
            var windowId = Microsoft.UI.Win32Interop.GetWindowIdFromWindow(hwnd);
            var appWindow = Microsoft.UI.Windowing.AppWindow.GetFromWindowId(windowId);

            if (appWindow != null)
            {
                const int width = 860;
                const int height = 680;
                appWindow.Resize(new Windows.Graphics.SizeInt32(width, height));

                var displayArea = Microsoft.UI.Windowing.DisplayArea.GetFromWindowId(windowId, Microsoft.UI.Windowing.DisplayAreaFallback.Primary);
                if (displayArea != null)
                {
                    var centeredX = Math.Max(0, (displayArea.WorkArea.Width - width) / 2);
                    var centeredY = Math.Max(0, (displayArea.WorkArea.Height - height) / 2);
                    appWindow.Move(new Windows.Graphics.PointInt32(centeredX, centeredY));
                }
            }
        }
        catch { }

        try
        {
            this.SystemBackdrop = new MicaBackdrop();
        }
        catch { }
    }

    private void SetupTitleBar()
    {
        try
        {
            ExtendsContentIntoTitleBar = true;
            if (_view.DragRegion != null)
            {
                SetTitleBar(_view.DragRegion);
            }
        }
        catch { }

        try
        {
            var baseDir = AppContext.BaseDirectory;
            var iconPath = Path.Combine(baseDir, "app.ico");
            if (File.Exists(iconPath))
            {
                AppWindow?.SetIcon(iconPath);
            }
            else
            {
                AppWindow?.SetIcon("app.ico");
            }
        }
        catch { }
    }
}
