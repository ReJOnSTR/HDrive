# HDrive Windows - WinUI 3 / Microsoft UI XAML

HDrive'ın Windows sürümü, Microsoft'un en modern masaüstü çatısı olan **WinUI 3 (Windows App SDK / `microsoft-ui-xaml`)** ve **C# / .NET 8** kullanılarak geliştirilmiştir.

---

## 🎨 Windows 11 Fluent Design Özellikleri

- **Mica Arka Plan**: Windows 11'in yerel dinamik yarı saydam Mica efekti.
- **Özel Başlık Çubuğu (TitleBar)**: Pencere içine gömülü arama çubuğu (`AutoSuggestBox`) ve modern ikonlar.
- **Gezinti Menüsü (NavigationView)**: Windows 11 Dosya Gezgini sol menüsü gibi (`Cloudreve`, `Sabitlenen Klasörler`, `Ayarlar`).
- **Yol Çubuğu (BreadcrumbBar)**: Klasör derinliklerini tıklanabilir bağlantılar olarak gösterir (`Cloudreve > DOSYALAR > ...`).
- **Komut Çubuğu (CommandBar)**:
  - Yeni Klasör Oluşturma
  - Dosya Yükleme (Windows FileOpenPicker)
  - Yenile
  - Görünüm Değiştirici (Büyük Simgeler / Ayrıntılı Liste)
- **Çift Tıklamayla Açma**: Tıklanan dosyayı anlık olarak önbelleğe alıp varsayılan Windows uygulamasında (Word, Excel, Adobe Reader, Medya Oynatıcı vb.) açar. Doğrudan düzenleme (in-place live edit) ile kaydedilen değişiklikleri otomatik buluta geri yükler.

---

## 🚀 Gereksinimler ve Çalıştırma

1. **Gereksinimler**:
   - Windows 10 (1809+) veya Windows 11
   - [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
   - Visual Studio 2022 (v17.8+) veya Visual Studio Code (`C# Dev Kit` eklentisiyle)

2. **Çalıştırma**:
   - Terminalde:
     ```cmd
     cd windows\HDriveWin
     dotnet run -r win-x64
     ```
   - Veya doğrudan `windows\run-windows.bat` dosyasına çift tıklayın.

3. **Derleme (Tek Başına Çalışan EXE)**:
   - `windows\build-windows.bat` dosyasına çift tıklayın veya:
     ```cmd
     dotnet publish -c Release -p:Platform=x64 -r win-x64 --self-contained true -p:PublishSingleFile=false -p:PublishTrimmed=false
     ```

## Uygulama açılmıyorsa

PowerShell'de `diagnose-windows.ps1` dosyasının bulunduğu klasörde çalıştırın:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\diagnose-windows.ps1
```

Araç uygulamayı başlatır, 10 saniye bekler ve çıkış kodunu, gerekli dosyaların varlığını,
ilgili Windows Olay Günlüğü hatalarını ve `crash.log` dosyasının son satırlarını
masaüstündeki `HDrive-diagnostics.txt` dosyasına kaydeder. Taşınabilir sürüm farklı
bir klasördeyse `-ExePath "C:\klasor\HDrive.exe"` parametresini kullanın.
Paylaşmadan önce rapordaki yerel dosya yollarını ve hata mesajlarını kontrol edin.

GitHub Actions derleme süreci ayrıca `test-startup.ps1` ile yayın klasöründeki
uygulamayı açar. Test, `HDrive` ana penceresinin açılıp açık kaldığını ve yeni bir
başlangıç hatası kaydedilmediğini kontrol eder. Başarısız açılışlarda kurulum paketi
oluşturulmaz; `HDrive-Windows-Startup` artifact'i hata kayıtlarını içerir.

## v1.2.7 yükseltme hatası ve regresyon kontrolü

v1.3.1 ile gelen `ServerConfig.IsActive` özelliği, eski `config.json` dosyasının
`servers.json` biçimine taşınması sırasında JSON'a yazılmaya çalışılıyordu. Bu işlem
henüz oluşturulmakta olan `CloudreveManager.Instance`'ı tekrar oluşturup yığın
taşmasına neden oluyordu. Hesap modelindeki hesaplanan arayüz özellikleri artık
`[JsonIgnore]` ile kayıt işleminden çıkarıldı. Ayrıntılı karşılaştırma ve doğrulama
sonuçları: [STARTUP-REGRESSION.md](STARTUP-REGRESSION.md).

Arayüz bağımlılığı olmadan gerçek hesap modelinin kayıt işlemini test etmek için
depo kökünden çalıştırın:

```sh
dotnet run --project windows/tests/AccountSerialization/AccountSerialization.csproj -c Release
```

Yayın akışı ayrıca izole Windows runner'ında `test-startup-upgrade.ps1 -VerifyMigration`
ile eski hesapla ilk açılışı, hesabın ve aktif hesap seçiminin korunmasını ve yeniden
açılışı kontrol eder. Bu test başarısızsa kurulum paketi oluşturulmaz.
