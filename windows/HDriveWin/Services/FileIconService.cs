using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.UI.Xaml.Media.Imaging;

namespace HDriveWin.Services;

/// <summary>
/// Windows Shell32 API kullanarak sistemde kurulu gerçek uygulamaların ve Windows 11'in
/// orijinal, yüksek çözünürlüklü ve renkli dosya/klasör simgelerini (.ico / PNG) sağlayan servis.
/// </summary>
public static class FileIconService
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct SHFILEINFO
    {
        public IntPtr hIcon;
        public int iIcon;
        public uint dwAttributes;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
        public string szDisplayName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 80)]
        public string szTypeName;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Auto)]
    private static extern IntPtr SHGetFileInfo(
        string pszPath,
        uint dwFileAttributes,
        out SHFILEINFO psfi,
        uint cbFileInfo,
        uint uFlags);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(IntPtr hIcon);

    private const uint SHGFI_ICON = 0x000000100;
    private const uint SHGFI_USEFILEATTRIBUTES = 0x000000010;
    private const uint SHGFI_LARGEICON = 0x000000000; // 32x32 / 48x48 sistem çözünürlüğü
    private const uint SHGFI_SMALLICON = 0x000000001; // 16x16 ayrıntılar listesi
    private const uint FILE_ATTRIBUTE_NORMAL = 0x00000080;
    private const uint FILE_ATTRIBUTE_DIRECTORY = 0x00000010;

    // Uzantı bazlı bellek önbelleği (Örn: ".xlsx" -> BitmapImage). Bir kez çekildikten sonra 0ms ve sıfır bellek tüketimiyle anında döner.
    private static readonly ConcurrentDictionary<string, BitmapImage?> _largeIconCache = new(StringComparer.OrdinalIgnoreCase);
    private static readonly ConcurrentDictionary<string, BitmapImage?> _smallIconCache = new(StringComparer.OrdinalIgnoreCase);

    public static BitmapImage? GetIcon(string filename, bool isDirectory, bool large = true)
    {
        var cacheKey = isDirectory ? "__directory__" : Path.GetExtension(filename).ToLowerInvariant();
        if (string.IsNullOrEmpty(cacheKey)) cacheKey = "__file__";

        var cache = large ? _largeIconCache : _smallIconCache;
        if (cache.TryGetValue(cacheKey, out var cached))
        {
            return cached;
        }

        var image = ExtractShellIcon(cacheKey, isDirectory, large);
        cache[cacheKey] = image;
        return image;
    }

    private static BitmapImage? ExtractShellIcon(string extOrKey, bool isDirectory, bool large)
    {
        try
        {
            var flags = SHGFI_ICON | SHGFI_USEFILEATTRIBUTES | (large ? SHGFI_LARGEICON : SHGFI_SMALLICON);
            var attr = isDirectory ? FILE_ATTRIBUTE_DIRECTORY : FILE_ATTRIBUTE_NORMAL;
            var path = isDirectory ? "folder" : (extOrKey.StartsWith(".") ? extOrKey : "." + extOrKey);

            var shinfo = new SHFILEINFO();
            var res = SHGetFileInfo(path, attr, out shinfo, (uint)Marshal.SizeOf(shinfo), flags);
            if (res != IntPtr.Zero && shinfo.hIcon != IntPtr.Zero)
            {
                try
                {
                    using var icon = Icon.FromHandle(shinfo.hIcon);
                    using var bmp = icon.ToBitmap();
                    using var ms = new MemoryStream();
                    bmp.Save(ms, ImageFormat.Png);
                    ms.Position = 0;

                    var bitmapImage = new BitmapImage();
                    using var ras = ms.AsRandomAccessStream();
                    bitmapImage.SetSource(ras);
                    return bitmapImage;
                }
                finally
                {
                    DestroyIcon(shinfo.hIcon);
                }
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"FileIconService error for {extOrKey}: {ex.Message}");
        }

        return null;
    }
}
