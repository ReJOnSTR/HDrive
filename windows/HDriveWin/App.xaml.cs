using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;

namespace HDriveWin;

public partial class App : Application
{
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int MessageBox(IntPtr hWnd, string text, string caption, uint type);

    public static MainWindow? MainWindowInstance { get; private set; }

    public App()
    {
        AppDomain.CurrentDomain.UnhandledException += (sender, args) =>
        {
            var ex = args.ExceptionObject as Exception;
            LogCrash("AppDomain.UnhandledException", ex);
            ShowCrashDialog("Kritik Hata (AppDomain)", ex);
        };

        this.UnhandledException += (sender, args) =>
        {
            LogCrash("App.UnhandledException", args.Exception);
            ShowCrashDialog("Arayüz Hatası (WinUI)", args.Exception);
            args.Handled = true;
        };

        try
        {
            this.InitializeComponent();
        }
        catch (Exception ex)
        {
            LogCrash("App.InitializeComponent", ex);
            ShowCrashDialog("Bileşen Başlatma Hatası", ex);
            throw;
        }
    }

    protected override void OnLaunched(Microsoft.UI.Xaml.LaunchActivatedEventArgs args)
    {
        try
        {
            MainWindowInstance = new MainWindow();
            MainWindowInstance.Activate();
        }
        catch (Exception ex)
        {
            LogCrash("App.OnLaunched", ex);
            ShowCrashDialog("Pencere Başlatma Hatası", ex);
        }
    }

    public static void LogCrash(string source, Exception? ex)
    {
        try
        {
            var appData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            var logDir = Path.Combine(appData, "HDrive");
            Directory.CreateDirectory(logDir);
            var logPath = Path.Combine(logDir, "crash.log");

            var message = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] [{source}] {ex?.GetType().FullName}: {ex?.Message}\n{ex?.StackTrace}\n";
            if (ex?.InnerException != null)
            {
                message += $"InnerException: {ex.InnerException.GetType().FullName}: {ex.InnerException.Message}\n{ex.InnerException.StackTrace}\n";
            }
            message += new string('-', 80) + "\n";
            File.AppendAllText(logPath, message);
        }
        catch { }
    }

    private static void ShowCrashDialog(string title, Exception? ex)
    {
        try
        {
            var message = $"HDrive başlatılırken bir hata oluştu:\n\n{ex?.Message}\n\nDetaylar crash.log dosyasına kaydedildi.";
            MessageBox(IntPtr.Zero, message, $"HDrive - {title}", 0x00000010 /* MB_ICONERROR */);
        }
        catch { }
    }
}

