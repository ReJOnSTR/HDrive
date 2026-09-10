using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage;
using Windows.Storage.Pickers;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using HDriveWin.Models;
using HDriveWin.Services;
using HDriveWin.Views;

namespace HDriveWin;

public sealed partial class MainWindow : Window
{
    private readonly ObservableCollection<FileItem> _items = new();
    private readonly List<FileItem> _allItems = new();
    private readonly ObservableCollection<string> _breadcrumbs = new();

    private string _currentPath = "";
    private readonly List<string> _history = new();
    private int _historyIndex = -1;

    private FileItem? _selectedItem;

    public MainWindow()
    {
        this.InitializeComponent();

        SetupTitleBar();

        FileGridView.ItemsSource = _items;
        FileGridViewMedium.ItemsSource = _items;
        FileListView.ItemsSource = _items;
        PathBreadcrumbBar.ItemsSource = _breadcrumbs;

        // Başlangıç sekmesi oluştur
        CreateInitialTab();

        // Ctrl+T (Yeni Sekme) ve Ctrl+W (Sekmeyi Kapat) klavye kısayolları
        var newTabAccelerator = new Microsoft.UI.Xaml.Input.KeyboardAccelerator
        {
            Key = Windows.System.VirtualKey.T,
            Modifiers = Windows.System.VirtualKeyModifiers.Control
        };
        newTabAccelerator.Invoked += (s, e) => { OpenNewTab(""); e.Handled = true; };
        this.Content.KeyboardAccelerators.Add(newTabAccelerator);

        var closeTabAccelerator = new Microsoft.UI.Xaml.Input.KeyboardAccelerator
        {
            Key = Windows.System.VirtualKey.W,
            Modifiers = Windows.System.VirtualKeyModifiers.Control
        };
        closeTabAccelerator.Invoked += (s, e) => { CloseCurrentTab(); e.Handled = true; };
        this.Content.KeyboardAccelerators.Add(closeTabAccelerator);

        // Senkronizasyon durumunu dinle
        FolderSyncEngine.Instance.PropertyChanged += (s, e) =>
        {
            if (e.PropertyName == nameof(FolderSyncEngine.SyncStatus))
            {
                DispatcherQueue.TryEnqueue(() =>
                {
                    SyncStatusText.Text = $"Eşitleme: {FolderSyncEngine.Instance.SyncStatus}";
                });
            }
        };

        NavView.SelectedItem = CloudreveNavItem;
    }

    #region Windows 11 Sekme (TabView) Yönetimi

    public void OpenNewTab(string path = "")
    {
        var state = new ExplorerTabState
        {
            CurrentPath = path,
            History = new List<string> { path },
            HistoryIndex = 0
        };
        var folderName = string.IsNullOrEmpty(path) ? "Cloudreve" : Path.GetFileName(path.TrimEnd('/'));
        var isRoot = string.IsNullOrEmpty(path);

        var newTab = new TabViewItem
        {
            Header = folderName,
            IconSource = new FontIconSource
            {
                Glyph = isRoot ? "\uE753" : "\uE8B7",
                Foreground = isRoot 
                    ? new SolidColorBrush(Windows.UI.Color.FromArgb(255, 0, 120, 212)) 
                    : new SolidColorBrush(Windows.UI.Color.FromArgb(255, 234, 163, 0))
            },
            Tag = state,
            IsClosable = true
        };
        ExplorerTabs.TabItems.Add(newTab);
        ExplorerTabs.SelectedItem = newTab;

        _currentPath = state.CurrentPath;
        _history.Clear();
        _history.AddRange(state.History);
        _historyIndex = state.HistoryIndex;

        UpdateNavigationButtons();
        UpdateBreadcrumbs(_currentPath);
        _ = LoadDirectoryAsync(_currentPath);
    }

    public void CloseCurrentTab()
    {
        if (ExplorerTabs.SelectedItem is TabViewItem currentTab && ExplorerTabs.TabItems.Count > 1)
        {
            var index = ExplorerTabs.TabItems.IndexOf(currentTab);
            ExplorerTabs.TabItems.Remove(currentTab);
            var newIndex = Math.Clamp(index, 0, ExplorerTabs.TabItems.Count - 1);
            ExplorerTabs.SelectedIndex = newIndex;
        }
    }

    private void CreateInitialTab()
    {
        OpenNewTab("");
    }

    private void ExplorerTabs_AddTabButtonClick(TabView sender, object args)
    {
        OpenNewTab("");
    }

    private void ExplorerTabs_TabCloseRequested(TabView sender, TabViewTabCloseRequestedEventArgs args)
    {
        if (sender.TabItems.Count > 1)
        {
            var index = sender.TabItems.IndexOf(args.Tab);
            var isSelected = sender.SelectedItem is TabViewItem sel && sel == args.Tab;
            sender.TabItems.Remove(args.Tab);
            if (isSelected && sender.TabItems.Count > 0)
            {
                var newIndex = Math.Clamp(index, 0, sender.TabItems.Count - 1);
                sender.SelectedIndex = newIndex;
            }
        }
    }

    private void ExplorerTabs_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (ExplorerTabs.SelectedItem is TabViewItem tab && tab.Tag is ExplorerTabState state)
        {
            if (_currentPath != state.CurrentPath || _items.Count == 0)
            {
                _currentPath = state.CurrentPath;
                _history.Clear();
                _history.AddRange(state.History);
                _historyIndex = state.HistoryIndex;

                UpdateNavigationButtons();
                UpdateBreadcrumbs(_currentPath);
                _ = LoadDirectoryAsync(_currentPath);
            }
        }
    }

    #endregion

    private void SetupTitleBar()
    {
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(CustomDragRegion);
        try
        {
            AppWindow.SetIcon("app.ico");
        }
        catch { }
    }

    private async void NavigateToPath(string path, bool addToHistory = true)
    {
        _currentPath = path;

        if (addToHistory)
        {
            if (_historyIndex < _history.Count - 1)
            {
                _history.RemoveRange(_historyIndex + 1, _history.Count - (_historyIndex + 1));
            }
            _history.Add(path);
            _historyIndex = _history.Count - 1;
        }

        // Aktif sekmenin başlığını ve durumunu güncelle
        if (ExplorerTabs.SelectedItem is TabViewItem currentTab && currentTab.Tag is ExplorerTabState state)
        {
            state.CurrentPath = path;
            state.History = new List<string>(_history);
            state.HistoryIndex = _historyIndex;
            var folderName = string.IsNullOrEmpty(path) ? "Cloudreve" : Path.GetFileName(path.TrimEnd('/'));
            var isRoot = string.IsNullOrEmpty(path);
            currentTab.Header = folderName;
            currentTab.IconSource = new FontIconSource
            {
                Glyph = isRoot ? "\uE753" : "\uE8B7",
                Foreground = isRoot 
                    ? new SolidColorBrush(Windows.UI.Color.FromArgb(255, 0, 120, 212)) 
                    : new SolidColorBrush(Windows.UI.Color.FromArgb(255, 234, 163, 0))
            };
        }

        UpdateNavigationButtons();
        UpdateBreadcrumbs(path);
        await LoadDirectoryAsync(path);
    }

    private void UpdateNavigationButtons()
    {
        BackButton.IsEnabled = _historyIndex > 0;
        ForwardButton.IsEnabled = _historyIndex < _history.Count - 1;
        UpButton.IsEnabled = !string.IsNullOrEmpty(_currentPath);
    }

    private void UpdateBreadcrumbs(string path)
    {
        _breadcrumbs.Clear();
        _breadcrumbs.Add("Cloudreve");

        var parts = path.Split(new[] { '/' }, StringSplitOptions.RemoveEmptyEntries);
        foreach (var part in parts)
        {
            _breadcrumbs.Add(part);
        }
    }

    private async Task LoadDirectoryAsync(string path)
    {
        LoadingRing.IsActive = true;
        _items.Clear();
        _allItems.Clear();

        var config = CloudreveManager.Instance.ActiveServer;
        var client = new WebDAVClient(config);

        var list = await client.ListDirectoryAsync(path);
        _allItems.AddRange(list);

        ApplySearchFilter(SearchBox.Text);

        LoadingRing.IsActive = false;
        ItemCountText.Text = $"{_items.Count} öğe";
    }

    private void ApplySearchFilter(string query)
    {
        _items.Clear();
        var trimmed = query.Trim();

        var filtered = string.IsNullOrEmpty(trimmed)
            ? _allItems
            : _allItems.Where(i => i.Name.Contains(trimmed, StringComparison.CurrentCultureIgnoreCase));

        foreach (var item in filtered)
        {
            _items.Add(item);
        }

        ItemCountText.Text = $"{_items.Count} öğe";
    }

    private async void FileItem_Clicked(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is FileItem item)
        {
            _selectedItem = item;
            UpdatePreviewPane(item);
        }
    }

    private async void FileList_DoubleTapped(object sender, DoubleTappedRoutedEventArgs e)
    {
        e.Handled = true;
        var item = _selectedItem ?? (sender as ListViewBase)?.SelectedItem as FileItem;
        if (item != null)
        {
            await HandleOpenItemAsync(item);
        }
    }

    private async void Item_DoubleTapped(object sender, DoubleTappedRoutedEventArgs e)
    {
        e.Handled = true;
        if (sender is FrameworkElement fe && fe.DataContext is FileItem item)
        {
            _selectedItem = item;
            await HandleOpenItemAsync(item);
        }
    }

    private void Item_Tapped(object sender, TappedRoutedEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.DataContext is FileItem item)
        {
            _selectedItem = item;
            UpdatePreviewPane(item);
        }
    }

    private void FileList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        var selected = (sender as ListViewBase)?.SelectedItem as FileItem;
        if (selected != null)
        {
            _selectedItem = selected;
            UpdatePreviewPane(selected);
        }
    }

    private async void FileList_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key == Windows.System.VirtualKey.Enter && _selectedItem != null)
        {
            e.Handled = true;
            await HandleOpenItemAsync(_selectedItem);
        }
    }

    private async Task HandleOpenItemAsync(FileItem item)
    {
        if (item.IsDirectory)
        {
            NavigateToPath(item.Path);
        }
        else
        {
            await OpenFileAsync(item);
        }
    }

    private async Task OpenFileAsync(FileItem item)
    {
        LoadingRing.IsActive = true;
        var config = CloudreveManager.Instance.ActiveServer;
        var client = new WebDAVClient(config);

        var localPath = await client.DownloadFileToCacheAsync(item.Path);
        LoadingRing.IsActive = false;

        if (!string.IsNullOrEmpty(localPath) && File.Exists(localPath))
        {
            // Windows varsayılan uygulamasıyla aç (Örn: Word, Adobe Acrobat/Edge, VLC vb.)
            Process.Start(new ProcessStartInfo
            {
                FileName = localPath,
                UseShellExecute = true
            });
        }
    }

    private void BackButton_Click(object sender, RoutedEventArgs e)
    {
        if (_historyIndex > 0)
        {
            _historyIndex--;
            NavigateToPath(_history[_historyIndex], addToHistory: false);
        }
    }

    private void ForwardButton_Click(object sender, RoutedEventArgs e)
    {
        if (_historyIndex < _history.Count - 1)
        {
            _historyIndex++;
            NavigateToPath(_history[_historyIndex], addToHistory: false);
        }
    }

    private void UpButton_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(_currentPath)) return;
        var clean = _currentPath.TrimEnd('/');
        var lastSlash = clean.LastIndexOf('/');
        if (lastSlash >= 0)
        {
            NavigateToPath(clean.Substring(0, lastSlash));
        }
        else
        {
            NavigateToPath("");
        }
    }

    private void PathBreadcrumbBar_ItemClicked(BreadcrumbBar sender, BreadcrumbBarItemClickedEventArgs args)
    {
        if (args.Index == 0)
        {
            NavigateToPath("");
        }
        else
        {
            var parts = _breadcrumbs.Skip(1).Take(args.Index);
            var targetPath = string.Join("/", parts);
            NavigateToPath(targetPath);
        }
    }

    private void ViewLarge_Click(object sender, RoutedEventArgs e)
    {
        FileGridView.Visibility = Visibility.Visible;
        FileGridViewMedium.Visibility = Visibility.Collapsed;
        FileListView.Visibility = Visibility.Collapsed;
    }

    private void ViewMedium_Click(object sender, RoutedEventArgs e)
    {
        FileGridView.Visibility = Visibility.Collapsed;
        FileGridViewMedium.Visibility = Visibility.Visible;
        FileListView.Visibility = Visibility.Collapsed;
    }

    private void ViewDetails_Click(object sender, RoutedEventArgs e)
    {
        FileGridView.Visibility = Visibility.Collapsed;
        FileGridViewMedium.Visibility = Visibility.Collapsed;
        FileListView.Visibility = Visibility.Visible;
    }

    private void PreviewPaneToggle_Click(object sender, RoutedEventArgs e)
    {
        var isVisible = PreviewPane.Visibility == Visibility.Visible;
        PreviewPane.Visibility = isVisible ? Visibility.Collapsed : Visibility.Visible;
        PreviewPaneToggle.IsChecked = !isVisible;
        if (!isVisible && _selectedItem != null)
        {
            UpdatePreviewPane(_selectedItem);
        }
    }

    private void ClosePreviewPane_Click(object sender, RoutedEventArgs e)
    {
        PreviewPane.Visibility = Visibility.Collapsed;
        PreviewPaneToggle.IsChecked = false;
    }

    private void UpdatePreviewPane(FileItem? item)
    {
        if (item == null)
        {
            PreviewFileName.Text = "Dosya Seçilmedi";
            PreviewTypeBadge.Text = "Bilinmeyen";
            PreviewSizeText.Text = "--";
            PreviewDateText.Text = "--";
            PreviewExtensionText.Text = "--";
            PreviewPathText.Text = "--";
            PreviewImage.Visibility = Visibility.Collapsed;
            PreviewIcon.Visibility = Visibility.Visible;
            return;
        }

        PreviewFileName.Text = item.Name;
        PreviewTypeBadge.Text = item.TypeDescription;
        PreviewSizeText.Text = item.FormattedSize;
        PreviewDateText.Text = item.FormattedDate;
        PreviewExtensionText.Text = string.IsNullOrEmpty(item.Extension) ? (item.IsDirectory ? "Klasör" : "Bilinmeyen") : item.Extension;
        PreviewPathText.Text = item.Path;

        PreviewIcon.Glyph = item.GlyphIcon;
        PreviewIcon.Foreground = item.IconBrush;

        if (item.IsImage)
        {
            var cacheDir = Path.Combine(Path.GetTempPath(), "HDriveCache");
            var cachedFile = Path.Combine(cacheDir, Path.GetFileName(item.Path));
            if (File.Exists(cachedFile))
            {
                try
                {
                    PreviewImage.Source = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri(cachedFile));
                    PreviewImage.Visibility = Visibility.Visible;
                    PreviewIcon.Visibility = Visibility.Collapsed;
                }
                catch
                {
                    PreviewImage.Visibility = Visibility.Collapsed;
                    PreviewIcon.Visibility = Visibility.Visible;
                }
            }
            else
            {
                PreviewImage.Visibility = Visibility.Collapsed;
                PreviewIcon.Visibility = Visibility.Visible;

                _ = Task.Run(async () =>
                {
                    var client = new WebDAVClient(CloudreveManager.Instance.ActiveServer);
                    var downloaded = await client.DownloadFileToCacheAsync(item.Path);
                    if (!string.IsNullOrEmpty(downloaded) && File.Exists(downloaded))
                    {
                        DispatcherQueue.TryEnqueue(() =>
                        {
                            if (_selectedItem?.Path == item.Path)
                            {
                                try
                                {
                                    PreviewImage.Source = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri(downloaded));
                                    PreviewImage.Visibility = Visibility.Visible;
                                    PreviewIcon.Visibility = Visibility.Collapsed;
                                }
                                catch { }
                            }
                        });
                    }
                });
            }
        }
        else
        {
            PreviewImage.Visibility = Visibility.Collapsed;
            PreviewIcon.Visibility = Visibility.Visible;
        }

        if (item.IsDirectory)
        {
            PreviewOpenButton.Content = "Klasöre Git";
            PreviewDownloadButton.Visibility = Visibility.Collapsed;
        }
        else
        {
            PreviewOpenButton.Content = item.IsPdf ? "PDF'i Aç / Önizle" : "Varsayılan Uygulamayla Aç";
            PreviewDownloadButton.Visibility = Visibility.Visible;
        }
    }

    private async void PreviewOpenButton_Click(object sender, RoutedEventArgs e)
    {
        if (_selectedItem != null)
        {
            await HandleOpenItemAsync(_selectedItem);
        }
    }

    private async void PreviewDownloadButton_Click(object sender, RoutedEventArgs e)
    {
        if (_selectedItem != null && !_selectedItem.IsDirectory)
        {
            await OpenFileAsync(_selectedItem);
        }
    }

    private async void RefreshButton_Click(object sender, RoutedEventArgs e)
    {
        await LoadDirectoryAsync(_currentPath);
    }

    private async void NewFolderButton_Click(object sender, RoutedEventArgs e)
    {
        var inputTextBox = new TextBox { PlaceholderText = "Klasör Adı" };
        var dialog = new ContentDialog
        {
            Title = "Yeni Klasör Oluştur",
            Content = inputTextBox,
            PrimaryButtonText = "Oluştur",
            CloseButtonText = "İptal",
            DefaultButton = ContentDialogButton.Primary,
            XamlRoot = this.Content.XamlRoot
        };

        var result = await dialog.ShowAsync();
        if (result == ContentDialogResult.Primary && !string.IsNullOrWhiteSpace(inputTextBox.Text))
        {
            var folderName = inputTextBox.Text.Trim();
            var targetPath = _currentPath.TrimEnd('/') + "/" + folderName;

            var client = new WebDAVClient(CloudreveManager.Instance.ActiveServer);
            var success = await client.CreateFolderAsync(targetPath);
            if (success)
            {
                try
                {
                    FolderSyncEngine.Instance.SuppressWatcher(() =>
                    {
                        var rel = targetPath.TrimStart('/').Replace('/', Path.DirectorySeparatorChar);
                        var localTarget = Path.Combine(FolderSyncEngine.Instance.LocalFolderPath, rel);
                        Directory.CreateDirectory(localTarget);
                        FolderSyncEngine.Instance.RegisterRemoteFile(targetPath);
                    });
                }
                catch { }

                await LoadDirectoryAsync(_currentPath);
            }
        }
    }

    private async void UploadButton_Click(object sender, RoutedEventArgs e)
    {
        var picker = new FileOpenPicker();
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        WinRT.Interop.InitializeWithWindow.Initialize(picker, hwnd);

        picker.ViewMode = PickerViewMode.List;
        picker.SuggestedStartLocation = PickerLocationId.Desktop;
        picker.FileTypeFilter.Add("*");

        var file = await picker.PickSingleFileAsync();
        if (file != null)
        {
            LoadingRing.IsActive = true;
            var client = new WebDAVClient(CloudreveManager.Instance.ActiveServer);
            var success = await client.UploadFileAsync(file.Path, _currentPath);
            LoadingRing.IsActive = false;

            if (success)
            {
                try
                {
                    FolderSyncEngine.Instance.SuppressWatcher(() =>
                    {
                        var relDir = _currentPath.Trim('/').Replace('/', Path.DirectorySeparatorChar);
                        var localDir = string.IsNullOrEmpty(relDir)
                            ? FolderSyncEngine.Instance.LocalFolderPath
                            : Path.Combine(FolderSyncEngine.Instance.LocalFolderPath, relDir);
                        Directory.CreateDirectory(localDir);
                        var localDest = Path.Combine(localDir, Path.GetFileName(file.Path));
                        File.Copy(file.Path, localDest, overwrite: true);

                        var relPath = Path.GetRelativePath(FolderSyncEngine.Instance.LocalFolderPath, localDest).Replace('\\', '/');
                        FolderSyncEngine.Instance.RegisterRemoteFile(relPath);
                    });
                }
                catch { }

                await LoadDirectoryAsync(_currentPath);
            }
        }
    }

    private void SearchBox_TextChanged(AutoSuggestBox sender, AutoSuggestBoxTextChangedEventArgs args)
    {
        ApplySearchFilter(sender.Text);
    }

    private async void NavView_ItemInvoked(NavigationView sender, NavigationViewItemInvokedEventArgs args)
    {
        if (args.IsSettingsInvoked)
        {
            await OpenSettingsDialogAsync();
        }
        else if (args.InvokedItemContainer is NavigationViewItem item)
        {
            if ((string)item.Tag == "cloud")
            {
                NavigateToPath("");
            }
            else if ((string)item.Tag == "local")
            {
                FolderSyncEngine.Instance.OpenLocalFolderInExplorer();
            }
        }
    }

    private async Task OpenSettingsDialogAsync()
    {
        var dialog = new SettingsDialog
        {
            XamlRoot = this.Content.XamlRoot
        };
        await dialog.ShowAsync();
        await LoadDirectoryAsync(_currentPath);
    }

    private void FileItem_RightTapped(object sender, RightTappedRoutedEventArgs e)
    {
        if (e.OriginalSource is FrameworkElement element && element.DataContext is FileItem item)
        {
            _selectedItem = item;
        }
    }

    private async void ContextOpen_Click(object sender, RoutedEventArgs e)
    {
        if (_selectedItem != null)
        {
            if (_selectedItem.IsDirectory)
                NavigateToPath(_selectedItem.Path);
            else
                await OpenFileAsync(_selectedItem);
        }
    }

    private async void ContextDownload_Click(object sender, RoutedEventArgs e)
    {
        if (_selectedItem != null && !_selectedItem.IsDirectory)
        {
            await OpenFileAsync(_selectedItem);
        }
    }

    private async void ContextDelete_Click(object sender, RoutedEventArgs e)
    {
        if (_selectedItem == null) return;

        var confirmDialog = new ContentDialog
        {
            Title = "Silinsin mi?",
            Content = $"'{_selectedItem.Name}' öğesini silmek istediğinizden emin misiniz?",
            PrimaryButtonText = "Sil",
            CloseButtonText = "İptal",
            DefaultButton = ContentDialogButton.Close,
            XamlRoot = this.Content.XamlRoot
        };

        var result = await confirmDialog.ShowAsync();
        if (result == ContentDialogResult.Primary)
        {
            var client = new WebDAVClient(CloudreveManager.Instance.ActiveServer);
            var success = await client.DeleteAsync(_selectedItem.Path);
            if (success)
            {
                try
                {
                    FolderSyncEngine.Instance.SuppressWatcher(() =>
                    {
                        var rel = _selectedItem.Path.TrimStart('/').Replace('/', Path.DirectorySeparatorChar);
                        var localTarget = Path.Combine(FolderSyncEngine.Instance.LocalFolderPath, rel);
                        if (File.Exists(localTarget))
                        {
                            File.Delete(localTarget);
                        }
                        else if (Directory.Exists(localTarget))
                        {
                            Directory.Delete(localTarget, true);
                        }
                        FolderSyncEngine.Instance.UnregisterRemoteFile(_selectedItem.Path);
                    });
                }
                catch { }

                await LoadDirectoryAsync(_currentPath);
            }
        }
    }

    #region Sürükle ve Bırak (Drag & Drop) Desteği

    /// <summary>
    /// HDrive içinden Windows Masaüstüne, Explorer'a veya başka programlara dosya sürükleyip kopyalama
    /// </summary>
    private async void FileItem_DragStarting(UIElement sender, DragStartingEventArgs e)
    {
        var deferral = e.GetDeferral();
        try
        {
            if (sender is not FrameworkElement fe || fe.DataContext is not FileItem item)
            {
                deferral.Complete();
                return;
            }

            var storageItems = new List<IStorageItem>();
            var syncFolder = FolderSyncEngine.Instance.LocalFolderPath;
            var cacheDir = Path.Combine(Path.GetTempPath(), "HDriveCache");
            Directory.CreateDirectory(cacheDir);

            var config = CloudreveManager.Instance.ActiveServer;
            var client = new WebDAVClient(config);

            string? localPath = null;

            // 1. Yerel eşitleme klasöründe (HDrive - Cloudreve) mevcut mu?
            var relPath = item.Path.TrimStart('/').Replace('/', Path.DirectorySeparatorChar);
            var syncPath = Path.Combine(syncFolder, relPath);
            if (File.Exists(syncPath) || Directory.Exists(syncPath))
            {
                localPath = syncPath;
            }
            else
            {
                // 2. Geçici önbellekte (Cache) var mı?
                var cachedPath = Path.Combine(cacheDir, Path.GetFileName(item.Path));
                if (File.Exists(cachedPath))
                {
                    localPath = cachedPath;
                }
                else if (!item.IsDirectory)
                {
                    // 3. Henüz indirilmemişse, dışarı sürükleme için hızla önbelleğe indir
                    localPath = await client.DownloadFileToCacheAsync(item.Path);
                }
                else
                {
                    // Klasör ise yerel geçici klasör aç
                    var cachedFolderPath = Path.Combine(cacheDir, Path.GetFileName(item.Path.TrimEnd('/')));
                    Directory.CreateDirectory(cachedFolderPath);
                    localPath = cachedFolderPath;
                }
            }

            if (!string.IsNullOrEmpty(localPath))
            {
                if (File.Exists(localPath))
                {
                    var sf = await StorageFile.GetFileFromPathAsync(localPath);
                    storageItems.Add(sf);
                }
                else if (Directory.Exists(localPath))
                {
                    var df = await StorageFolder.GetFolderFromPathAsync(localPath);
                    storageItems.Add(df);
                }
            }

            if (storageItems.Count > 0)
            {
                e.Data.SetStorageItems(storageItems);
                e.Data.RequestedOperation = DataPackageOperation.Copy | DataPackageOperation.Move;
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"DragStarting error: {ex.Message}");
        }
        finally
        {
            deferral.Complete();
        }
    }

    /// <summary>
    /// Dışarıdan HDrive içine dosya sürüklendiğinde görsel geribildirim sağlama
    /// </summary>
    private void FileArea_DragOver(object sender, DragEventArgs e)
    {
        if (e.DataView.Contains(StandardDataFormats.StorageItems))
        {
            e.AcceptedOperation = DataPackageOperation.Copy;
            e.DragUIOverride.Caption = "HDrive'a Kopyala / Yükle";
            e.DragUIOverride.IsCaptionVisible = true;
            e.DragUIOverride.IsContentVisible = true;
        }
    }

    /// <summary>
    /// Windows Explorer veya Masaüstünden HDrive içine bırakılan dosyaları otomatik Cloudreve'e yükleme
    /// </summary>
    private async void FileArea_Drop(object sender, DragEventArgs e)
    {
        if (e.DataView.Contains(StandardDataFormats.StorageItems))
        {
            var deferral = e.GetDeferral();
            try
            {
                var items = await e.DataView.GetStorageItemsAsync();
                if (items.Count > 0)
                {
                    LoadingRing.IsActive = true;
                    var client = new WebDAVClient(CloudreveManager.Instance.ActiveServer);
                    int uploadedCount = 0;

                    foreach (var item in items)
                    {
                        uploadedCount += await UploadStorageItemRecursivelyAsync(item, _currentPath, client);
                    }

                    LoadingRing.IsActive = false;
                    if (uploadedCount > 0)
                    {
                        await LoadDirectoryAsync(_currentPath);
                    }
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Drop error: {ex.Message}");
            }
            finally
            {
                deferral.Complete();
            }
        }
    }

    private async Task<int> UploadStorageItemRecursivelyAsync(IStorageItem item, string remoteDir, WebDAVClient client)
    {
        int count = 0;
        if (item is StorageFile file)
        {
            var ok = await client.UploadFileAsync(file.Path, remoteDir);
            if (ok)
            {
                count++;
                try
                {
                    FolderSyncEngine.Instance.SuppressWatcher(() =>
                    {
                        var relDir = remoteDir.Trim('/').Replace('/', Path.DirectorySeparatorChar);
                        var localDir = string.IsNullOrEmpty(relDir)
                            ? FolderSyncEngine.Instance.LocalFolderPath
                            : Path.Combine(FolderSyncEngine.Instance.LocalFolderPath, relDir);
                        Directory.CreateDirectory(localDir);
                        var localDest = Path.Combine(localDir, Path.GetFileName(file.Path));
                        File.Copy(file.Path, localDest, overwrite: true);

                        var relPath = Path.GetRelativePath(FolderSyncEngine.Instance.LocalFolderPath, localDest).Replace('\\', '/');
                        FolderSyncEngine.Instance.RegisterRemoteFile(relPath);
                    });
                }
                catch { }
            }
        }
        else if (item is StorageFolder folder)
        {
            var targetSubDir = remoteDir.TrimEnd('/') + "/" + folder.Name;
            await client.CreateFolderAsync(targetSubDir);
            try
            {
                FolderSyncEngine.Instance.SuppressWatcher(() =>
                {
                    var relDir = targetSubDir.Trim('/').Replace('/', Path.DirectorySeparatorChar);
                    var localDir = Path.Combine(FolderSyncEngine.Instance.LocalFolderPath, relDir);
                    Directory.CreateDirectory(localDir);
                    FolderSyncEngine.Instance.RegisterRemoteFile(targetSubDir);
                });
            }
            catch { }

            var subItems = await folder.GetItemsAsync();
            foreach (var sub in subItems)
            {
                count += await UploadStorageItemRecursivelyAsync(sub, targetSubDir, client);
            }
        }
        return count;
    }

    #endregion

    #region Üç Nokta (...) Menüsü ve Hızlı Eylemler

    private void SyncNow_Click(object sender, RoutedEventArgs e)
    {
        _ = FolderSyncEngine.Instance.SyncNowAsync();
    }

    private void OpenLocalFolder_Click(object sender, RoutedEventArgs e)
    {
        FolderSyncEngine.Instance.OpenLocalFolderInExplorer();
    }

    private void SelectAll_Click(object sender, RoutedEventArgs e)
    {
        FileGridView.SelectAll();
        FileGridViewMedium.SelectAll();
        FileListView.SelectAll();
    }

    private async void OpenSettings_Click(object sender, RoutedEventArgs e)
    {
        await OpenSettingsDialogAsync();
    }

    #endregion
}

public class ExplorerTabState
{
    public string CurrentPath { get; set; } = "";
    public List<string> History { get; set; } = new() { "" };
    public int HistoryIndex { get; set; } = 0;
}
