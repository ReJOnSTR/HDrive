using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Threading;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;

namespace HDriveWin;

public static class Program
{
    [DllImport("Microsoft.ui.xaml.dll", EntryPoint = "XamlCheckProcessRequirements", SetLastError = true)]
    private static extern void XamlCheckProcessRequirements();

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int MessageBox(IntPtr hWnd, string text, string caption, uint type);

    private static readonly string LogDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "HDrive"
    );

    [STAThread]
    public static void Main(string[] args)
    {
        // Seviye 0: Saf Win32 / .NET çalışma zamanı. Hiçbir WinUI nesnesi referans edilmez.
        // Bu sayede JIT derleme hatası olsa dahi Main çalışır ve yakalar.
        try
        {
            Directory.CreateDirectory(LogDir);
            WriteStartupLog("HDrive başlatılıyor (Main)...");

            AppDomain.CurrentDomain.UnhandledException += (s, e) =>
            {
                var ex = e.ExceptionObject as Exception;
                WriteStartupLog($"[AppDomain.UnhandledException] {ex?.Message}\n{ex?.StackTrace}");
                ShowFatalDialog("Kritik Çalışma Zamanı Hatası", ex);
            };

            // Seviye 1: WinUI başlatıcıyı ayrı bir metoda delege et (NoInlining şart)
            RunWinUIApp(args);
        }
        catch (Exception ex)
        {
            WriteStartupLog($"[Main.Catch] {ex.GetType().FullName}: {ex.Message}\n{ex.StackTrace}");
            if (ex.InnerException != null)
            {
                WriteStartupLog($"[Main.InnerException] {ex.InnerException.GetType().FullName}: {ex.InnerException.Message}\n{ex.InnerException.StackTrace}");
            }
            ShowFatalDialog("Uygulama Başlatılamadı", ex);
        }
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void RunWinUIApp(string[] args)
    {
        WriteStartupLog("XamlCheckProcessRequirements kontrol ediliyor...");
        try
        {
            XamlCheckProcessRequirements();
        }
        catch (Exception ex)
        {
            WriteStartupLog($"XamlCheckProcessRequirements uyarı/hata: {ex.Message}");
        }

        WriteStartupLog("WinRT ComWrappers başlatılıyor...");
        WinRT.ComWrappersSupport.InitializeComWrappers();

        WriteStartupLog("Application.Start çağrılıyor...");
        Application.Start((p) =>
        {
            try
            {
                WriteStartupLog("DispatcherQueueSynchronizationContext ayarlanıyor...");
                var queue = DispatcherQueue.GetForCurrentThread();
                var context = new DispatcherQueueSynchronizationContext(queue);
                SynchronizationContext.SetSynchronizationContext(context);

                WriteStartupLog("App sınıfı başlatılıyor...");
                _ = new App();
            }
            catch (Exception ex)
            {
                WriteStartupLog($"[Application.Start.Callback Hatası] {ex.Message}\n{ex.StackTrace}");
                ShowFatalDialog("WinUI Başlatma Hatası", ex);
                throw;
            }
        });
    }

    public static void WriteStartupLog(string text)
    {
        try
        {
            Directory.CreateDirectory(LogDir);
            var path = Path.Combine(LogDir, "startup.log");
            File.AppendAllText(path, $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}] {text}\n");
        }
        catch { }
    }

    private static void ShowFatalDialog(string title, Exception? ex)
    {
        try
        {
            var logPath = Path.Combine(LogDir, "startup.log");
            var msg = $"HDrive başlatılamadı:\n\n{ex?.GetType().Name}: {ex?.Message}\n\nDetaylı kayıt dosyası:\n{logPath}";
            
            // Eğer eksik Windows App SDK ile ilgiliyse yönlendirici bilgi ekle
            if (ex is TypeLoadException || ex is DllNotFoundException || (ex != null && ex.Message.Contains("0x80040154")))
            {
                msg += "\n\nNot: Bilgisayarınızda 'Windows App SDK 1.5 Runtime' veya 'Visual C++ 2015-2022' eksik olabilir.";
            }

            MessageBox(IntPtr.Zero, msg, $"HDrive - {title}", 0x00000010 /* MB_ICONERROR */);
        }
        catch { }
    }
}
