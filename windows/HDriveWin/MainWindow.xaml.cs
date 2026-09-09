using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Windows.Storage.Pickers;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
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
    private bool _isGridView = true;

    private FileItem? _selectedItem;

    public MainWindow()
    {
        this.InitializeComponent();

        SetupTitleBar();

        FileGridView.ItemsSource = _items;
        FileListView.ItemsSource = _items;
        PathBreadcrumbBar.ItemsSource = _breadcrumbs;

        // Başlangıç konumu
        NavigateToPath("");

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

    private void SetupTitleBar()
    {
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
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

        UpdateNavigationButtons();
        UpdateBreadcrumbs(path);
        await LoadDirectoryAsync(path);
    }

    private void UpdateNavigationButtons()
    {
        BackButton.IsEnabled = _historyIndex > 0;
        ForwardButton.IsEnabled = _historyIndex < _history.Count - 1;
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
        if (e.ClickedItem is not FileItem item) return;

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
            // Windows varsayılan uygulamasıyla aç
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

    private void ViewToggleButton_Click(object sender, RoutedEventArgs e)
    {
        _isGridView = !_isGridView;
        FileGridView.Visibility = _isGridView ? Visibility.Visible : Visibility.Collapsed;
        FileListView.Visibility = _isGridView ? Visibility.Collapsed : Visibility.Visible;
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
                await LoadDirectoryAsync(_currentPath);
            }
        }
    }
}
