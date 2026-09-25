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
            Program.ReportFatalError("AppDomain.UnhandledException", ex);
        };

        this.UnhandledException += (sender, args) =>
        {
            Program.ReportFatalError("App.UnhandledException (WinUI)", args.Exception);
        };

        try
        {
            this.InitializeComponent();
        }
        catch (Exception ex)
        {
            Program.ReportFatalError("App.InitializeComponent", ex);
            throw;
        }
    }

    protected override void OnLaunched(Microsoft.UI.Xaml.LaunchActivatedEventArgs args)
    {
        try
        {
            Program.WriteStartupLog("App.OnLaunched çağrıldı. MainWindow oluşturuluyor...");
            MainWindowInstance = new MainWindow();
            Program.WriteStartupLog("MainWindow oluşturuldu. MainWindow.Activate çağrılıyor...");
            MainWindowInstance.Activate();
            Program.WriteStartupLog("MainWindow.Activate başarıyla tamamlandı.");
        }
        catch (Exception ex)
        {
            Program.ReportFatalError("App.OnLaunched", ex);
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

