using System.Diagnostics;
using HDriveWin.Models;
using HDriveWin.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.ApplicationModel.DataTransfer;

namespace HDriveWin;

public sealed partial class MainWindow
{
    private async void ConnectSystemDrive_Click(object sender, RoutedEventArgs e)
    {
        var account = CloudreveManager.Instance.ActiveServer; if (account == null) return;
        try { Process.Start(new ProcessStartInfo(new WebDAVClient(account).SystemConnectionTarget()) { UseShellExecute = true }); }
        catch (Exception error) { await ShowOperationErrorAsync("Sistem bağlantısı", error.Message); }
    }
    private void FileActions_Opening(object sender, object e)
    {
        var protocol = CloudreveManager.Instance.ActiveServer?.Protocol;
        var cloud = protocol is StorageProtocol.GoogleDrive or StorageProtocol.OneDrive;
        var selected = GetSelectedItems();
        CloudSharingMenuItem.IsEnabled = cloud && selected.Count == 1;
        CloudVersionsMenuItem.IsEnabled = cloud && selected.Count == 1 && !selected[0].IsDirectory;
        SaveOfflineMenuItem.IsEnabled = selected.Any(item => !item.IsDirectory);
    }

    private void TransferPause_Click(object sender, RoutedEventArgs e) {
        if (sender is FrameworkElement element && element.Tag is Guid id) TransferManager.Instance.PauseTask(id);
    }
    private void TransferResume_Click(object sender, RoutedEventArgs e) {
        if (sender is FrameworkElement element && element.Tag is Guid id) TransferManager.Instance.ResumeTask(id);
    }

    private async void Workspace_Click(object sender, RoutedEventArgs e)
    {
        var panel = new StackPanel { Spacing = 12, MinWidth = 400 };
        var status = new TextBlock { TextWrapping = TextWrapping.Wrap };
        var usage = new TextBlock { TextWrapping = TextWrapping.Wrap };
        void ReloadUsage() {
            var entries = WorkingCache.Entries();
            usage.Text = $"Önbellek: {TransferItem.FormatBytes(entries.Sum(item => item.Bytes))} · Korunan: {TransferItem.FormatBytes(entries.Where(item => item.Protected).Sum(item => item.Bytes))}";
        }
        try { ReloadUsage(); } catch (Exception error) { status.Text = error.Message; }
        panel.Children.Add(usage);
        panel.Children.Add(new TextBlock { Text = "Harici uygulamada açılan çalışma kopyaları temizlenmez.", TextWrapping = TextWrapping.Wrap });
        var limit = new ComboBox { Header = "Önbellek boyut sınırı", ItemsSource = new[] { "256 MB", "1 GB", "5 GB" }, SelectedIndex = 1 };
        panel.Children.Add(limit);
        var trim = new Button { Content = "Sınıra Göre Temizle" };
        trim.Click += (_, _) => {
            try { WorkingCache.LimitBytes = (limit.SelectedIndex == 0 ? 256L : limit.SelectedIndex == 2 ? 5120L : 1024L) * 1024 * 1024; WorkingCache.Trim(WorkingCache.LimitBytes); ReloadUsage(); status.Text = "Önbellek temizlendi."; }
            catch (Exception error) { status.Text = error.Message; }
        };
        panel.Children.Add(trim);
        var clear = new Button { Content = "Temizlenebilir Önbelleği Sil" };
        clear.Click += (_, _) => { try { WorkingCache.Trim(0); ReloadUsage(); } catch (Exception error) { status.Text = error.Message; } };
        panel.Children.Add(clear);
        panel.Children.Add(new TextBlock { Text = "Çevrimdışı Dosyalar", FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });
        try {
            var entries = OfflineLibrary.Entries();
            if (entries.Count == 0) panel.Children.Add(new TextBlock { Text = "Dosya menüsünden Çevrimdışı Kaydet'i seçin.", TextWrapping = TextWrapping.Wrap });
            foreach (var entry in entries) {
                var button = new Button { Content = entry.AccountName + " · " + entry.Name };
                button.Click += (_, _) => { try { Process.Start(new ProcessStartInfo(entry.LocalPath) { UseShellExecute = true }); } catch (Exception error) { status.Text = error.Message; } };
                panel.Children.Add(button);
            }
        } catch (Exception error) { status.Text = error.Message; }
        panel.Children.Add(status);
        await new ContentDialog { Title = "Dosyalar ve Depolama", CloseButtonText = "Kapat", Content = new ScrollViewer { Content = panel, MaxHeight = 520 }, XamlRoot = Content.XamlRoot }.ShowAsync();
    }
    private async void SaveOffline_Click(object sender, RoutedEventArgs e)
    {
        var account = CloudreveManager.Instance.ActiveServer;
        if (account == null) return;
        var client = new WebDAVClient(account);
        var errors = new List<string>();
        foreach (var item in GetSelectedItems()) {
            if (item.IsDirectory) { errors.Add(item.Name + ": Klasörün içindeki dosyaları seçin."); continue; }
            try {
                var target = OfflineLibrary.Destination(account, item.Path, item.Name);
                TransferManager.Instance.EnqueueDownload(item.Name, item.Path, target, client, item.Size);
            } catch (Exception error) { errors.Add(item.Name + ": " + error.Message); }
        }
        if (errors.Count > 0) await ShowOperationErrorAsync("Çevrimdışı kaydetme", string.Join("\n", errors));
        else TransferFlyout.ShowAt(TransferButton);
    }
    private async void CloudSharing_Click(object sender, RoutedEventArgs e)
    {
        var item = GetSelectedItems().FirstOrDefault();
        var account = CloudreveManager.Instance.ActiveServer;
        if (item == null || account == null) return;
        var client = new WebDAVClient(account);
        var panel = new StackPanel { Spacing = 12, MinWidth = 400 };
        var output = new TextBox { IsReadOnly = true, TextWrapping = TextWrapping.Wrap, Header = "Bağlantı" };
        var status = new TextBlock { TextWrapping = TextWrapping.Wrap };
        var publicAccess = new CheckBox { Content = "Bağlantıya sahip herkes görüntüleyebilsin" };
        panel.Children.Add(new TextBlock { Text = "İşaretlenmezse mevcut erişim izinleri değişmez.", TextWrapping = TextWrapping.Wrap });
        panel.Children.Add(publicAccess);
        var create = new Button { Content = "Görüntüleme Bağlantısı Al" };
        create.Click += async (_, _) => {
            create.IsEnabled = false;
            try {
                var url = await client.ReadOnlyLinkAsync(item.Path, publicAccess.IsChecked == true);
                output.Text = url.AbsoluteUri; status.Text = "Bağlantı hazır.";
            } catch (Exception error) { status.Text = error.Message; }
            finally { create.IsEnabled = true; }
        };
        var copy = new Button { Content = "Bağlantıyı Kopyala" };
        copy.Click += (_, _) => {
            if (string.IsNullOrEmpty(output.Text)) return;
            var data = new DataPackage(); data.SetText(output.Text); Clipboard.SetContent(data); status.Text = "Bağlantı kopyalandı.";
        };
        var revoke = new Button { Content = "Herkese Açık Bağlantıları Kaldır" };
        revoke.Click += async (_, _) => {
            revoke.IsEnabled = false;
            try { await client.RevokePublicLinksAsync(item.Path); output.Text = ""; status.Text = "Herkese açık bağlantılar kaldırıldı."; }
            catch (Exception error) { status.Text = error.Message; }
            finally { revoke.IsEnabled = true; }
        };
        panel.Children.Add(create); panel.Children.Add(output); panel.Children.Add(copy); panel.Children.Add(revoke); panel.Children.Add(status);
        await new ContentDialog { Title = item.Name + " · Paylaşım", CloseButtonText = "Kapat", Content = panel, XamlRoot = Content.XamlRoot }.ShowAsync();
    }
    private async void CloudVersions_Click(object sender, RoutedEventArgs e)
    {
        var item = GetSelectedItems().FirstOrDefault(); var account = CloudreveManager.Instance.ActiveServer;
        if (item == null || account == null) return;
        var panel = new StackPanel { Spacing = 12, MinWidth = 400 };
        var status = new TextBlock { TextWrapping = TextWrapping.Wrap };
        var confirm = new CheckBox { Content = "Seçilen sürümün güncel dosyanın yerine geçmesini onaylıyorum" };
        panel.Children.Add(confirm); panel.Children.Add(status);
        var client = new WebDAVClient(account);
        var dialog = new ContentDialog { Title = "Sürüm Geçmişi · " + item.Name, CloseButtonText = "Kapat", Content = new ScrollViewer { Content = panel, MaxHeight = 450 }, XamlRoot = Content.XamlRoot };
        dialog.Opened += async (_, _) => {
            try {
                var versions = await client.VersionsAsync(item.Path);
                if (versions.Count == 0) status.Text = "Sağlayıcı bu dosya için sürüm döndürmedi.";
                foreach (var version in versions) {
                    var row = new StackPanel { Spacing = 4 };
                    row.Children.Add(new TextBlock { Text = version.Id + " · " + version.Modified });
                    if (version.CanRestore) {
                        var restore = new Button { Content = "Bu Sürümü Geri Yükle" };
                        restore.Click += async (_, _) => {
                            if (confirm.IsChecked != true) { status.Text = "Önce geri yüklemeyi onaylayın."; return; }
                            restore.IsEnabled = false;
                            try { await client.RestoreVersionAsync(item.Path, version.Id); status.Text = "Sürüm geri yüklendi."; }
                            catch (Exception error) { status.Text = error.Message; }
                            finally { restore.IsEnabled = true; }
                        };
                        row.Children.Add(restore);
                    }
                    panel.Children.Add(row);
                }
                if (account.Protocol == StorageProtocol.GoogleDrive) status.Text = "Google Drive sürümleri burada listelenir; geri yükleme Google Drive üzerinden yapılır.";
            } catch (Exception error) { status.Text = error.Message; }
        };
        await dialog.ShowAsync();
    }
    private async void CloudTrash_Click(object sender, RoutedEventArgs e)
    {
        var account = CloudreveManager.Instance.ActiveServer;
        if (account == null) return;
        var client = new WebDAVClient(account); var panel = new StackPanel { Spacing = 12, MinWidth = 400 };
        var status = new TextBlock { TextWrapping = TextWrapping.Wrap }; panel.Children.Add(status);
        var dialog = new ContentDialog { Title = "Google Drive Çöp Kutusu", CloseButtonText = "Kapat", Content = new ScrollViewer { Content = panel, MaxHeight = 450 }, XamlRoot = Content.XamlRoot };
        dialog.Opened += async (_, _) => {
            try {
                var items = await client.TrashedFilesAsync();
                if (items.Count == 0) status.Text = "Çöp kutusu boş.";
                foreach (var item in items) {
                    var restore = new Button { Content = item.Name + " · Geri Yükle" };
                    restore.Click += async (_, _) => {
                        restore.IsEnabled = false;
                        try { await client.RestoreTrashAsync(item.Id); panel.Children.Remove(restore); }
                        catch (Exception error) { status.Text = error.Message; restore.IsEnabled = true; }
                    };
                    panel.Children.Add(restore);
                }
            } catch (Exception error) { status.Text = error.Message; }
        };
        await dialog.ShowAsync();
    }

    private async void FolderSync_Click(object sender, RoutedEventArgs e)
    {
        var account = CloudreveManager.Instance.ActiveServer; if (account == null) return;
        var identity = WebDAVClient.StorageIdentity(account);
        var remoteRoot = _currentPath; string? localRoot = null;
        using var cancellation = new CancellationTokenSource();
        var token = cancellation.Token;
        var busy = false;
        FolderSynchronizer? engine = null; List<SyncRow> rows = new();
        var panel = new StackPanel { Spacing = 12, MinWidth = 450 };
        var local = new TextBlock { Text = "Yerel klasör seçilmedi", TextWrapping = TextWrapping.Wrap };
        var exclusions = new TextBox { Header = "Hariç tutulanlar (; ile ayırın)", Text = ".git/**;node_modules/**;*.tmp;*.part" };
        var policy = new ComboBox { Header = "Çakışma kararı", ItemsSource = new[] { "Çakışmaları Atla", "Yereli Kullan", "Bulutu Kullan", "İkisini Koru" }, SelectedIndex = 0 };
        var automatic = new CheckBox { Content = "Bu ekran açıkken her dakika eşitle" };
        var status = new TextBox { IsReadOnly = true, AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, MaxHeight = 220,
            Text = "Önce değişiklikleri tarayın. Otomatik turda çakışmalar atlanır; silmeler otomatik yayılmaz." };
        var choose = new Button { Content = "Yerel Klasör Seç" };
        var preview = new Button { Content = "Değişiklikleri Tara" };
        var apply = new Button { Content = "Seçilen Kararla Eşitle", IsEnabled = false };
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMinutes(1) };
        void SetBusy(bool value) {
            busy = value;
            preview.IsEnabled = choose.IsEnabled = exclusions.IsEnabled = policy.IsEnabled = !value;
            apply.IsEnabled = !value && engine != null && rows.Any(row => row.Action != SyncAction.None);
        }
        async Task RunAsync(bool applyChanges, bool automaticCycle) {
            if (busy || token.IsCancellationRequested) return;
            if (localRoot == null) { if (!automaticCycle) status.Text = "Önce yerel klasörü seçin."; return; }
            var owner = CloudreveManager.Instance.Servers.FirstOrDefault(server => server.Id == account.Id && server.IsConnected && WebDAVClient.StorageIdentity(server) == identity);
            if (owner == null) { timer.Stop(); automatic.IsChecked = false; status.Text = "Eşitleme durdu: hesabı yeniden bağlayın."; return; }
            SetBusy(true);
            try {
                if (!applyChanges || automaticCycle) {
                    engine = new FolderSynchronizer(new WebDAVClient(owner), localRoot, remoteRoot, exclusions.Text);
                    rows = await engine.PreviewAsync(token);
                    status.Text = string.Join("\n", rows.Where(row => row.Action != SyncAction.None).Select(row => row.Action + " · " + row.RelativePath));
                    if (string.IsNullOrEmpty(status.Text)) status.Text = "Klasörler eşit.";
                }
                if (applyChanges && engine != null) {
                    var decision = automaticCycle ? SyncConflictPolicy.Skip : (SyncConflictPolicy)policy.SelectedIndex;
                    var errors = await engine.ApplyAsync(rows, decision, token);
                    status.Text = errors.Count == 0 ? "Eşitleme tamamlandı. Çakışmalar ve silmeler karar için bekletilir." : string.Join("\n", errors);
                    engine = null; rows.Clear();
                }
            } catch (OperationCanceledException) { }
            catch (Exception error) { status.Text = error.Message; engine = null; rows.Clear(); }
            finally { SetBusy(false); }
        }
        choose.Click += async (_, _) => {
            if (busy || token.IsCancellationRequested) return;
            SetBusy(true);
            try {
                var picker = new Windows.Storage.Pickers.FolderPicker(); picker.FileTypeFilter.Add("*");
                WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(this));
                var folder = await picker.PickSingleFolderAsync(); if (folder == null || token.IsCancellationRequested) return;
                localRoot = folder.Path; local.Text = localRoot; engine = null; rows.Clear();
            } catch (Exception error) { status.Text = error.Message; }
            finally { SetBusy(false); }
        };
        exclusions.TextChanged += (_, _) => { engine = null; rows.Clear(); apply.IsEnabled = false; };
        preview.Click += async (_, _) => await RunAsync(false, false);
        apply.Click += async (_, _) => await RunAsync(true, false);
        timer.Tick += async (_, _) => { if (automatic.IsChecked == true) await RunAsync(true, true); };
        automatic.Checked += (_, _) => timer.Start();
        automatic.Unchecked += (_, _) => timer.Stop();
        panel.Children.Add(new TextBlock { Text = account.Name + " · seçili bulut klasörü" });
        foreach (var element in new FrameworkElement[] { local, choose, exclusions, policy, automatic,
            new TextBlock { Text = "Ekranı kapatmak otomatik eşitlemeyi durdurur.", TextWrapping = TextWrapping.Wrap }, preview, apply, status }) panel.Children.Add(element);
        var dialog = new ContentDialog { Title = "Klasör Eşitleme", CloseButtonText = "Kapat", Content = new ScrollViewer { Content = panel, MaxHeight = 550 }, XamlRoot = Content.XamlRoot };
        dialog.Closed += (_, _) => { timer.Stop(); cancellation.Cancel(); };
        try { await dialog.ShowAsync(); }
        finally { timer.Stop(); cancellation.Cancel(); }
    }

}
