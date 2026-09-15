using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage;

namespace HDriveWin.Services;

/// <summary>
/// Windows işletim sistemi panosuna (Clipboard) yerel dosya ve klasörleri
/// hem modern WinUI/UWP (StorageItems) hem de yerel Win32 (CF_HDROP) formatında yazar.
/// Bu sayede Windows Gezgini (Masaüstü, klasörler) veya diğer uygulamalara doğrudan yapıştırma (Ctrl+V) yapılabilir.
/// </summary>
public static class WindowsClipboardHelper
{
    private const uint CF_HDROP = 15;
    private const uint GMEM_MOVEABLE = 0x0002;
    private const uint GMEM_ZEROINIT = 0x0040;
    private const uint GHND = GMEM_MOVEABLE | GMEM_ZEROINIT;

    [StructLayout(LayoutKind.Sequential)]
    private struct DROPFILES
    {
        public int pFiles;
        public int ptX;
        public int ptY;
        public int fNC;
        public int fWide;
    }

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool OpenClipboard(IntPtr hWndNewOwner);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseClipboard();

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EmptyClipboard();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetClipboardData(uint uFormat, IntPtr hMem);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern uint RegisterClipboardFormat(string lpszFormat);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalAlloc(uint uFlags, UIntPtr dwBytes);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalLock(IntPtr hMem);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GlobalUnlock(IntPtr hMem);

    public static async Task SetClipboardFilesAsync(IReadOnlyList<string> localPaths, bool isCut = false)
    {
        if (localPaths == null || localPaths.Count == 0) return;

        // 1. WinUI 3 DataPackage (Modern UWP / WinUI uygulamaları için)
        try
        {
            var dp = new DataPackage();
            dp.RequestedOperation = isCut ? DataPackageOperation.Move : DataPackageOperation.Copy;
            var storageItems = new List<IStorageItem>();
            foreach (var path in localPaths)
            {
                if (File.Exists(path))
                {
                    storageItems.Add(await StorageFile.GetFileFromPathAsync(path));
                }
                else if (Directory.Exists(path))
                {
                    storageItems.Add(await StorageFolder.GetFolderFromPathAsync(path));
                }
            }

            if (storageItems.Count > 0)
            {
                dp.SetStorageItems(storageItems);
            }
            dp.SetText(string.Join(Environment.NewLine, localPaths));
            Clipboard.SetContent(dp);
        }
        catch { }

        // 2. Win32 Yerel CF_HDROP formatı (Windows Gezgini, Masaüstü, Dosya Yöneticisi için)
        try
        {
            SetWin32FileDrop(localPaths, isCut);
        }
        catch { }
    }

    private static void SetWin32FileDrop(IReadOnlyList<string> localPaths, bool isCut)
    {
        // Unicode null-separated string with double-null termination
        var sb = new StringBuilder();
        foreach (var path in localPaths)
        {
            sb.Append(path);
            sb.Append('\0');
        }
        sb.Append('\0');

        byte[] pathBytes = Encoding.Unicode.GetBytes(sb.ToString());
        int dropFilesSize = Marshal.SizeOf<DROPFILES>();
        int totalSize = dropFilesSize + pathBytes.Length;

        IntPtr hGlobal = GlobalAlloc(GHND, (UIntPtr)totalSize);
        if (hGlobal == IntPtr.Zero) return;

        IntPtr pGlobal = GlobalLock(hGlobal);
        if (pGlobal == IntPtr.Zero) return;

        try
        {
            var df = new DROPFILES
            {
                pFiles = dropFilesSize,
                ptX = 0,
                ptY = 0,
                fNC = 0,
                fWide = 1 // Unicode = 1
            };

            Marshal.StructureToPtr(df, pGlobal, false);
            Marshal.Copy(pathBytes, 0, IntPtr.Add(pGlobal, dropFilesSize), pathBytes.Length);
        }
        finally
        {
            GlobalUnlock(hGlobal);
        }

        if (OpenClipboard(IntPtr.Zero))
        {
            try
            {
                EmptyClipboard();
                SetClipboardData(CF_HDROP, hGlobal);

                // Preferred DropEffect (DROPEFFECT_MOVE = 2, DROPEFFECT_COPY = 1)
                uint formatEffect = RegisterClipboardFormat("Preferred DropEffect");
                if (formatEffect != 0)
                {
                    IntPtr hEffect = GlobalAlloc(GHND, (UIntPtr)sizeof(uint));
                    if (hEffect != IntPtr.Zero)
                    {
                        IntPtr pEffect = GlobalLock(hEffect);
                        if (pEffect != IntPtr.Zero)
                        {
                            uint effect = isCut ? 2u : 1u;
                            Marshal.WriteInt32(pEffect, (int)effect);
                            GlobalUnlock(hEffect);
                            SetClipboardData(formatEffect, hEffect);
                        }
                    }
                }
            }
            finally
            {
                CloseClipboard();
            }
        }
    }
}
