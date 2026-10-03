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
            Program.WriteStartupLog($"[App.AppDomain.UnhandledException] {ex?.GetType().FullName}: {ex?.Message}\n{ex?.StackTrace}");
            Program.HandleOrReportError("AppDomain.UnhandledException", ex);
        };

        System.Threading.Tasks.TaskScheduler.UnobservedTaskException += (sender, args) =>
        {
            Program.WriteStartupLog($"[App.TaskScheduler.UnobservedTaskException] {args.Exception?.GetType().FullName}: {args.Exception?.Message}\n{args.Exception?.StackTrace}");
            args.SetObserved();
        };

        this.UnhandledException += (sender, args) =>
        {
            try
            {
                var ex = args.Exception;
                var msg = $"[App.UnhandledException (WinUI)] Mesaj: {args.Message}, Ex: {ex?.GetType().FullName}: {ex?.Message}\n{ex?.StackTrace}";
                Program.WriteStartupLog(msg);
                Program.HandleOrReportError("App.UnhandledException (WinUI)", ex);
            }
            catch (Exception handlerEx)
            {
                Program.WriteStartupLog($"[App.UnhandledException Handler Crash] {handlerEx.Message}");
            }
        };

        try
        {
            this.InitializeComponent();
        }
        catch (Exception ex)
        {
            Program.WriteStartupLog($"[App.InitializeComponent Hatasi] {ex.GetType().FullName}: {ex.Message}\n{ex.StackTrace}");
            Program.HandleOrReportError("App.InitializeComponent", ex);
            Environment.Exit(1);
        }
    }

    protected override void OnLaunched(Microsoft.UI.Xaml.LaunchActivatedEventArgs args)
    {
        try
        {
            Program.WriteStartupLog("Adim 6: App.OnLaunched cagrildi. MainWindow olusturuluyor...");
            MainWindowInstance = new MainWindow();
            Program.WriteStartupLog("Adim 7: MainWindow olusturuldu. MainWindow.Activate cagiriliyor...");
            MainWindowInstance.Activate();
            Program.WriteStartupLog("Adim 8: MainWindow.Activate basariyla tamamlandi.");
        }
        catch (Exception ex)
        {
            var msg = $"[App.OnLaunched Hatasi] {ex.GetType().FullName}: {ex.Message}\n{ex.StackTrace}";
            if (ex.InnerException != null)
            {
                msg += $"\n[Inner] {ex.InnerException.GetType().FullName}: {ex.InnerException.Message}\n{ex.InnerException.StackTrace}";
            }
            Program.WriteStartupLog(msg);
            Program.HandleOrReportError("App.OnLaunched", ex);
            Environment.Exit(1);
        }
    }

    public static void LogCrash(string source, Exception? ex)
    {
        var message = $"[CRASH {source}] {ex?.GetType().FullName}: {ex?.Message}\n{ex?.StackTrace}";
        if (ex?.InnerException != null)
        {
            message += $"\n[Inner] {ex.InnerException.GetType().FullName}: {ex.InnerException.Message}\n{ex.InnerException.StackTrace}";
        }
        Program.WriteStartupLog(message);

        try
        {
            var appData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            var logDir = Path.Combine(appData, "HDrive");
            Directory.CreateDirectory(logDir);
            var logPath = Path.Combine(logDir, "crash.log");
            File.AppendAllText(logPath, $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {message}\n" + new string('-', 80) + "\n");
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

