using System;
using System.IO;
using System.Runtime.InteropServices;

namespace HDriveWin.Services;

/// <summary>
/// Windows Sistem Tepsisi (System Tray / NotifyIcon) entegrasyonu.
/// macOS MenuBarExtra özelliğinin Windows karşılığıdır.
/// </summary>
public sealed class SystemTrayService : IDisposable
{
    private const int WM_APP = 0x8000;
    private const int WM_TRAYICON = WM_APP + 42;
    private const int WM_COMMAND = 0x0111;
    private const int WM_LBUTTONDBLCLK = 0x0203;
    private const int WM_RBUTTONUP = 0x0205;
    private const int WM_CONTEXTMENU = 0x007B;

    private const uint NIM_ADD = 0x00000000;
    private const uint NIM_MODIFY = 0x00000001;
    private const uint NIM_DELETE = 0x00000002;
    private const uint NIF_MESSAGE = 0x00000001;
    private const uint NIF_ICON = 0x00000002;
    private const uint NIF_TIP = 0x00000004;

    private const uint IMAGE_ICON = 1;
    private const uint LR_LOADFROMFILE = 0x00000010;
    private const uint LR_DEFAULTSIZE = 0x00000040;

    private const uint MF_STRING = 0x00000000;
    private const uint MF_SEPARATOR = 0x00000800;
    private const uint MF_GRAYED = 0x00000001;
    private const uint TPM_RIGHTBUTTON = 0x0002;
    private const uint TPM_RETURNCMD = 0x0100;

    private const int GWLP_WNDPROC = -4;

    private const int CMD_OPEN_WINDOW = 1001;
    private const int CMD_OPEN_SETTINGS = 1002;
    private const int CMD_EXIT_APP = 1003;

    private delegate IntPtr WndProcDelegate(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NOTIFYICONDATA
    {
        public int cbSize;
        public IntPtr hWnd;
        public uint uID;
        public uint uFlags;
        public uint uCallbackMessage;
        public IntPtr hIcon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string szTip;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT
    {
        public int X;
        public int Y;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern bool Shell_NotifyIcon(uint dwMessage, ref NOTIFYICONDATA lpData);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr LoadImage(IntPtr hInst, string lpszName, uint uType, int cxDesired, int cyDesired, uint fuLoad);

    [DllImport("user32.dll")]
    private static extern IntPtr LoadIcon(IntPtr hInstance, IntPtr lpIconName);

    [DllImport("user32.dll")]
    private static extern bool DestroyIcon(IntPtr hIcon);

    [DllImport("user32.dll")]
    private static extern IntPtr CreatePopupMenu();

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool AppendMenu(IntPtr hMenu, uint uFlags, UIntPtr uIDNewItem, string? lpNewItem);

    [DllImport("user32.dll")]
    private static extern bool DestroyMenu(IntPtr hMenu);

    [DllImport("user32.dll")]
    private static extern int TrackPopupMenu(IntPtr hMenu, uint uFlags, int x, int y, int nReserved, IntPtr hWnd, IntPtr prcRect);

    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out POINT lpPoint);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
    private static extern IntPtr SetWindowLongPtr(IntPtr hWnd, int nIndex, IntPtr dwNewLong);

    [DllImport("user32.dll", EntryPoint = "CallWindowProcW")]
    private static extern IntPtr CallWindowProc(IntPtr lpPrevWndFunc, IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    private readonly IntPtr _hWnd;
    private readonly Action _onOpenWindow;
    private readonly Action _onOpenSettings;
    private readonly Action _onExit;
    private readonly WndProcDelegate _wndProcDelegate;
    private IntPtr _oldWndProc = IntPtr.Zero;
    private IntPtr _hIcon = IntPtr.Zero;
    private bool _ownsIcon;
    private bool _isAdded;
    private bool _disposed;

    public SystemTrayService(IntPtr hWnd, Action onOpenWindow, Action onOpenSettings, Action onExit)
    {
        _hWnd = hWnd;
        _onOpenWindow = onOpenWindow;
        _onOpenSettings = onOpenSettings;
        _onExit = onExit;
        _wndProcDelegate = WndProc;

        InitializeTrayIcon();
    }

    private void InitializeTrayIcon()
    {
        if (_hWnd == IntPtr.Zero) return;

        try
        {
            _oldWndProc = SetWindowLongPtr(_hWnd, GWLP_WNDPROC, Marshal.GetFunctionPointerForDelegate(_wndProcDelegate));

            var iconPath = Path.Combine(AppContext.BaseDirectory, "app.ico");
            if (File.Exists(iconPath))
            {
                _hIcon = LoadImage(IntPtr.Zero, iconPath, IMAGE_ICON, 16, 16, LR_LOADFROMFILE | LR_DEFAULTSIZE);
                _ownsIcon = _hIcon != IntPtr.Zero;
            }
            if (_hIcon == IntPtr.Zero)
            {
                _hIcon = LoadIcon(IntPtr.Zero, (IntPtr)32512); // IDI_APPLICATION
            }

            var nid = new NOTIFYICONDATA
            {
                cbSize = Marshal.SizeOf<NOTIFYICONDATA>(),
                hWnd = _hWnd,
                uID = 1,
                uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP,
                uCallbackMessage = WM_TRAYICON,
                hIcon = _hIcon,
                szTip = GetTooltipText()
            };

            _isAdded = Shell_NotifyIcon(NIM_ADD, ref nid);
        }
        catch { }
    }

    public void UpdateTooltip()
    {
        if (!_isAdded || _hWnd == IntPtr.Zero) return;
        try
        {
            var nid = new NOTIFYICONDATA
            {
                cbSize = Marshal.SizeOf<NOTIFYICONDATA>(),
                hWnd = _hWnd,
                uID = 1,
                uFlags = NIF_TIP,
                szTip = GetTooltipText()
            };
            Shell_NotifyIcon(NIM_MODIFY, ref nid);
        }
        catch { }
    }

    private static string GetTooltipText()
    {
        var active = CloudreveManager.Instance.ActiveServer;
        return active != null && !string.IsNullOrWhiteSpace(active.Name)
            ? $"HDrive — Bulut: {active.Name}"
            : "HDrive Bulut Gezgini";
    }

    private IntPtr WndProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam)
    {
        if (msg == WM_TRAYICON)
        {
            uint mouseMsg = (uint)(lParam.ToInt64() & 0xFFFF);
            if (mouseMsg == WM_LBUTTONDBLCLK)
            {
                _onOpenWindow();
                return IntPtr.Zero;
            }
            if (mouseMsg == WM_RBUTTONUP || mouseMsg == WM_CONTEXTMENU)
            {
                ShowContextMenu();
                return IntPtr.Zero;
            }
        }
        return _oldWndProc != IntPtr.Zero ? CallWindowProc(_oldWndProc, hWnd, msg, wParam, lParam) : IntPtr.Zero;
    }

    private void ShowContextMenu()
    {
        IntPtr hMenu = CreatePopupMenu();
        if (hMenu == IntPtr.Zero) return;

        try
        {
            var active = CloudreveManager.Instance.ActiveServer;
            var statusTitle = active != null ? $"Bulut: {active.Name}" : "HDrive Bulut Gezgini";
            AppendMenu(hMenu, MF_STRING | MF_GRAYED, UIntPtr.Zero, statusTitle);
            AppendMenu(hMenu, MF_SEPARATOR, UIntPtr.Zero, null);
            AppendMenu(hMenu, MF_STRING, (UIntPtr)CMD_OPEN_WINDOW, "HDrive'ı Göster");
            AppendMenu(hMenu, MF_STRING, (UIntPtr)CMD_OPEN_SETTINGS, "Ayarlar...");
            AppendMenu(hMenu, MF_SEPARATOR, UIntPtr.Zero, null);
            AppendMenu(hMenu, MF_STRING, (UIntPtr)CMD_EXIT_APP, "HDrive'dan Çık");

            GetCursorPos(out var pt);
            SetForegroundWindow(_hWnd);
            int cmd = TrackPopupMenu(hMenu, TPM_RIGHTBUTTON | TPM_RETURNCMD, pt.X, pt.Y, 0, _hWnd, IntPtr.Zero);

            switch (cmd)
            {
                case CMD_OPEN_WINDOW:
                    _onOpenWindow();
                    break;
                case CMD_OPEN_SETTINGS:
                    _onOpenSettings();
                    break;
                case CMD_EXIT_APP:
                    _onExit();
                    break;
            }
        }
        finally
        {
            DestroyMenu(hMenu);
        }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        try
        {
            if (_isAdded && _hWnd != IntPtr.Zero)
            {
                var nid = new NOTIFYICONDATA
                {
                    cbSize = Marshal.SizeOf<NOTIFYICONDATA>(),
                    hWnd = _hWnd,
                    uID = 1
                };
                Shell_NotifyIcon(NIM_DELETE, ref nid);
                _isAdded = false;
            }
        }
        catch { }

        try
        {
            if (_ownsIcon && _hIcon != IntPtr.Zero)
            {
                DestroyIcon(_hIcon);
                _hIcon = IntPtr.Zero;
            }
        }
        catch { }
    }
}

