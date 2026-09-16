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

    public enum SortField
    {
        Name,
        Date,
        Size,
        Type
    }

    private SortField _sortField = SortField.Name;
    private bool _sortAscending = true;
    private bool _foldersFirst = true;

    public MainWindow()
    {
        try
        {
            this.InitializeComponent();
        }
        catch (Exception ex)
        {
            App.LogCrash("MainWindow.InitializeComponent", ex);
            throw;
        }

        try
        {
            SetupTitleBar();
        }
        catch (Exception ex)
        {
            App.LogCrash("MainWindow.SetupTitleBar", ex);
        }

        try
        {
            FileGridView.ItemsSource = _items;
            FileGridViewMedium.ItemsSource = _items;
            FileListView.ItemsSource = _items;
            PathBreadcrumbBar.ItemsSource = _breadcrumbs;

            // Görünüm ve sıralama ayarlarını ilk sekme açılmadan önce yükle
            LoadViewSettings();

            // Başlangıç sekmesi oluştur
            CreateInitialTab();
        }
        catch (Exception ex)
        {
            App.LogCrash("MainWindow.TabAndItemsSetup", ex);
        }

        try
        {
            if (this.Content is FrameworkElement rootElement)
            {
                // Klavyeden Explorer Kısayolları (Ctrl+C, Ctrl+X, Ctrl+V, F2, Alt+Enter, Ctrl+A, Ctrl+T, Ctrl+W, Delete, Esc)
                rootElement.KeyDown += (s, e) =>
                {
                    var isCtrl = Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(Windows.System.VirtualKey.Control)
                        .HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);
                    var isAlt = Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(Windows.System.VirtualKey.Menu)
                        .HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);

                    var focused = Microsoft.UI.Xaml.Input.FocusManager.GetFocusedElement(this.Content.XamlRoot);
                    var isTypingInBox = focused is TextBox || focused is AutoSuggestBox || focused is PasswordBox;

                    if (isCtrl)
                    {
                        if (e.Key == Windows.System.VirtualKey.A && !isTypingInBox)
                        {
                            e.Handled = true;
                            SelectAll_Click(s, new RoutedEventArgs());
                        }
                        else if (e.Key == Windows.System.VirtualKey.C && !isTypingInBox)
                        {
                            e.Handled = true;
                            CopySelectedItemsToClipboard();
                        }
                        else if (e.Key == Windows.System.VirtualKey.X && !isTypingInBox)
                        {
                            e.Handled = true;
                            CutSelectedItemsToClipboard();
                        }
                        else if (e.Key == Windows.System.VirtualKey.V && !isTypingInBox)
                        {
                            e.Handled = true;
                            _ = PasteFromClipboardAsync();
                        }
                        else if (e.Key == Windows.System.VirtualKey.T)
                        {
                            OpenNewTab("");
                            e.Handled = true;
                        }
                        else if (e.Key == Windows.System.VirtualKey.W)
                        {
                            CloseCurrentTab();
                            e.Handled = true;
                        }
                    }
                    else if (isAlt && e.Key == Windows.System.VirtualKey.Enter && !isTypingInBox)
                    {
                        e.Handled = true;
                        _ = ShowPropertiesAsync(GetSelectedItems().FirstOrDefault() ?? _selectedItem);
                    }
                    else if (isAlt && e.Key == Windows.System.VirtualKey.P)
                    {
                        e.Handled = true;
                        TogglePreviewPane();
                    }
                    else if (e.Key == Windows.System.VirtualKey.Space && !isTypingInBox)
                    {
                        e.Handled = true;
                        TogglePreviewPane();
                    }
                    else if (e.Key == Windows.System.VirtualKey.F2 && !isTypingInBox)
                    {
                        e.Handled = true;
                        BeginInlineRename(GetSelectedItems().FirstOrDefault() ?? _selectedItem);
                    }
                    else if (e.Key == Windows.System.VirtualKey.Delete && !isTypingInBox)
                    {
                        var items = GetSelectedItems();
                        if (items.Count > 0)
                        {
                            e.Handled = true;
                            ContextDelete_Click(s, new RoutedEventArgs());
                        }
                    }
                    else if (e.Key == Windows.System.VirtualKey.Escape)
                    {
                        ClearSelection();
                    }
                };
            }
        }
        catch (Exception ex)
        {
            App.LogCrash("MainWindow.KeyDownSetup", ex);
        }

        try
        {
            // Senkronizasyon durumunu dinle
            FolderSyncEngine.Instance.PropertyChanged += (s, e) =>
            {
                if (e.PropertyName == nameof(FolderSyncEngine.SyncStatus))
                {
                    DispatcherQueue?.TryEnqueue(() =>
                    {
                        if (SyncStatusText != null)
                        {
                            SyncStatusText.Text = $"Eşitleme: {FolderSyncEngine.Instance.SyncStatus}";
                        }
                    });
                }
            };

            // Canlı Harici Uygulama Düzenleme (In-Place Edit Auto-Sync) Dinleyicisi
            LiveEditWatcherService.Instance.FileAutoSynced += (s, e) =>
            {
                DispatcherQueue?.TryEnqueue(async () =>
                {
                    if (e.Success)
                    {
                        if (SyncStatusText != null)
                        {
                            SyncStatusText.Text = $"Otomatik Eşitlendi: {e.FileName}";
                        }
                        if (e.RemoteDirectory == _currentPath)
                        {
                            await LoadDirectoryAsync(_currentPath);
                        }
                    }
                    else
                    {
                        if (SyncStatusText != null)
                        {
                            SyncStatusText.Text = $"Otomatik eşitleme başarısız: {e.FileName}";
                        }
                    }
                });
            };
        }
        catch (Exception ex)
        {
            App.LogCrash("MainWindow.FolderSyncEngineSetup", ex);
        }

        try
        {
            LoadPinnedFolders();
        }
        catch (Exception ex)
        {
            App.LogCrash("MainWindow.LoadPinnedFolders", ex);
        }

        try
        {
            _ = RefreshStorageQuotaAsync();
        }
        catch (Exception ex)
        {
            App.LogCrash("MainWindow.RefreshStorageQuotaAsync", ex);
        }

        try
        {
            NavView.SelectedItem = AllFilesNavItem;
        }
        catch (Exception ex)
        {
            App.LogCrash("MainWindow.NavViewSelection", ex);
        }
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
        // Not: ExplorerTabs.SelectedItem = newTab tetiklendiğinde ExplorerTabs_SelectionChanged otomatik olarak LoadDirectoryAsync çağırır
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
        try
        {
            ExtendsContentIntoTitleBar = true;
            if (CustomDragRegion != null)
            {
                SetTitleBar(CustomDragRegion);
            }
        }
        catch (Exception ex)
        {
            App.LogCrash("SetupTitleBar.SetTitleBar", ex);
        }

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
        catch (Exception ex)
        {
            App.LogCrash("SetupTitleBar.SetIcon", ex);
        }
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

    private int _loadSessionId = 0;

    private async Task LoadDirectoryAsync(string path)
    {
        var sessionId = ++_loadSessionId;
        LoadingRing.IsActive = true;

        var config = CloudreveManager.Instance.ActiveServer;
        if (config == null)
        {
            LoadingRing.IsActive = false;
            return;
        }

        var client = new WebDAVClient(config);
        var list = await client.ListDirectoryAsync(path);

        // Eğer başka bir gezinme başladıysa bu eski isteğin sonucunu yoksay
        if (sessionId != _loadSessionId) return;

        _allItems.Clear();
        var uniqueList = list.GroupBy(x => x.Path, StringComparer.OrdinalIgnoreCase)
                             .Select(g => g.First())
                             .ToList();
        _allItems.AddRange(uniqueList);

        ApplySearchFilter(SearchBox.Text);

        LoadingRing.IsActive = false;
        ItemCountText.Text = $"{_items.Count} öğe";

        _ = RefreshStorageQuotaAsync();
    }

    private void ApplySearchFilter(string query)
    {
        _items.Clear();
        var trimmed = query.Trim();

        var filtered = string.IsNullOrEmpty(trimmed)
            ? (IEnumerable<FileItem>)_allItems
            : _allItems.Where(i => i.Name.Contains(trimmed, StringComparison.CurrentCultureIgnoreCase));

        var sorted = filtered.OrderBy(item => _foldersFirst && !item.IsDirectory ? 1 : 0);

        IOrderedEnumerable<FileItem> ordered = _sortField switch
        {
            SortField.Date => _sortAscending
                ? sorted.ThenBy(i => i.ModifiedDate ?? DateTime.MinValue)
                : sorted.ThenByDescending(i => i.ModifiedDate ?? DateTime.MinValue),
            SortField.Size => _sortAscending
                ? sorted.ThenBy(i => i.Size)
                : sorted.ThenByDescending(i => i.Size),
            SortField.Type => _sortAscending
                ? sorted.ThenBy(i => i.TypeDescription, StringComparer.CurrentCultureIgnoreCase)
                : sorted.ThenByDescending(i => i.TypeDescription, StringComparer.CurrentCultureIgnoreCase),
            _ => _sortAscending
                ? sorted.ThenBy(i => i.Name, StringComparer.CurrentCultureIgnoreCase)
                : sorted.ThenByDescending(i => i.Name, StringComparer.CurrentCultureIgnoreCase)
        };

        foreach (var item in ordered)
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
        FileItem? item = null;
        if (e.OriginalSource is FrameworkElement fe && fe.DataContext is FileItem fi)
        {
            item = fi;
        }
        else
        {
            item = _selectedItem ?? (sender as ListViewBase)?.SelectedItem as FileItem;
        }

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
        var selectedList = GetSelectedItems();
        if (selectedList.Count == 1)
        {
            _selectedItem = selectedList[0];
            UpdatePreviewPane(_selectedItem);
        }
        else if (selectedList.Count > 1)
        {
            _selectedItem = selectedList.Last();
            UpdatePreviewPaneForMultipleItems(selectedList);
        }
        else
        {
            _selectedItem = null;
            UpdatePreviewPane(null);
        }
        UpdateItemCountStatus(selectedList);
    }

    private void FileArea_Tapped(object sender, TappedRoutedEventArgs e)
    {
        if (e.OriginalSource == sender || 
            (e.OriginalSource is FrameworkElement fe && fe.DataContext is not FileItem && fe is not Button && fe is not AppBarButton))
        {
            ClearSelection();
        }
    }

    private void ClearSelection()
    {
        var container = GetActiveItemContainer();
        if (container != null)
        {
            container.SelectedItems.Clear();
            container.SelectedItem = null;
        }
        _selectedItem = null;
        UpdatePreviewPane(null);
        UpdateItemCountStatus();
    }

    private void UpdateItemCountStatus(List<FileItem>? selectedItems = null)
    {
        var total = _items.Count;
        selectedItems ??= GetSelectedItems();
        if (selectedItems.Count > 1)
        {
            long totalSize = selectedItems.Where(i => !i.IsDirectory).Sum(i => i.Size);
            string formattedSize = FormatByteSize(totalSize);
            ItemCountText.Text = $"{total} öğe  |  {selectedItems.Count} öğe seçildi ({formattedSize})";
        }
        else if (selectedItems.Count == 1)
        {
            var item = selectedItems[0];
            ItemCountText.Text = $"{total} öğe  |  1 öğe seçildi ({(item.IsDirectory ? "Klasör" : item.FormattedSize)})";
        }
        else
        {
            ItemCountText.Text = $"{total} öğe";
        }
    }

    private static string FormatByteSize(long bytes)
    {
        if (bytes < 1024) return $"{bytes} B";
        if (bytes < 1024 * 1024) return $"{(bytes / 1024.0):F1} KB";
        if (bytes < 1024 * 1024 * 1024) return $"{(bytes / (1024.0 * 1024.0)):F1} MB";
        return $"{(bytes / (1024.0 * 1024.0 * 1024.0)):F2} GB";
    }

    private void UpdatePreviewPaneForMultipleItems(List<FileItem> selectedItems)
    {
        if (PreviewPane == null || PreviewPane.Visibility != Visibility.Visible) return;

        if (PreviewEmptyState != null) PreviewEmptyState.Visibility = Visibility.Collapsed;
        if (PreviewContentState != null) PreviewContentState.Visibility = Visibility.Visible;

        PreviewFileName.Text = $"{selectedItems.Count} Öğe Seçildi";
        PreviewTypeBadge.Text = "Çoklu Seçim";
        long totalSize = selectedItems.Where(i => !i.IsDirectory).Sum(i => i.Size);
        PreviewSizeText.Text = FormatByteSize(totalSize);
        PreviewDateText.Text = "--";
        PreviewExtensionText.Text = "Karma";
        PreviewPathText.Text = $"{selectedItems.Count} dosya/klasör seçili";

        if (PreviewTextScroll != null) PreviewTextScroll.Visibility = Visibility.Collapsed;
        if (PreviewImage != null) PreviewImage.Visibility = Visibility.Collapsed;
        if (PreviewIconContainer != null) PreviewIconContainer.Visibility = Visibility.Visible;
        if (PreviewIconImage != null) PreviewIconImage.Visibility = Visibility.Collapsed;
        if (PreviewIcon != null)
        {
            PreviewIcon.Visibility = Visibility.Visible;
            PreviewIcon.Glyph = "\uE8B3";
        }

        PreviewOpenButton.Content = $"{selectedItems.Count} Öğeyi Aç";
        PreviewDownloadButton.Content = $"{selectedItems.Count} Öğeyi İndir...";
        PreviewDownloadButton.Visibility = Visibility.Visible;
    }

    private async void FileList_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        var isCtrl = Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(Windows.System.VirtualKey.Control)
            .HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);

        if (isCtrl && e.Key == Windows.System.VirtualKey.A)
        {
            e.Handled = true;
            SelectAll_Click(sender, new RoutedEventArgs());
        }
        else if (e.Key == Windows.System.VirtualKey.Escape)
        {
            e.Handled = true;
            ClearSelection();
        }
        else if (e.Key == Windows.System.VirtualKey.Enter && _selectedItem != null)
        {
            e.Handled = true;
            await HandleOpenItemAsync(_selectedItem);
        }
        else if (e.Key == Windows.System.VirtualKey.Space && _selectedItem != null)
        {
            e.Handled = true;
            PreviewPaneToggle_Click(sender, new RoutedEventArgs());
        }
        else if (e.Key == Windows.System.VirtualKey.F2 && _selectedItem != null)
        {
            e.Handled = true;
            BeginInlineRename(_selectedItem);
        }
        else if (e.Key == Windows.System.VirtualKey.Delete)
        {
            var items = GetSelectedItems();
            if (items.Count > 0)
            {
                e.Handled = true;
                ContextDelete_Click(sender, new RoutedEventArgs());
            }
        }
        else if (!isCtrl && (e.Key >= Windows.System.VirtualKey.A && e.Key <= Windows.System.VirtualKey.Z ||
                             e.Key >= Windows.System.VirtualKey.Number0 && e.Key <= Windows.System.VirtualKey.Number9))
        {
            char c = (char)e.Key;
            if (e.Key >= Windows.System.VirtualKey.A && e.Key <= Windows.System.VirtualKey.Z)
            {
                c = (char)('a' + (e.Key - Windows.System.VirtualKey.A));
            }
            else if (e.Key >= Windows.System.VirtualKey.Number0 && e.Key <= Windows.System.VirtualKey.Number9)
            {
                c = (char)('0' + (e.Key - Windows.System.VirtualKey.Number0));
            }
            HandleTypeToSelect(c);
            e.Handled = true;
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
        try
        {
            LoadingRing.IsActive = true;
            var config = CloudreveManager.Instance.ActiveServer;
            if (config == null) return;
            var client = new WebDAVClient(config);

            var localPath = await client.DownloadFileToCacheAsync(item.Path);
            LoadingRing.IsActive = false;

            if (!string.IsNullOrEmpty(localPath) && File.Exists(localPath))
            {
                // Windows varsayılan uygulamasıyla aç (Örn: Word, Adobe Acrobat/Edge, VLC vb.)
                try
                {
                    Process.Start(new ProcessStartInfo
                    {
                        FileName = localPath,
                        UseShellExecute = true
                    });

                    // Canlı Harici Düzenleme Takibi: Harici programda Ctrl+S yapıldığında Cloudreve'e otomatik geri yükle
                    LiveEditWatcherService.Instance.WatchFile(localPath, item.Path, _currentPath);
                }
                catch (Exception ex)
                {
                    Debug.WriteLine($"Failed to open with default app: {ex.Message}");
                    Process.Start(new ProcessStartInfo
                    {
                        FileName = "explorer.exe",
                        Arguments = $"/select,\"{localPath}\"",
                        UseShellExecute = true
                    });

                    LiveEditWatcherService.Instance.WatchFile(localPath, item.Path, _currentPath);
                }
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"OpenFileAsync error: {ex.Message}");
        }
        finally
        {
            LoadingRing.IsActive = false;
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

    public enum ExplorerViewMode
    {
        Large,
        Medium,
        Details
    }

    public class ViewSettingsModel
    {
        public ExplorerViewMode ViewMode { get; set; } = ExplorerViewMode.Large;
        public bool ShowPreviewPane { get; set; } = false;
        public SortField SortBy { get; set; } = SortField.Name;
        public bool SortAscending { get; set; } = true;
        public bool FoldersFirst { get; set; } = true;
        public double ColDateWidth { get; set; } = 180;
        public double ColTypeWidth { get; set; } = 140;
        public double ColSizeWidth { get; set; } = 100;
        public bool ShowColDate { get; set; } = true;
        public bool ShowColType { get; set; } = true;
        public bool ShowColSize { get; set; } = true;
    }

    private ExplorerViewMode _currentViewMode = ExplorerViewMode.Large;

    private double _colDateWidth = 180;
    private double _colTypeWidth = 140;
    private double _colSizeWidth = 100;
    private bool _showColDate = true;
    private bool _showColType = true;
    private bool _showColSize = true;

    private bool _isResizingColumn = false;
    private string _resizingColumnName = "";
    private double _resizeStartX = 0;
    private double _resizeStartWidth = 0;

    private string _typeToSelectQuery = "";
    private DispatcherTimer? _typeToSelectTimer;

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
                var settings = System.Text.Json.JsonSerializer.Deserialize<ViewSettingsModel>(json);
                if (settings != null)
                {
                    _sortField = settings.SortBy;
                    _sortAscending = settings.SortAscending;
                    _foldersFirst = settings.FoldersFirst;
                    _colDateWidth = settings.ColDateWidth > 0 ? settings.ColDateWidth : 180;
                    _colTypeWidth = settings.ColTypeWidth > 0 ? settings.ColTypeWidth : 140;
                    _colSizeWidth = settings.ColSizeWidth > 0 ? settings.ColSizeWidth : 100;
                    _showColDate = settings.ShowColDate;
                    _showColType = settings.ShowColType;
                    _showColSize = settings.ShowColSize;
                    ApplyColumnWidths();
                    ApplyViewMode(settings.ViewMode, save: false);
                    SetPreviewPaneVisibility(settings.ShowPreviewPane, save: false);
                    UpdateSortMenuChecks();
                    return;
                }
            }
        }
        catch (Exception ex)
        {
            App.LogCrash("MainWindow.LoadViewSettings", ex);
        }
        ApplyColumnWidths();
        ApplyViewMode(ExplorerViewMode.Large, save: false);
        SetPreviewPaneVisibility(false, save: false);
        UpdateSortMenuChecks();
    }

    private void SaveCurrentSettings()
    {
        try
        {
            var settings = new ViewSettingsModel
            {
                ViewMode = _currentViewMode,
                ShowPreviewPane = (PreviewPane?.Visibility == Visibility.Visible),
                SortBy = _sortField,
                SortAscending = _sortAscending,
                FoldersFirst = _foldersFirst,
                ColDateWidth = _colDateWidth,
                ColTypeWidth = _colTypeWidth,
                ColSizeWidth = _colSizeWidth,
                ShowColDate = _showColDate,
                ShowColType = _showColType,
                ShowColSize = _showColSize
            };
            var filePath = GetViewSettingsFilePath();
            var json = System.Text.Json.JsonSerializer.Serialize(settings, new System.Text.Json.JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(filePath, json);
        }
        catch (Exception ex)
        {
            App.LogCrash("MainWindow.SaveCurrentSettings", ex);
        }
    }

    private void TogglePreviewPane()
    {
        var isVisible = PreviewPane.Visibility == Visibility.Visible;
        SetPreviewPaneVisibility(!isVisible, save: true);
    }

    private void SetPreviewPaneVisibility(bool visible, bool save = true)
    {
        if (PreviewPane == null) return;
        PreviewPane.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
        if (PreviewPaneToggle != null) PreviewPaneToggle.IsChecked = visible;
        if (visible)
        {
            UpdatePreviewPane(_selectedItem);
        }
        if (save)
        {
            SaveCurrentSettings();
        }
    }

    private void ApplyViewMode(ExplorerViewMode mode, bool save = true)
    {
        _currentViewMode = mode;
        if (FileGridView != null) FileGridView.Visibility = (mode == ExplorerViewMode.Large) ? Visibility.Visible : Visibility.Collapsed;
        if (FileGridViewMedium != null) FileGridViewMedium.Visibility = (mode == ExplorerViewMode.Medium) ? Visibility.Visible : Visibility.Collapsed;
        if (FileListView != null) FileListView.Visibility = (mode == ExplorerViewMode.Details) ? Visibility.Visible : Visibility.Collapsed;

        if (ViewLargeItem != null) ViewLargeItem.IsChecked = (mode == ExplorerViewMode.Large);
        if (ViewMediumItem != null) ViewMediumItem.IsChecked = (mode == ExplorerViewMode.Medium);
        if (ViewDetailsItem != null) ViewDetailsItem.IsChecked = (mode == ExplorerViewMode.Details);

        if (save)
        {
            SaveCurrentSettings();
        }
    }

    private void ViewLarge_Click(object sender, RoutedEventArgs e)
    {
        ApplyViewMode(ExplorerViewMode.Large);
    }

    private void ViewMedium_Click(object sender, RoutedEventArgs e)
    {
        ApplyViewMode(ExplorerViewMode.Medium);
    }

    private void ViewDetails_Click(object sender, RoutedEventArgs e)
    {
        ApplyViewMode(ExplorerViewMode.Details);
    }

    private void SortByName_Click(object sender, RoutedEventArgs e)
    {
        _sortField = SortField.Name;
        UpdateSortMenuChecks();
        ApplySearchFilter(SearchBox.Text);
        SaveCurrentSettings();
    }

    private void SortByDate_Click(object sender, RoutedEventArgs e)
    {
        _sortField = SortField.Date;
        UpdateSortMenuChecks();
        ApplySearchFilter(SearchBox.Text);
        SaveCurrentSettings();
    }

    private void SortBySize_Click(object sender, RoutedEventArgs e)
    {
        _sortField = SortField.Size;
        UpdateSortMenuChecks();
        ApplySearchFilter(SearchBox.Text);
        SaveCurrentSettings();
    }

    private void SortByType_Click(object sender, RoutedEventArgs e)
    {
        _sortField = SortField.Type;
        UpdateSortMenuChecks();
        ApplySearchFilter(SearchBox.Text);
        SaveCurrentSettings();
    }

    private void SortAscending_Click(object sender, RoutedEventArgs e)
    {
        _sortAscending = true;
        UpdateSortMenuChecks();
        ApplySearchFilter(SearchBox.Text);
        SaveCurrentSettings();
    }

    private void SortDescending_Click(object sender, RoutedEventArgs e)
    {
        _sortAscending = false;
        UpdateSortMenuChecks();
        ApplySearchFilter(SearchBox.Text);
        SaveCurrentSettings();
    }

    private void HeaderSortByName_Click(object sender, RoutedEventArgs e)
    {
        if (_sortField == SortField.Name) _sortAscending = !_sortAscending;
        else { _sortField = SortField.Name; _sortAscending = true; }
        UpdateSortMenuChecks();
        ApplySearchFilter(SearchBox.Text);
        SaveCurrentSettings();
    }

    private void HeaderSortByDate_Click(object sender, RoutedEventArgs e)
    {
        if (_sortField == SortField.Date) _sortAscending = !_sortAscending;
        else { _sortField = SortField.Date; _sortAscending = true; }
        UpdateSortMenuChecks();
        ApplySearchFilter(SearchBox.Text);
        SaveCurrentSettings();
    }

    private void HeaderSortByType_Click(object sender, RoutedEventArgs e)
    {
        if (_sortField == SortField.Type) _sortAscending = !_sortAscending;
        else { _sortField = SortField.Type; _sortAscending = true; }
        UpdateSortMenuChecks();
        ApplySearchFilter(SearchBox.Text);
        SaveCurrentSettings();
    }

    private void HeaderSortBySize_Click(object sender, RoutedEventArgs e)
    {
        if (_sortField == SortField.Size) _sortAscending = !_sortAscending;
        else { _sortField = SortField.Size; _sortAscending = true; }
        UpdateSortMenuChecks();
        ApplySearchFilter(SearchBox.Text);
        SaveCurrentSettings();
    }

    private void UpdateSortMenuChecks()
    {
        if (SortByNameItem != null) SortByNameItem.IsChecked = (_sortField == SortField.Name);
        if (SortByDateItem != null) SortByDateItem.IsChecked = (_sortField == SortField.Date);
        if (SortBySizeItem != null) SortBySizeItem.IsChecked = (_sortField == SortField.Size);
        if (SortByTypeItem != null) SortByTypeItem.IsChecked = (_sortField == SortField.Type);
        if (SortAscItem != null) SortAscItem.IsChecked = _sortAscending;
        if (SortDescItem != null) SortDescItem.IsChecked = !_sortAscending;

        var arrowGlyph = _sortAscending ? "\uE70E" : "\uE70D";
        if (SortNameArrow != null)
        {
            SortNameArrow.Visibility = (_sortField == SortField.Name) ? Visibility.Visible : Visibility.Collapsed;
            SortNameArrow.Glyph = arrowGlyph;
        }
        if (SortDateArrow != null)
        {
            SortDateArrow.Visibility = (_sortField == SortField.Date) ? Visibility.Visible : Visibility.Collapsed;
            SortDateArrow.Glyph = arrowGlyph;
        }
        if (SortTypeArrow != null)
        {
            SortTypeArrow.Visibility = (_sortField == SortField.Type) ? Visibility.Visible : Visibility.Collapsed;
            SortTypeArrow.Glyph = arrowGlyph;
        }
        if (SortSizeArrow != null)
        {
            SortSizeArrow.Visibility = (_sortField == SortField.Size) ? Visibility.Visible : Visibility.Collapsed;
            SortSizeArrow.Glyph = arrowGlyph;
        }
    }

    #region Tablo Sütun Boyutlandırma & Otomatik Sığdırma (Windows 11 Explorer Uyumu)

    private void ApplyColumnWidths()
    {
        try
        {
            if (ColHeaderDate != null) ColHeaderDate.Width = _showColDate ? new GridLength(_colDateWidth) : new GridLength(0);
            if (ColHeaderType != null) ColHeaderType.Width = _showColType ? new GridLength(_colTypeWidth) : new GridLength(0);
            if (ColHeaderSize != null) ColHeaderSize.Width = _showColSize ? new GridLength(_colSizeWidth) : new GridLength(0);

            if (ColSplitterDateCol != null) ColSplitterDateCol.Width = _showColDate ? new GridLength(6) : new GridLength(0);
            if (ColSplitterTypeCol != null) ColSplitterTypeCol.Width = _showColType ? new GridLength(6) : new GridLength(0);
            if (ColSplitterSizeCol != null) ColSplitterSizeCol.Width = _showColSize ? new GridLength(6) : new GridLength(0);

            if (BtnHeaderDate != null) BtnHeaderDate.Visibility = _showColDate ? Visibility.Visible : Visibility.Collapsed;
            if (BtnHeaderType != null) BtnHeaderType.Visibility = _showColType ? Visibility.Visible : Visibility.Collapsed;
            if (BtnHeaderSize != null) BtnHeaderSize.Visibility = _showColSize ? Visibility.Visible : Visibility.Collapsed;

            if (BorderSplitterDate != null) BorderSplitterDate.Visibility = _showColDate ? Visibility.Visible : Visibility.Collapsed;
            if (BorderSplitterType != null) BorderSplitterType.Visibility = _showColType ? Visibility.Visible : Visibility.Collapsed;
            if (BorderSplitterSize != null) BorderSplitterSize.Visibility = _showColSize ? Visibility.Visible : Visibility.Collapsed;

            FileItem.SharedColDateWidth = _showColDate ? new GridLength(_colDateWidth) : new GridLength(0);
            FileItem.SharedColTypeWidth = _showColType ? new GridLength(_colTypeWidth) : new GridLength(0);
            FileItem.SharedColSizeWidth = _showColSize ? new GridLength(_colSizeWidth) : new GridLength(0);

            FileItem.SharedColDateVisibility = _showColDate ? Visibility.Visible : Visibility.Collapsed;
            FileItem.SharedColTypeVisibility = _showColType ? Visibility.Visible : Visibility.Collapsed;
            FileItem.SharedColSizeVisibility = _showColSize ? Visibility.Visible : Visibility.Collapsed;

            foreach (var item in _items)
            {
                item.NotifyColumnSettingsChanged();
            }
        }
        catch { }
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern IntPtr LoadCursor(IntPtr hInstance, int lpCursorName);

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern IntPtr SetCursor(IntPtr hCursor);

    private const int IDC_SIZEWE = 32644;
    private const int IDC_ARROW = 32512;

    private static readonly System.Reflection.PropertyInfo? _protectedCursorProp =
        typeof(UIElement).GetProperty("ProtectedCursor", System.Reflection.BindingFlags.Instance | System.Reflection.NonPublic | System.Reflection.Public);

    private void SetElementCursor(FrameworkElement fe, bool isResize)
    {
        try
        {
            if (isResize)
            {
                var cursor = Microsoft.UI.Input.InputSystemCursor.Create(Microsoft.UI.Input.InputSystemCursorShape.SizeWestEast);
                _protectedCursorProp?.SetValue(fe, cursor);
                SetCursor(LoadCursor(IntPtr.Zero, IDC_SIZEWE));
            }
            else
            {
                _protectedCursorProp?.SetValue(fe, null);
                SetCursor(LoadCursor(IntPtr.Zero, IDC_ARROW));
            }
        }
        catch { }
    }

    private void Splitter_PointerEntered(object sender, PointerRoutedEventArgs e)
    {
        if (sender is FrameworkElement fe)
        {
            SetElementCursor(fe, true);
        }
    }

    private void Splitter_PointerExited(object sender, PointerRoutedEventArgs e)
    {
        if (sender is FrameworkElement fe)
        {
            SetElementCursor(fe, false);
        }
    }

    private void Splitter_PointerPressed(object sender, PointerRoutedEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is string colName)
        {
            _isResizingColumn = true;
            _resizingColumnName = colName;
            var pt = e.GetCurrentPoint(this.Content).Position;
            _resizeStartX = pt.X;

            if (colName == "Date") _resizeStartWidth = _colDateWidth;
            else if (colName == "Type") _resizeStartWidth = _colTypeWidth;
            else if (colName == "Size") _resizeStartWidth = _colSizeWidth;

            fe.CapturePointer(e.Pointer);
            e.Handled = true;
        }
    }

    private void Splitter_PointerMoved(object sender, PointerRoutedEventArgs e)
    {
        if (_isResizingColumn && sender is FrameworkElement fe)
        {
            var pt = e.GetCurrentPoint(this.Content).Position;
            double delta = pt.X - _resizeStartX;

            if (_resizingColumnName == "Date")
            {
                _colDateWidth = Math.Max(80, _resizeStartWidth - delta);
                ApplyColumnWidths();
            }
            else if (_resizingColumnName == "Type")
            {
                _colTypeWidth = Math.Max(70, _resizeStartWidth - delta);
                ApplyColumnWidths();
            }
            else if (_resizingColumnName == "Size")
            {
                _colSizeWidth = Math.Max(60, _resizeStartWidth - delta);
                ApplyColumnWidths();
            }
            e.Handled = true;
        }
    }

    private void Splitter_PointerReleased(object sender, PointerRoutedEventArgs e)
    {
        if (_isResizingColumn && sender is FrameworkElement fe)
        {
            _isResizingColumn = false;
            fe.ReleasePointerCapture(e.Pointer);
            SetElementCursor(fe, false);
            SaveCurrentSettings();
            e.Handled = true;
        }
    }

    private void Splitter_DoubleTapped(object sender, DoubleTappedRoutedEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is string colName)
        {
            AutoFitColumn(colName);
            e.Handled = true;
        }
    }

    private void AutoFitColumn(string colName)
    {
        if (colName == "Date") _colDateWidth = 180;
        else if (colName == "Type") _colTypeWidth = 140;
        else if (colName == "Size") _colSizeWidth = 100;
        ApplyColumnWidths();
        SaveCurrentSettings();
    }

    private void AutoFitAllColumns()
    {
        _colDateWidth = 180;
        _colTypeWidth = 140;
        _colSizeWidth = 100;
        ApplyColumnWidths();
        SaveCurrentSettings();
    }

    private void ResetColumnWidths()
    {
        _colDateWidth = 180;
        _colTypeWidth = 140;
        _colSizeWidth = 100;
        _showColDate = true;
        _showColType = true;
        _showColSize = true;
        ApplyColumnWidths();
        SaveCurrentSettings();
    }

    private void Header_RightTapped(object sender, RightTappedRoutedEventArgs e)
    {
        var menu = new MenuFlyout();

        var dateItem = new ToggleMenuFlyoutItem { Text = "Değiştirilme Tarihi", IsChecked = _showColDate };
        dateItem.Click += (s, args) =>
        {
            _showColDate = !_showColDate;
            ApplyColumnWidths();
            SaveCurrentSettings();
        };
        menu.Items.Add(dateItem);

        var typeItem = new ToggleMenuFlyoutItem { Text = "Tür", IsChecked = _showColType };
        typeItem.Click += (s, args) =>
        {
            _showColType = !_showColType;
            ApplyColumnWidths();
            SaveCurrentSettings();
        };
        menu.Items.Add(typeItem);

        var sizeItem = new ToggleMenuFlyoutItem { Text = "Boyut", IsChecked = _showColSize };
        sizeItem.Click += (s, args) =>
        {
            _showColSize = !_showColSize;
            ApplyColumnWidths();
            SaveCurrentSettings();
        };
        menu.Items.Add(sizeItem);

        menu.Items.Add(new MenuFlyoutSeparator());

        var autoFitItem = new MenuFlyoutItem { Text = "Tüm sütunları sığdır" };
        autoFitItem.Click += (s, args) => { AutoFitAllColumns(); };
        menu.Items.Add(autoFitItem);

        var resetItem = new MenuFlyoutItem { Text = "Varsayılan sütun boyutları" };
        resetItem.Click += (s, args) => { ResetColumnWidths(); };
        menu.Items.Add(resetItem);

        menu.ShowAt(sender as FrameworkElement, e.GetPosition(sender as UIElement));
    }

    private void HandleTypeToSelect(char c)
    {
        _typeToSelectTimer?.Stop();
        _typeToSelectQuery += char.ToLowerInvariant(c);

        var match = _items.FirstOrDefault(i => i.Name.StartsWith(_typeToSelectQuery, StringComparison.OrdinalIgnoreCase));
        if (match != null)
        {
            _selectedItem = match;
            if (_currentViewMode == ExplorerViewMode.Details)
            {
                FileListView.SelectedItem = match;
                FileListView.ScrollIntoView(match);
            }
            else if (_currentViewMode == ExplorerViewMode.Medium)
            {
                FileGridViewMedium.SelectedItem = match;
                FileGridViewMedium.ScrollIntoView(match);
            }
            else
            {
                FileGridView.SelectedItem = match;
                FileGridView.ScrollIntoView(match);
            }
        }

        _typeToSelectTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _typeToSelectTimer.Tick += (s, e) =>
        {
            _typeToSelectQuery = "";
            _typeToSelectTimer?.Stop();
        };
        _typeToSelectTimer.Start();
    }

    #endregion

    private void PreviewPaneToggle_Click(object sender, RoutedEventArgs e)
    {
        TogglePreviewPane();
    }

    private void ClosePreviewPane_Click(object sender, RoutedEventArgs e)
    {
        SetPreviewPaneVisibility(false, save: true);
    }

    private void UpdatePreviewPane(FileItem? item)
    {
        if (PreviewPane == null || PreviewPane.Visibility != Visibility.Visible) return;

        if (item == null)
        {
            if (PreviewEmptyState != null) PreviewEmptyState.Visibility = Visibility.Visible;
            if (PreviewContentState != null) PreviewContentState.Visibility = Visibility.Collapsed;
            return;
        }

        if (PreviewEmptyState != null) PreviewEmptyState.Visibility = Visibility.Collapsed;
        if (PreviewContentState != null) PreviewContentState.Visibility = Visibility.Visible;

        PreviewFileName.Text = item.Name;
        PreviewTypeBadge.Text = item.TypeDescription;
        PreviewSizeText.Text = item.FormattedSize;
        PreviewDateText.Text = item.FormattedDate;
        PreviewExtensionText.Text = string.IsNullOrEmpty(item.Extension) ? (item.IsDirectory ? "Klasör" : "Bilinmeyen") : item.Extension;
        PreviewPathText.Text = item.Path;

        if (PreviewTextScroll != null) PreviewTextScroll.Visibility = Visibility.Collapsed;
        if (PreviewImage != null) PreviewImage.Visibility = Visibility.Collapsed;
        if (PreviewIconContainer != null) PreviewIconContainer.Visibility = Visibility.Visible;

        if (item.IconImage != null)
        {
            PreviewIconImage.Source = item.IconImage;
            PreviewIconImage.Visibility = Visibility.Visible;
            PreviewIcon.Visibility = Visibility.Collapsed;
        }
        else
        {
            PreviewIconImage.Visibility = Visibility.Collapsed;
            PreviewIcon.Visibility = Visibility.Visible;
            PreviewIcon.Glyph = item.GlyphIcon;
            PreviewIcon.Foreground = item.IconBrush;
        }

        if (item.IsDirectory)
        {
            PreviewOpenButton.Content = "Klasöre Git";
            PreviewDownloadButton.Visibility = Visibility.Collapsed;
            return;
        }

        PreviewOpenButton.Content = item.IsPdf ? "PDF'i Aç / Önizle" : "Varsayılan Uygulamayla Aç";
        PreviewDownloadButton.Visibility = Visibility.Visible;

        var ext = item.Extension?.TrimStart('.').ToLowerInvariant() ?? "";
        bool isText = new[] { "txt", "md", "json", "xml", "csv", "log", "cs", "py", "js", "ts", "html", "css", "yml", "yaml", "sql", "ini", "sh", "bat" }.Contains(ext);

        if (item.IsImage)
        {
            var cacheDir = Path.Combine(Path.GetTempPath(), "HDriveCache");
            var cachedFile = Path.Combine(cacheDir, Path.GetFileName(item.Path));
            if (File.Exists(cachedFile))
            {
                try
                {
                    if (PreviewImage != null)
                    {
                        PreviewImage.Source = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri(cachedFile));
                        PreviewImage.Visibility = Visibility.Visible;
                    }
                    if (PreviewIconContainer != null) PreviewIconContainer.Visibility = Visibility.Collapsed;
                }
                catch { }
            }
            else
            {
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
                                    if (PreviewImage != null)
                                    {
                                        PreviewImage.Source = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri(downloaded));
                                        PreviewImage.Visibility = Visibility.Visible;
                                    }
                                    if (PreviewIconContainer != null) PreviewIconContainer.Visibility = Visibility.Collapsed;
                                }
                                catch { }
                            }
                        });
                    }
                });
            }
        }
        else if (isText && item.Size < 5 * 1024 * 1024)
        {
            var cacheDir = Path.Combine(Path.GetTempPath(), "HDriveCache");
            var cachedFile = Path.Combine(cacheDir, Path.GetFileName(item.Path));
            if (File.Exists(cachedFile))
            {
                try
                {
                    var content = File.ReadAllText(cachedFile);
                    if (content.Length > 8000) content = content.Substring(0, 8000) + "\n\n... (Önizleme sınırı)";
                    if (PreviewTextContent != null) PreviewTextContent.Text = content;
                    if (PreviewTextScroll != null) PreviewTextScroll.Visibility = Visibility.Visible;
                    if (PreviewIconContainer != null) PreviewIconContainer.Visibility = Visibility.Collapsed;
                }
                catch { }
            }
            else
            {
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
                                    var content = File.ReadAllText(downloaded);
                                    if (content.Length > 8000) content = content.Substring(0, 8000) + "\n\n... (Önizleme sınırı)";
                                    if (PreviewTextContent != null) PreviewTextContent.Text = content;
                                    if (PreviewTextScroll != null) PreviewTextScroll.Visibility = Visibility.Visible;
                                    if (PreviewIconContainer != null) PreviewIconContainer.Visibility = Visibility.Collapsed;
                                }
                                catch { }
                            }
                        });
                    }
                });
            }
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

    private void SearchBox_LostFocus(object sender, RoutedEventArgs e)
    {
        if (!string.IsNullOrEmpty(SearchBox.Text))
        {
            SearchBox.Text = "";
            ApplySearchFilter("");
        }
    }

    private async void NavView_ItemInvoked(NavigationView sender, NavigationViewItemInvokedEventArgs args)
    {
        if (args.IsSettingsInvoked)
        {
            await OpenSettingsDialogAsync();
        }
        else if (args.InvokedItemContainer is NavigationViewItem item)
        {
            if (item.Tag is string tag)
            {
                if (tag == "cloud")
                {
                    NavigateToPath("");
                }
                else if (tag.StartsWith("pinned:"))
                {
                    var pinnedPath = tag.Substring("pinned:".Length);
                    NavigateToPath(pinnedPath);
                }
                else if (tag == "local")
                {
                    FolderSyncEngine.Instance.OpenLocalFolderInExplorer();
                }
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

            // Eğer sağ tıklanan öğe mevcut seçimde değilse seçimi bu öğe yap
            var container = GetActiveItemContainer();
            if (container != null && !container.SelectedItems.Contains(item))
            {
                container.SelectedItems.Clear();
                container.SelectedItem = item;
            }

            if (item.IsDirectory)
            {
                ContextPinItem.Visibility = Visibility.Visible;
                if (IsFolderPinned(item.Path))
                {
                    ContextPinItem.Text = "Kenar Çubuğundan Kaldır";
                    ContextPinIcon.Glyph = "\uE77A";
                }
                else
                {
                    ContextPinItem.Text = "Kenar Çubuğuna Sabitle";
                    ContextPinIcon.Glyph = "\uE718";
                }
            }
            else
            {
                ContextPinItem.Visibility = Visibility.Collapsed;
            }
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

    private ListViewBase? GetActiveItemContainer()
    {
        if (FileListView.Visibility == Visibility.Visible) return FileListView;
        if (FileGridViewMedium.Visibility == Visibility.Visible) return FileGridViewMedium;
        if (FileGridView.Visibility == Visibility.Visible) return FileGridView;
        return null;
    }

    /// <summary>
    /// Aktif görünümdeki (Liste veya Izgara) tüm seçili öğeleri döner. Hiç seçim yoksa _selectedItem döner.
    /// </summary>
    private List<FileItem> GetSelectedItems()
    {
        var list = new List<FileItem>();
        if (FileListView.Visibility == Visibility.Visible && FileListView.SelectedItems != null)
        {
            list.AddRange(FileListView.SelectedItems.OfType<FileItem>());
        }
        else if (FileGridViewMedium.Visibility == Visibility.Visible && FileGridViewMedium.SelectedItems != null)
        {
            list.AddRange(FileGridViewMedium.SelectedItems.OfType<FileItem>());
        }
        else if (FileGridView.Visibility == Visibility.Visible && FileGridView.SelectedItems != null)
        {
            list.AddRange(FileGridView.SelectedItems.OfType<FileItem>());
        }

        if (list.Count == 0 && _selectedItem != null)
        {
            list.Add(_selectedItem);
        }
        return list;
    }

    private async void ContextDownload_Click(object sender, RoutedEventArgs e)
    {
        var itemsToDownload = GetSelectedItems().Where(i => !i.IsDirectory).ToList();
        if (itemsToDownload.Count == 0) return;

        if (itemsToDownload.Count == 1)
        {
            var item = itemsToDownload[0];
            var savePicker = new Windows.Storage.Pickers.FileSavePicker();
            savePicker.SuggestedStartLocation = Windows.Storage.Pickers.PickerLocationId.Downloads;
            savePicker.SuggestedFileName = item.Name;
            var ext = Path.GetExtension(item.Name);
            if (!string.IsNullOrEmpty(ext))
            {
                savePicker.FileTypeChoices.Add($"{ext.ToUpperInvariant().TrimStart('.')} Dosyası", new List<string> { ext });
            }
            savePicker.FileTypeChoices.Add("Tüm Dosyalar", new List<string> { "." });

            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
            WinRT.Interop.InitializeWithWindow.Initialize(savePicker, hwnd);

            var file = await savePicker.PickSaveFileAsync();
            if (file != null)
            {
                LoadingRing.IsActive = true;
                var server = CloudreveManager.Instance.ActiveServer;
                if (server != null)
                {
                    var client = new WebDAVClient(server);
                    var cachedFile = await client.DownloadFileToCacheAsync(item.Path);
                    if (!string.IsNullOrEmpty(cachedFile) && File.Exists(cachedFile))
                    {
                        File.Copy(cachedFile, file.Path, true);
                        Process.Start(new ProcessStartInfo { FileName = "explorer.exe", Arguments = $"/select,\"{file.Path}\"", UseShellExecute = true });
                    }
                }
                LoadingRing.IsActive = false;
            }
        }
        else
        {
            // Çoklu indirme: Kullanıcıdan hedef klasör seçmesini iste
            var folderPicker = new Windows.Storage.Pickers.FolderPicker();
            folderPicker.SuggestedStartLocation = Windows.Storage.Pickers.PickerLocationId.Downloads;
            folderPicker.FileTypeFilter.Add("*");

            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
            WinRT.Interop.InitializeWithWindow.Initialize(folderPicker, hwnd);

            var folder = await folderPicker.PickSingleFolderAsync();
            if (folder != null)
            {
                LoadingRing.IsActive = true;
                var server = CloudreveManager.Instance.ActiveServer;
                if (server != null)
                {
                    var client = new WebDAVClient(server);
                    foreach (var item in itemsToDownload)
                    {
                        var cachedFile = await client.DownloadFileToCacheAsync(item.Path);
                        if (!string.IsNullOrEmpty(cachedFile) && File.Exists(cachedFile))
                        {
                            var targetPath = Path.Combine(folder.Path, item.Name);
                            File.Copy(cachedFile, targetPath, true);
                        }
                    }
                }
                LoadingRing.IsActive = false;
            }
        }
    }

    #region Yerinde Yeniden Adlandırma (F2 Inline Rename)

    private void ContextRename_Click(object sender, RoutedEventArgs e)
    {
        var item = GetSelectedItems().FirstOrDefault() ?? _selectedItem;
        if (item != null)
        {
            BeginInlineRename(item);
        }
    }

    private void BeginInlineRename(FileItem? item)
    {
        if (item == null) return;

        // Diğer tüm öğelerin düzenleme durumunu kapat
        foreach (var it in _items)
        {
            if (it != item && it.IsEditing)
            {
                it.IsEditing = false;
            }
        }

        item.EditingName = item.Name;
        item.IsEditing = true;
    }

    private static readonly char[] InvalidFileNameChars = new[] { '/', '\\', ':', '*', '?', '"', '<', '>', '|' };

    private void InlineRenameTextBox_BeforeTextChanging(TextBox sender, TextBoxBeforeTextChangingEventArgs args)
    {
        if (args.NewText.IndexOfAny(InvalidFileNameChars) >= 0)
        {
            args.Cancel = true;
            if (SyncStatusText != null)
            {
                SyncStatusText.Text = "Dosya adları \\ / : * ? \" < > | karakterlerini içeremez";
            }
        }
    }

    private void InlineRenameTextBox_Loaded(object sender, RoutedEventArgs e)
    {
        if (sender is TextBox textBox)
        {
            textBox.Focus(FocusState.Programmatic);
            var text = textBox.Text ?? "";
            var isDir = (textBox.DataContext as FileItem)?.IsDirectory ?? false;
            var dotIndex = text.LastIndexOf('.');
            if (!isDir && dotIndex > 0)
            {
                textBox.Select(0, dotIndex);
            }
            else
            {
                textBox.SelectAll();
            }
        }
    }

    private async void InlineRenameTextBox_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (sender is TextBox textBox && textBox.DataContext is FileItem item)
        {
            if (e.Key == Windows.System.VirtualKey.Enter)
            {
                e.Handled = true;
                await CommitInlineRenameAsync(item, textBox.Text);
            }
            else if (e.Key == Windows.System.VirtualKey.Escape)
            {
                e.Handled = true;
                CancelInlineRename(item);
            }
            else if (e.Key == Windows.System.VirtualKey.F2)
            {
                e.Handled = true;
                // Windows Gezgini F2: Uzantısız seçim ile tümünü seçme arasında geçiş yap
                var text = textBox.Text ?? "";
                var isDir = item.IsDirectory;
                var dotIndex = text.LastIndexOf('.');
                if (!isDir && dotIndex > 0 && textBox.SelectionLength == dotIndex)
                {
                    textBox.SelectAll();
                }
                else if (!isDir && dotIndex > 0)
                {
                    textBox.Select(0, dotIndex);
                }
            }
            else if (e.Key == Windows.System.VirtualKey.Tab)
            {
                e.Handled = true;
                var isShift = Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(Windows.System.VirtualKey.Shift)
                    .HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);

                await CommitInlineRenameAsync(item, textBox.Text);

                // Windows Gezgini Tab standardı: Bir sonraki / önceki dosyayı yeniden adlandır
                var currentIdx = _items.IndexOf(item);
                if (currentIdx >= 0)
                {
                    int nextIdx = isShift ? currentIdx - 1 : currentIdx + 1;
                    if (nextIdx >= 0 && nextIdx < _items.Count)
                    {
                        var nextItem = _items[nextIdx];
                        _selectedItem = nextItem;
                        BeginInlineRename(nextItem);
                    }
                }
            }
        }
    }

    private async void InlineRenameTextBox_LostFocus(object sender, RoutedEventArgs e)
    {
        if (sender is TextBox textBox && textBox.DataContext is FileItem item && item.IsEditing)
        {
            await CommitInlineRenameAsync(item, textBox.Text);
        }
    }

    private void CancelInlineRename(FileItem item)
    {
        item.IsEditing = false;
        item.EditingName = item.Name;
    }

    private async Task CommitInlineRenameAsync(FileItem item, string newNameText)
    {
        if (!item.IsEditing) return;
        item.IsEditing = false;

        var newName = newNameText?.Trim();
        if (string.IsNullOrWhiteSpace(newName) || newName == item.Name)
        {
            item.EditingName = item.Name;
            return;
        }

        var server = CloudreveManager.Instance.ActiveServer;
        if (server == null) return;

        var client = new WebDAVClient(server);
        var parent = _currentPath.TrimEnd('/');
        var destPath = string.IsNullOrEmpty(parent) ? "/" + newName : parent + "/" + newName;

        LoadingRing.IsActive = true;
        var success = await client.MoveAsync(item.Path, destPath);
        LoadingRing.IsActive = false;

        if (success)
        {
            item.Name = newName;
            item.Path = destPath;
            if (SyncStatusText != null)
            {
                SyncStatusText.Text = $"Yeniden adlandırıldı: {newName}";
            }
            await LoadDirectoryAsync(_currentPath);
        }
        else
        {
            item.EditingName = item.Name;
            if (SyncStatusText != null)
            {
                SyncStatusText.Text = $"Yeniden adlandırılamadı: '{newName}'";
            }
        }
    }

    #endregion

    #region Sistem Panosu İşlemleri (Ctrl+C, Ctrl+X, Ctrl+V)

    private readonly List<FileItem> _clipboardItems = new();
    private bool _isClipboardCut = false;

    private void ContextCopy_Click(object sender, RoutedEventArgs e)
    {
        CopySelectedItemsToClipboard();
    }

    private void ContextCut_Click(object sender, RoutedEventArgs e)
    {
        CutSelectedItemsToClipboard();
    }

    private async void ContextPaste_Click(object sender, RoutedEventArgs e)
    {
        await PasteFromClipboardAsync();
    }

    private async void CopySelectedItemsToClipboard()
    {
        var selected = GetSelectedItems();
        if (selected.Count == 0) return;

        var server = CloudreveManager.Instance.ActiveServer;
        if (server == null) return;
        var client = new WebDAVClient(server);

        foreach (var it in _items) it.IsCut = false;
        _clipboardItems.Clear();
        _clipboardItems.AddRange(selected);
        _isClipboardCut = false;

        LoadingRing.IsActive = true;
        if (SyncStatusText != null)
        {
            SyncStatusText.Text = $"{selected.Count} öğe panoya hazırlanıyor...";
        }

        try
        {
            var localPaths = new List<string>();
            foreach (var item in selected)
            {
                if (item.IsDirectory)
                {
                    var dir = await client.DownloadFolderToCacheAsync(item.Path);
                    if (!string.IsNullOrEmpty(dir)) localPaths.Add(dir);
                }
                else
                {
                    var local = await client.DownloadFileToCacheAsync(item.Path);
                    if (!string.IsNullOrEmpty(local)) localPaths.Add(local);
                }
            }

            if (localPaths.Count > 0)
            {
                await WindowsClipboardHelper.SetClipboardFilesAsync(localPaths, isCut: false);
            }

            if (SyncStatusText != null)
            {
                SyncStatusText.Text = $"{selected.Count} öğe panoya kopyalandı (Masaüstü veya klasörlere yapıştırabilirsiniz)";
            }
        }
        catch (Exception ex)
        {
            if (SyncStatusText != null) SyncStatusText.Text = $"Kopyalama hatası: {ex.Message}";
        }
        finally
        {
            LoadingRing.IsActive = false;
        }
    }

    private async void CutSelectedItemsToClipboard()
    {
        var selected = GetSelectedItems();
        if (selected.Count == 0) return;

        var server = CloudreveManager.Instance.ActiveServer;
        if (server == null) return;
        var client = new WebDAVClient(server);

        foreach (var it in _items) it.IsCut = false;
        _clipboardItems.Clear();
        _clipboardItems.AddRange(selected);
        _isClipboardCut = true;

        foreach (var it in selected)
        {
            it.IsCut = true;
        }

        LoadingRing.IsActive = true;
        if (SyncStatusText != null)
        {
            SyncStatusText.Text = $"{selected.Count} öğe kesiliyor...";
        }

        try
        {
            var localPaths = new List<string>();
            foreach (var item in selected)
            {
                if (item.IsDirectory)
                {
                    var dir = await client.DownloadFolderToCacheAsync(item.Path);
                    if (!string.IsNullOrEmpty(dir)) localPaths.Add(dir);
                }
                else
                {
                    var local = await client.DownloadFileToCacheAsync(item.Path);
                    if (!string.IsNullOrEmpty(local)) localPaths.Add(local);
                }
            }

            if (localPaths.Count > 0)
            {
                await WindowsClipboardHelper.SetClipboardFilesAsync(localPaths, isCut: true);
            }

            if (SyncStatusText != null)
            {
                SyncStatusText.Text = $"{selected.Count} öğe kesildi (Masaüstü veya klasörlere yapıştırabilirsiniz)";
            }
        }
        catch (Exception ex)
        {
            if (SyncStatusText != null) SyncStatusText.Text = $"Kesme hatası: {ex.Message}";
        }
        finally
        {
            LoadingRing.IsActive = false;
        }
    }

    private async Task PasteFromClipboardAsync()
    {
        var server = CloudreveManager.Instance.ActiveServer;
        if (server == null) return;
        var client = new WebDAVClient(server);

        // 1. Windows Sistem Panosundan dışarıdan kopyalanan dosyaları kontrol et
        try
        {
            var clipData = Clipboard.GetContent();
            if (clipData.Contains(StandardDataFormats.StorageItems))
            {
                var storageItems = await clipData.GetStorageItemsAsync();
                if (storageItems != null && storageItems.Count > 0)
                {
                    LoadingRing.IsActive = true;
                    int successCount = 0;
                    foreach (var it in storageItems)
                    {
                        if (it is Windows.Storage.StorageFile file)
                        {
                            var ok = await client.UploadFileAsync(file.Path, _currentPath);
                            if (ok) successCount++;
                        }
                        else if (it is Windows.Storage.StorageFolder folder)
                        {
                            var ok = await client.UploadFolderRecursiveAsync(folder.Path, _currentPath);
                            if (ok) successCount++;
                        }
                    }
                    LoadingRing.IsActive = false;
                    if (SyncStatusText != null)
                    {
                        SyncStatusText.Text = $"{successCount} öğe panodan yüklendi";
                    }
                    await LoadDirectoryAsync(_currentPath);
                    return;
                }
            }
            else if (clipData.Contains(StandardDataFormats.Text))
            {
                var text = await clipData.GetTextAsync();
                if (!string.IsNullOrWhiteSpace(text))
                {
                    var lines = text.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                    var validPaths = lines.Where(l => File.Exists(l) || Directory.Exists(l)).ToList();
                    if (validPaths.Count > 0)
                    {
                        LoadingRing.IsActive = true;
                        int successCount = 0;
                        foreach (var path in validPaths)
                        {
                            if (File.Exists(path))
                            {
                                var ok = await client.UploadFileAsync(path, _currentPath);
                                if (ok) successCount++;
                            }
                            else if (Directory.Exists(path))
                            {
                                var ok = await client.UploadFolderRecursiveAsync(path, _currentPath);
                                if (ok) successCount++;
                            }
                        }
                        LoadingRing.IsActive = false;
                        if (SyncStatusText != null)
                        {
                            SyncStatusText.Text = $"{successCount} öğe panodan yüklendi";
                        }
                        await LoadDirectoryAsync(_currentPath);
                        return;
                    }
                }
            }
        }
        catch { }

        // 2. HDrive içi kesme / kopyalama yapıştırma işlemi
        if (_clipboardItems.Count > 0)
        {
            LoadingRing.IsActive = true;
            var parent = _currentPath.TrimEnd('/');

            foreach (var item in _clipboardItems)
            {
                var destPath = string.IsNullOrEmpty(parent) ? "/" + item.Name : parent + "/" + item.Name;
                if (item.Path.Equals(destPath, StringComparison.OrdinalIgnoreCase)) continue;

                if (_isClipboardCut)
                {
                    await client.MoveAsync(item.Path, destPath);
                }
                else
                {
                    var local = await client.DownloadFileToCacheAsync(item.Path);
                    if (!string.IsNullOrEmpty(local) && File.Exists(local))
                    {
                        await client.UploadFileAsync(local, _currentPath);
                    }
                }
            }

            foreach (var it in _items) it.IsCut = false;
            _clipboardItems.Clear();
            _isClipboardCut = false;
            LoadingRing.IsActive = false;

            await LoadDirectoryAsync(_currentPath);
        }
    }

    #endregion

    #region Dosya Özellikleri (Alt+Enter / Properties)

    private async void ContextProperties_Click(object sender, RoutedEventArgs e)
    {
        var item = GetSelectedItems().FirstOrDefault() ?? _selectedItem;
        if (item != null)
        {
            await ShowPropertiesAsync(item);
        }
    }

    private async Task ShowPropertiesAsync(FileItem? item)
    {
        if (item == null) return;

        try
        {
            var dialog = new FilePropertiesDialog(item)
            {
                XamlRoot = this.Content.XamlRoot
            };
            await dialog.ShowAsync();
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"ShowProperties error: {ex.Message}");
        }
    }

    #endregion

    #region Fare ile Çerçeve Çizerek Çoklu Seçim (Marquee / Rubber-Band Selection)

    private bool _isMarqueeSelecting = false;
    private Windows.Foundation.Point _marqueeStartPoint;

    private static bool IsItemOrChildOfItem(DependencyObject? obj)
    {
        while (obj != null && obj is not ListViewBase)
        {
            if (obj is GridViewItem or ListViewItem) return true;
            if (obj is FrameworkElement fe && fe.DataContext is FileItem) return true;
            obj = VisualTreeHelper.GetParent(obj);
        }
        return false;
    }

    private void FileArea_PointerPressed(object sender, PointerRoutedEventArgs e)
    {
        var point = e.GetCurrentPoint(FileAreaGrid);
        if (point.Properties.IsLeftButtonPressed)
        {
            if (e.OriginalSource is DependencyObject dep && IsItemOrChildOfItem(dep))
            {
                return;
            }

            if (!string.IsNullOrEmpty(SearchBox.Text))
            {
                SearchBox.Text = "";
                ApplySearchFilter("");
            }

            _isMarqueeSelecting = true;
            _marqueeStartPoint = point.Position;

            Canvas.SetLeft(SelectionBox, _marqueeStartPoint.X);
            Canvas.SetTop(SelectionBox, _marqueeStartPoint.Y);
            SelectionBox.Width = 0;
            SelectionBox.Height = 0;
            SelectionBox.Visibility = Visibility.Visible;

            FileAreaGrid.CapturePointer(e.Pointer);

            var isCtrl = Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(Windows.System.VirtualKey.Control)
                .HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);
            var isShift = Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(Windows.System.VirtualKey.Shift)
                .HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);

            if (!isCtrl && !isShift)
            {
                ClearSelection();
            }

            e.Handled = true;
        }
    }

    private void FileArea_PointerMoved(object sender, PointerRoutedEventArgs e)
    {
        if (!_isMarqueeSelecting) return;

        var currentPoint = e.GetCurrentPoint(FileAreaGrid).Position;

        var left = Math.Min(_marqueeStartPoint.X, currentPoint.X);
        var top = Math.Min(_marqueeStartPoint.Y, currentPoint.Y);
        var width = Math.Abs(currentPoint.X - _marqueeStartPoint.X);
        var height = Math.Abs(currentPoint.Y - _marqueeStartPoint.Y);

        Canvas.SetLeft(SelectionBox, left);
        Canvas.SetTop(SelectionBox, top);
        SelectionBox.Width = width;
        SelectionBox.Height = height;

        if (width > 4 && height > 4)
        {
            UpdateMarqueeSelection(new Windows.Foundation.Rect(left, top, width, height));
        }

        e.Handled = true;
    }

    private void FileArea_PointerReleased(object sender, PointerRoutedEventArgs e)
    {
        if (_isMarqueeSelecting)
        {
            _isMarqueeSelecting = false;
            SelectionBox.Visibility = Visibility.Collapsed;
            try
            {
                FileAreaGrid.ReleasePointerCapture(e.Pointer);
            }
            catch { }
            e.Handled = true;
        }
    }

    private void UpdateMarqueeSelection(Windows.Foundation.Rect marqueeRect)
    {
        var container = GetActiveItemContainer();
        if (container == null) return;

        for (int i = 0; i < container.Items.Count; i++)
        {
            if (container.ContainerFromIndex(i) is FrameworkElement itemElement && itemElement.DataContext is FileItem item)
            {
                var transform = itemElement.TransformToVisual(FileAreaGrid);
                var bounds = transform.TransformBounds(new Windows.Foundation.Rect(0, 0, itemElement.ActualWidth, itemElement.ActualHeight));

                bool intersects = RectIntersects(marqueeRect, bounds);
                if (intersects)
                {
                    if (!container.SelectedItems.Contains(item))
                    {
                        container.SelectedItems.Add(item);
                    }
                }
            }
        }
        UpdateItemCountStatus();
    }

    private static bool RectIntersects(Windows.Foundation.Rect r1, Windows.Foundation.Rect r2)
    {
        return !(r2.Left > r1.Right || r2.Right < r1.Left || r2.Top > r1.Bottom || r2.Bottom < r1.Top);
    }

    #endregion

    private async void ContextDelete_Click(object sender, RoutedEventArgs e)
    {
        var itemsToDelete = GetSelectedItems();
        if (itemsToDelete.Count == 0) return;

        var prompt = itemsToDelete.Count == 1
            ? $"'{itemsToDelete[0].Name}' öğesini silmek istediğinizden emin misiniz?"
            : $"Seçili {itemsToDelete.Count} öğeyi kalıcı olarak silmek istediğinizden emin misiniz?";

        var confirmDialog = new ContentDialog
        {
            Title = "Silinsin mi?",
            Content = prompt,
            PrimaryButtonText = "Sil",
            CloseButtonText = "İptal",
            DefaultButton = ContentDialogButton.Close,
            XamlRoot = this.Content.XamlRoot
        };

        var result = await confirmDialog.ShowAsync();
        if (result == ContentDialogResult.Primary)
        {
            LoadingRing.IsActive = true;
            var server = CloudreveManager.Instance.ActiveServer;
            if (server == null) { LoadingRing.IsActive = false; return; }

            var client = new WebDAVClient(server);

            FolderSyncEngine.Instance.SuppressWatcher(() =>
            {
                foreach (var item in itemsToDelete)
                {
                    try
                    {
                        var rel = item.Path.TrimStart('/').Replace('/', Path.DirectorySeparatorChar);
                        var localTarget = Path.Combine(FolderSyncEngine.Instance.LocalFolderPath, rel);
                        if (File.Exists(localTarget))
                        {
                            File.Delete(localTarget);
                        }
                        else if (Directory.Exists(localTarget))
                        {
                            Directory.Delete(localTarget, true);
                        }
                        FolderSyncEngine.Instance.UnregisterRemoteFile(item.Path);
                    }
                    catch { }
                }
            });

            foreach (var item in itemsToDelete)
            {
                await client.DeleteAsync(item.Path, item.IsDirectory);
            }

            _selectedItem = null;
            UpdatePreviewPane(null);
            LoadingRing.IsActive = false;
            await LoadDirectoryAsync(_currentPath);
        }
    }

    #region Sürükle ve Bırak (Drag & Drop) Desteği

    /// <summary>
    /// HDrive içinden Windows Masaüstüne, Explorer'a veya başka programlara dosya sürükleyip kopyalama (Çoklu Seçim Destekli Yerel Sürükleme)
    /// </summary>
    private void FileList_DragItemsStarting(object sender, DragItemsStartingEventArgs e)
    {
        try
        {
            var selectedItems = e.Items?.OfType<FileItem>().ToList() ?? new List<FileItem>();
            if (selectedItems.Count == 0)
            {
                selectedItems = GetSelectedItems();
            }

            if (selectedItems.Count == 0)
            {
                return;
            }

            if (selectedItems.Count == 1 && selectedItems[0].IsDirectory)
            {
                e.Data.Properties["HDrive_Folder_Name"] = selectedItems[0].Name;
                e.Data.Properties["HDrive_Folder_Path"] = selectedItems[0].Path;
            }

            var storageItems = new List<IStorageItem>();
            var syncFolder = FolderSyncEngine.Instance.LocalFolderPath;
            var cacheDir = Path.Combine(Path.GetTempPath(), "HDriveCache");
            Directory.CreateDirectory(cacheDir);

            foreach (var item in selectedItems)
            {
                string? localPath = null;
                var relPath = item.Path.TrimStart('/').Replace('/', Path.DirectorySeparatorChar);
                var syncPath = Path.Combine(syncFolder, relPath);

                if (File.Exists(syncPath) || Directory.Exists(syncPath))
                {
                    localPath = syncPath;
                }
                else
                {
                    var cachedPath = Path.Combine(cacheDir, Path.GetFileName(item.Path));
                    if (File.Exists(cachedPath))
                    {
                        localPath = cachedPath;
                    }
                    else if (item.IsDirectory)
                    {
                        var cachedFolderPath = Path.Combine(cacheDir, Path.GetFileName(item.Path.TrimEnd('/')));
                        Directory.CreateDirectory(cachedFolderPath);
                        localPath = cachedFolderPath;
                    }
                }

                if (!string.IsNullOrEmpty(localPath))
                {
                    if (File.Exists(localPath))
                    {
                        var sf = StorageFile.GetFileFromPathAsync(localPath).AsTask().GetAwaiter().GetResult();
                        storageItems.Add(sf);
                    }
                    else if (Directory.Exists(localPath))
                    {
                        var sf = StorageFolder.GetFolderFromPathAsync(localPath).AsTask().GetAwaiter().GetResult();
                        storageItems.Add(sf);
                    }
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
    }

    /// <summary>
    /// Eski UIElement drag tetikleyicisi (Gerektiğinde geriye dönük uyumluluk için korunur)
    /// </summary>
    private async void FileItem_DragStarting(UIElement sender, DragStartingEventArgs e)
    {
        var deferral = e.GetDeferral();
        try
        {
            var selectedItems = GetSelectedItems();
            if (selectedItems.Count == 0 && sender is FrameworkElement fe && fe.DataContext is FileItem singleItem)
            {
                selectedItems.Add(singleItem);
            }

            if (selectedItems.Count == 0)
            {
                deferral.Complete();
                return;
            }

            if (selectedItems.Count == 1 && selectedItems[0].IsDirectory)
            {
                e.Data.Properties["HDrive_Folder_Name"] = selectedItems[0].Name;
                e.Data.Properties["HDrive_Folder_Path"] = selectedItems[0].Path;
            }

            var storageItems = new List<IStorageItem>();
            var syncFolder = FolderSyncEngine.Instance.LocalFolderPath;
            var cacheDir = Path.Combine(Path.GetTempPath(), "HDriveCache");
            Directory.CreateDirectory(cacheDir);

            var config = CloudreveManager.Instance.ActiveServer;
            var client = new WebDAVClient(config);

            foreach (var item in selectedItems)
            {
                string? localPath = null;
                var relPath = item.Path.TrimStart('/').Replace('/', Path.DirectorySeparatorChar);
                var syncPath = Path.Combine(syncFolder, relPath);

                if (File.Exists(syncPath) || Directory.Exists(syncPath))
                {
                    localPath = syncPath;
                }
                else
                {
                    var cachedPath = Path.Combine(cacheDir, Path.GetFileName(item.Path));
                    if (File.Exists(cachedPath))
                    {
                        localPath = cachedPath;
                    }
                    else if (!item.IsDirectory)
                    {
                        localPath = await client.DownloadFileToCacheAsync(item.Path);
                    }
                    else
                    {
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
                        var sf = await StorageFolder.GetFolderFromPathAsync(localPath);
                        storageItems.Add(sf);
                    }
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
        var container = GetActiveItemContainer();
        container?.SelectAll();
        UpdateItemCountStatus();
    }

    private async void OpenSettings_Click(object sender, RoutedEventArgs e)
    {
        await OpenSettingsDialogAsync();
    }

    private async void LocalShareButton_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var dialog = new Views.LocalShareDialog
            {
                XamlRoot = this.Content.XamlRoot
            };
            await dialog.ShowAsync();
        }
        catch { }
    }

    #region Kenar Çubuğu Sabit Klasörler (Pinned Favorites)

    private List<PinnedFolder> _pinnedFolders = new();

    private string GetPinnedFoldersFilePath()
    {
        var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HDrive");
        Directory.CreateDirectory(dir);
        var server = CloudreveManager.Instance.ActiveServer;
        var serverKey = !string.IsNullOrEmpty(server?.Username) ? server.Username.Replace("@", "_").Replace(".", "_") : "global";
        return Path.Combine(dir, $"pinned_folders_{serverKey}.json");
    }

    private void LoadPinnedFolders()
    {
        try
        {
            var filePath = GetPinnedFoldersFilePath();
            if (File.Exists(filePath))
            {
                var json = File.ReadAllText(filePath);
                _pinnedFolders = System.Text.Json.JsonSerializer.Deserialize<List<PinnedFolder>>(json) ?? new();
            }
            else
            {
                _pinnedFolders = new();
            }
        }
        catch
        {
            _pinnedFolders = new();
        }
        UpdateFavoritesSidebar();
    }

    private void SavePinnedFolders()
    {
        try
        {
            var filePath = GetPinnedFoldersFilePath();
            var json = System.Text.Json.JsonSerializer.Serialize(_pinnedFolders, new System.Text.Json.JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(filePath, json);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Failed to save pinned folders: {ex.Message}");
        }
    }

    private void UpdateFavoritesSidebar()
    {
        // Önceki sabit klasör öğelerini temizle
        var itemsToRemove = NavView.MenuItems
            .OfType<NavigationViewItem>()
            .Where(item => item.Tag is string tag && tag.StartsWith("pinned:"))
            .ToList();

        foreach (var item in itemsToRemove)
        {
            NavView.MenuItems.Remove(item);
        }

        // Sabitlenen klasörleri ekle
        foreach (var pinned in _pinnedFolders)
        {
            var navItem = new NavigationViewItem
            {
                Content = pinned.Name,
                Tag = $"pinned:{pinned.Path}",
                Icon = new FontIcon 
                { 
                    Glyph = "\uE8B7", 
                    Foreground = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 234, 163, 0)) 
                }
            };

            var flyout = new MenuFlyout();
            var unpinItem = new MenuFlyoutItem
            {
                Text = "Kenar Çubuğundan Kaldır",
                Icon = new FontIcon { Glyph = "\uE77A" }
            };
            var pinnedPath = pinned.Path;
            unpinItem.Click += (s, e) => UnpinFolder(pinnedPath);
            flyout.Items.Add(unpinItem);
            navItem.ContextFlyout = flyout;

            NavView.MenuItems.Add(navItem);
        }
    }

    private void PinFolder(string name, string path)
    {
        var cleanPath = path.Trim('/');
        if (string.IsNullOrEmpty(cleanPath)) return;

        if (!_pinnedFolders.Any(p => p.Path.Equals(cleanPath, StringComparison.OrdinalIgnoreCase)))
        {
            _pinnedFolders.Add(new PinnedFolder(name, cleanPath));
            SavePinnedFolders();
            UpdateFavoritesSidebar();
        }
    }

    private void UnpinFolder(string path)
    {
        var cleanPath = path.Trim('/');
        _pinnedFolders.RemoveAll(p => p.Path.Equals(cleanPath, StringComparison.OrdinalIgnoreCase));
        SavePinnedFolders();
        UpdateFavoritesSidebar();
    }

    private bool IsFolderPinned(string path)
    {
        var cleanPath = path.Trim('/');
        return _pinnedFolders.Any(p => p.Path.Equals(cleanPath, StringComparison.OrdinalIgnoreCase));
    }

    private void ContextPin_Click(object sender, RoutedEventArgs e)
    {
        if (_selectedItem != null && _selectedItem.IsDirectory)
        {
            if (IsFolderPinned(_selectedItem.Path))
            {
                UnpinFolder(_selectedItem.Path);
            }
            else
            {
                PinFolder(_selectedItem.Name, _selectedItem.Path);
            }
        }
    }

    private void NavView_DragOver(object sender, DragEventArgs e)
    {
        e.AcceptedOperation = DataPackageOperation.Copy;
        e.DragUIOverride.Caption = "Kenar Çubuğuna Sabitle";
        e.DragUIOverride.IsCaptionVisible = true;
        e.DragUIOverride.IsGlyphVisible = true;
    }

    private async void NavView_Drop(object sender, DragEventArgs e)
    {
        try
        {
            if (e.DataView.Properties.TryGetValue("HDrive_Folder_Path", out var pathObj) &&
                pathObj is string path &&
                e.DataView.Properties.TryGetValue("HDrive_Folder_Name", out var nameObj) &&
                nameObj is string name)
            {
                PinFolder(name, path);
                return;
            }

            if (e.DataView.Contains(StandardDataFormats.StorageItems))
            {
                var items = await e.DataView.GetStorageItemsAsync();
                foreach (var storageItem in items)
                {
                    if (storageItem is StorageFolder folder)
                    {
                        PinFolder(folder.Name, folder.Name);
                    }
                }
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"NavView Drop error: {ex.Message}");
        }
    }

    #endregion

    #region Sabit Depolama Kotası (Storage Quota)

    private async Task RefreshStorageQuotaAsync()
    {
        try
        {
            var config = CloudreveManager.Instance.ActiveServer;
            if (config == null) return;
            var client = new WebDAVClient(config);
            var quota = await client.GetQuotaAsync();
            if (quota.HasValue)
            {
                var (used, total) = quota.Value;
                double percent = total > 0 ? ((double)used / total) * 100.0 : 0.0;
                percent = Math.Min(100.0, Math.Max(0.0, percent));

                DispatcherQueue.TryEnqueue(() =>
                {
                    StorageQuotaPercentText.Text = $"%{Math.Round(percent)}";
                    StorageQuotaProgressBar.Value = percent;
                    StorageQuotaDetailText.Text = $"{FormatBytes(used)} / {FormatBytes(total)}";

                    if (percent > 90.0)
                    {
                        StorageQuotaProgressBar.Foreground = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 232, 17, 35));
                    }
                    else if (percent > 75.0)
                    {
                        StorageQuotaProgressBar.Foreground = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 247, 99, 12));
                    }
                    else
                    {
                        StorageQuotaProgressBar.Foreground = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 0, 120, 215));
                    }
                });
            }
            else
            {
                DispatcherQueue.TryEnqueue(() =>
                {
                    StorageQuotaDetailText.Text = "Bilgi alınamadı";
                });
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Quota error: {ex.Message}");
        }
    }

    private static string FormatBytes(long bytes)
    {
        if (bytes < 1024) return $"{bytes} B";
        if (bytes < 1024 * 1024) return $"{(bytes / 1024.0):F1} KB";
        if (bytes < 1024 * 1024 * 1024) return $"{(bytes / (1024.0 * 1024.0)):F1} MB";
        return $"{(bytes / (1024.0 * 1024.0 * 1024.0)):F2} GB";
    }

    private async void RefreshQuotaButton_Click(object sender, RoutedEventArgs e)
    {
        await RefreshStorageQuotaAsync();
    }

    #endregion

    #region Derin Arama (Deep Search)

    private void SearchBox_QuerySubmitted(AutoSuggestBox sender, AutoSuggestBoxQuerySubmittedEventArgs args)
    {
        ApplySearchFilter(args.QueryText);
    }

    private async Task PerformDeepSearchAsync(string query)
    {
        if (string.IsNullOrWhiteSpace(query))
        {
            ApplySearchFilter("");
            return;
        }

        var config = CloudreveManager.Instance.ActiveServer;
        if (config == null) return;

        LoadingRing.IsActive = true;
        _items.Clear();

        var client = new WebDAVClient(config);

        async Task CrawlDirectoryAsync(string path, int depth)
        {
            if (depth > 4) return;
            try
            {
                var dirItems = await client.ListDirectoryAsync(path);
                foreach (var it in dirItems)
                {
                    if (it.Name.Contains(query, StringComparison.CurrentCultureIgnoreCase))
                    {
                        DispatcherQueue.TryEnqueue(() =>
                        {
                            if (!_items.Contains(it)) _items.Add(it);
                            ItemCountText.Text = $"{_items.Count} öğe (Derin Arama)";
                        });
                    }

                    if (it.IsDirectory)
                    {
                        await CrawlDirectoryAsync(it.Path, depth + 1);
                    }
                }
            }
            catch { }
        }

        await CrawlDirectoryAsync("", 0);

        LoadingRing.IsActive = false;
        ItemCountText.Text = $"{_items.Count} sonuç bulundu";
    }

    #endregion

    #endregion
}

public class ExplorerTabState
{
    public string CurrentPath { get; set; } = "";
    public List<string> History { get; set; } = new() { "" };
    public int HistoryIndex { get; set; } = 0;
}
