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
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int MessageBox(IntPtr hWnd, string text, string caption, uint type);

    private const uint MB_OK = 0x00000000;
    private const uint MB_YESNO = 0x00000004;
    private const uint MB_ICONERROR = 0x00000010;
    private const uint MB_ICONQUESTION = 0x00000020;
    private const uint MB_TOPMOST = 0x00040000;
    private const uint MB_SETFOREGROUND = 0x00010000;
    private const int IDYES = 6;

    private static readonly string LogDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "HDrive"
    );

    [STAThread]
    public static void Main(string[] args)
    {
        // 1. Unpackaged / Self-contained Windows App SDK için temel dizin ortam değişkenini ayarla
        try
        {
            Environment.SetEnvironmentVariable("MICROSOFT_WINDOWSAPPRUNTIME_BASE_DIRECTORY", AppContext.BaseDirectory);
        }
        catch { }

        try
        {
            Directory.CreateDirectory(LogDir);
            WriteStartupLog("HDrive başlatılıyor (Main)...");

            AppDomain.CurrentDomain.UnhandledException += (s, e) =>
            {
                var ex = e.ExceptionObject as Exception;
                WriteStartupLog($"[AppDomain.UnhandledException] {ex?.Message}\n{ex?.StackTrace}");
                HandleOrReportError("AppDomain.UnhandledException", ex);
            };

            // WinUI uygulamasını başlat
            RunWinUIApp(args);
        }
        catch (Exception ex)
        {
            WriteStartupLog($"[Main.Catch] {ex.GetType().FullName}: {ex.Message}\n{ex.StackTrace}");
            HandleOrReportError("Program.Main", ex);
        }
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void RunWinUIApp(string[] args)
    {
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
                WriteStartupLog($"[Application.Start.Callback Hatası] {ex.Message}\n{ex.StackTrace}");
                HandleOrReportError("Application.Start.Callback", ex);
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

    public static void HandleOrReportError(string source, Exception? ex)
    {
        // Eğer hata Windows App SDK veya VC++ runtime eksikliğinden kaynaklanıyorsa ve yükleyici mevcutsa otomatik onarımı dene
        if (IsRuntimeMissingError(ex))
        {
            if (TryAutoInstallRuntimeAndRestart())
            {
                return;
            }
        }

        ReportFatalError(source, ex);
    }

    private static bool IsRuntimeMissingError(Exception? ex)
    {
        if (ex == null) return false;

        if (ex is TypeLoadException || ex is DllNotFoundException || ex is COMException)
        {
            return true;
        }

        var msg = (ex.Message + " " + (ex.InnerException?.Message ?? "")).ToLowerInvariant();
        if (msg.Contains("0x80040154") || // REGDB_E_CLASSNOTREG
            msg.Contains("0x8007007e") || // ERROR_MOD_NOT_FOUND
            msg.Contains("class not registered") ||
            msg.Contains("microsoft.ui.xaml") ||
            msg.Contains("windowsappruntime") ||
            msg.Contains("undockedregfree"))
        {
            return true;
        }

        return false;
    }

    private static bool TryAutoInstallRuntimeAndRestart()
    {
        try
        {
            var installerPath = Path.Combine(AppContext.BaseDirectory, "WindowsAppRuntimeInstall-x64.exe");
            if (!File.Exists(installerPath))
            {
                return false;
            }

            var dialogText = "HDrive'ı çalıştırmak için gereken 'Windows App SDK 1.5' bileşeni sisteminizde eksik veya kaydedilmemiş görünüyor.\n\n" +
                             "Gerekli bileşen (" + Path.GetFileName(installerPath) + ") otomatik olarak kurulsun mu?\n\n" +
                             "Kurulum tamamlandığında HDrive otomatik olarak açılacaktır.";

            var answer = MessageBox(
                IntPtr.Zero,
                dialogText,
                "HDrive - Eksik Sistem Bileşeni",
                MB_YESNO | MB_ICONQUESTION | MB_TOPMOST | MB_SETFOREGROUND
            );

            if (answer == IDYES)
            {
                WriteStartupLog("WindowsAppRuntimeInstall-x64.exe başlatılıyor (runas)...");
                var psi = new ProcessStartInfo
                {
                    FileName = installerPath,
                    Arguments = "--quiet",
                    UseShellExecute = true,
                    Verb = "runas"
                };

                var proc = Process.Start(psi);
                proc?.WaitForExit();
                WriteStartupLog($"WindowsAppRuntimeInstall-x64.exe tamamlandı. Çıkış kodu: {proc?.ExitCode}");

                // HDrive'ı yeniden başlat
                var currentExe = Environment.ProcessPath ?? Path.Combine(AppContext.BaseDirectory, "HDrive.exe");
                if (File.Exists(currentExe))
                {
                    Process.Start(new ProcessStartInfo
                    {
                        FileName = currentExe,
                        UseShellExecute = true
                    });
                }

                Environment.Exit(0);
                return true;
            }
        }
        catch (Exception ex)
        {
            WriteStartupLog($"Otomatik runtime kurulum hatası: {ex.Message}");
        }

        return false;
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
            sb.AppendLine("1. Bilgisayarınızda 'Windows App SDK 1.5 Runtime' veya 'Visual C++ 2015-2022' eksik olabilir.");
            sb.AppendLine("   Uygulama klasöründeki veya kurulum paketindeki 'WindowsAppRuntimeInstall-x64.exe' dosyasını sağ tıklayıp");
            sb.AppendLine("   'Yönetici olarak çalıştır' seçeneğiyle kurun.");
            sb.AppendLine("2. Sorun devam ederse bu dosyanın içeriğini geliştiriciye iletin.");
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
            MessageBox(IntPtr.Zero, dialogMsg, "HDrive - Başlatma Hatası", MB_OK | MB_ICONERROR | MB_TOPMOST | MB_SETFOREGROUND);
        }
        catch { }
    }
}

