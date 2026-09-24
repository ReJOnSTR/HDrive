using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;

namespace HDriveWin;

public static class Program
{
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int MessageBox(IntPtr hWnd, string text, string caption, uint type);

    [STAThread]
    public static void Main(string[] args)
    {
        // 1. Erken aşama kaza yakalayıcı (Crash handler)
        AppDomain.CurrentDomain.UnhandledException += (s, e) =>
        {
            var ex = e.ExceptionObject as Exception;
            App.LogCrash("Program.UnhandledException", ex);
            ShowFatalBox("Uygulama Başlatma Hatası", ex);
        };

        try
        {
            WinRT.ComWrappersSupport.InitializeComWrappers();

            Application.Start((p) =>
            {
                try
                {
                    var context = new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread());
                    SynchronizationContext.SetSynchronizationContext(context);
                    _ = new App();
                }
                catch (Exception ex)
                {
                    App.LogCrash("Application.Start.Callback", ex);
                    ShowFatalBox("WinUI Başlatma Hatası", ex);
                    throw;
                }
            });
        }
        catch (Exception ex)
        {
            App.LogCrash("Program.Main", ex);
            ShowFatalBox("Kritik Sistem Hatası", ex);
        }
    }

    private static void ShowFatalBox(string title, Exception? ex)
    {
        try
        {
            var appData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            var logPath = Path.Combine(appData, "HDrive", "crash.log");
            var msg = $"HDrive başlatılamadı:\n\n{ex?.Message}\n\nDetaylar kaydedildi:\n{logPath}";
            MessageBox(IntPtr.Zero, msg, $"HDrive - {title}", 0x00000010 /* MB_ICONERROR */);
        }
        catch { }
    }
}
