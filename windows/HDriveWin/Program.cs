using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
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
        // Seviye 0: Saf Win32 / .NET çalışma zamanı.
        try
        {
            Directory.CreateDirectory(LogDir);
            WriteStartupLog("HDrive başlatılıyor (Main)...");

            AppDomain.CurrentDomain.UnhandledException += (s, e) =>
            {
                var ex = e.ExceptionObject as Exception;
                ReportFatalError("AppDomain.UnhandledException", ex);
            };

            // Seviye 1: WinUI başlatıcıyı çağır (NoInlining şart)
            RunWinUIApp(args);
        }
        catch (Exception ex)
        {
            ReportFatalError("Program.Main", ex);
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
            WriteStartupLog($"XamlCheckProcessRequirements uyarısı: {ex.Message}");
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

                WriteStartupLog("App sınıfı oluşturuluyor...");
                _ = new App();
            }
            catch (Exception ex)
            {
                ReportFatalError("Application.Start.Callback", ex);
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

    public static void ReportFatalError(string source, Exception? ex)
    {
        try
        {
            var sb = new StringBuilder();
            sb.AppendLine("================================================================================");
            sb.AppendLine("                      HDRIVE WINDOWS HATA RAPORU");
            sb.AppendLine("================================================================================");
            sb.AppendLine($"Tarih / Saat       : {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
            sb.AppendLine($"İşletim Sistemi    : {Environment.OSVersion} ({(Environment.Is64BitOperatingSystem ? "64-bit" : "32-bit")})");
            sb.AppendLine($".NET Sürümü        : {Environment.Version}");
            sb.AppendLine($"Çalışma Dizini     : {AppContext.BaseDirectory}");
            sb.AppendLine($"Komut Satırı       : {Environment.CommandLine}");
            sb.AppendLine($"Hata Kaynağı       : {source}");
            sb.AppendLine("--------------------------------------------------------------------------------");
            sb.AppendLine($"Hata Türü          : {ex?.GetType().FullName ?? "Bilinmiyor"}");
            sb.AppendLine($"Hata Mesajı        : {ex?.Message ?? "Belirtilmedi"}");
            sb.AppendLine("--------------------------------------------------------------------------------");
            sb.AppendLine("Yığın İzi (Stack Trace):");
            sb.AppendLine(ex?.StackTrace ?? "İz bulunamadı");

            var inner = ex?.InnerException;
            int level = 1;
            while (inner != null)
            {
                sb.AppendLine("--------------------------------------------------------------------------------");
                sb.AppendLine($"İç Hata (Level {level}) : {inner.GetType().FullName}");
                sb.AppendLine($"Mesaj               : {inner.Message}");
                sb.AppendLine(inner.StackTrace ?? "");
                inner = inner.InnerException;
                level++;
            }

            sb.AppendLine("================================================================================");
            sb.AppendLine("ÖNERİLEN ÇÖZÜMLER:");
            sb.AppendLine("1. Windows App SDK 1.5 Runtime veya Visual C++ 2015-2022 eksik olabilir.");
            sb.AppendLine("   Uygulama klasöründeki veya kurulumdaki 'WindowsAppRuntimeInstall-x64.exe' dosyasını çalıştırın.");
            sb.AppendLine("2. Sorun devam ederse bu dosyanın içeriğini GitHub Issues üzerinden geliştiriciye iletin.");
            sb.AppendLine("================================================================================");

            var reportContent = sb.ToString();

            // 1. Masaüstüne yaz
            string? desktopFile = null;
            try
            {
                var desktopDir = Environment.GetFolderPath(Environment.SpecialFolder.Desktop);
                if (!string.IsNullOrEmpty(desktopDir) && Directory.Exists(desktopDir))
                {
                    desktopFile = Path.Combine(desktopDir, "HDrive-Hata.txt");
                    File.WriteAllText(desktopFile, reportContent, Encoding.UTF8);
                }
            }
            catch { }

            // 2. Uygulama dizinine yaz
            string? localFile = null;
            try
            {
                localFile = Path.Combine(AppContext.BaseDirectory, "HDrive-Hata.txt");
                File.WriteAllText(localFile, reportContent, Encoding.UTF8);
            }
            catch { }

            // 3. LocalAppData dizinine yaz
            try
            {
                Directory.CreateDirectory(LogDir);
                var logFile = Path.Combine(LogDir, "startup.log");
                File.AppendAllText(logFile, "\n" + reportContent + "\n");
            }
            catch { }

            // 4. Hata dosyasını otomatik olarak Not Defteri ile aç
            var fileToOpen = desktopFile ?? localFile;
            if (!string.IsNullOrEmpty(fileToOpen) && File.Exists(fileToOpen))
            {
                try
                {
                    Process.Start(new ProcessStartInfo
                    {
                        FileName = "notepad.exe",
                        Arguments = $"\"{fileToOpen}\"",
                        UseShellExecute = true
                    });
                }
                catch { }
            }

            // 5. En önde kalacak şekilde Windows Mesaj Kutusu göster (MB_ICONERROR | MB_TOPMOST | MB_SETFOREGROUND)
            var dialogMsg = $"HDrive başlatılırken bir hata oluştu:\n\n{ex?.Message}\n\nHata detayları masaüstünüze 'HDrive-Hata.txt' olarak kaydedildi ve Not Defteri ile açıldı.";
            MessageBox(IntPtr.Zero, dialogMsg, "HDrive - Başlatma Hatası", 0x00000010 | 0x00040000 | 0x00010000);
        }
        catch { }
    }
}
