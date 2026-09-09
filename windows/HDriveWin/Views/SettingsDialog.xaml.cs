using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using HDriveWin.Models;
using HDriveWin.Services;
using System;

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

        SyncToggle.IsOn = FolderSyncEngine.Instance.IsSyncEnabled;
        SyncStatusText.Text = $"Durum: {FolderSyncEngine.Instance.SyncStatus}";

        this.PrimaryButtonClick += SettingsDialog_PrimaryButtonClick;
    }

    private void SettingsDialog_PrimaryButtonClick(ContentDialog sender, ContentDialogButtonClickEventArgs args)
    {
        _config.ServerURL = ServerUrlBox.Text.Trim();
        _config.Username = UsernameBox.Text.Trim();
        _config.Password = PasswordBox.Password;
        _config.AutoSyncEnabled = SyncToggle.IsOn;

        CloudreveManager.Instance.SaveConfig(_config);
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
        TestResultInfoBar.Title = success ? "Başarılı" : "Hata";
        TestResultInfoBar.Message = msg;
        TestResultInfoBar.IsOpen = true;

        TestButton.IsEnabled = true;
    }

    private void SyncToggle_Toggled(object sender, RoutedEventArgs e)
    {
        FolderSyncEngine.Instance.IsSyncEnabled = SyncToggle.IsOn;
        SyncStatusText.Text = $"Durum: {FolderSyncEngine.Instance.SyncStatus}";
    }

    private void OpenFolder_Click(object sender, RoutedEventArgs e)
    {
        FolderSyncEngine.Instance.OpenLocalFolderInExplorer();
    }

    private async void SyncNow_Click(object sender, RoutedEventArgs e)
    {
        SyncStatusText.Text = "Durum: Eşitleniyor...";
        await FolderSyncEngine.Instance.SyncNowAsync();
        SyncStatusText.Text = $"Durum: {FolderSyncEngine.Instance.SyncStatus}";
    }
}
