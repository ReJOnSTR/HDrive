# HDrive Windows - WinUI 3 / Microsoft UI XAML

HDrive'ın Windows sürümü, Microsoft'un en modern masaüstü çatısı olan **WinUI 3 (Windows App SDK / `microsoft-ui-xaml`)** ve **C# / .NET 8** kullanılarak geliştirilmiştir.

---

## 🎨 Windows 11 Fluent Design Özellikleri

- **Mica Arka Plan**: Windows 11'in yerel dinamik yarı saydam Mica efekti.
- **Özel Başlık Çubuğu (TitleBar)**: Pencere içine gömülü arama çubuğu (`AutoSuggestBox`) ve modern ikonlar.
- **Gezinti Menüsü (NavigationView)**: Windows 11 Dosya Gezgini sol menüsü gibi (`Cloudreve`, `Yerel Klasör`, `Ayarlar`).
- **Yol Çubuğu (BreadcrumbBar)**: Klasör derinliklerini tıklanabilir bağlantılar olarak gösterir (`Cloudreve > DOSYALAR > ...`).
- **Komut Çubuğu (CommandBar)**:
  - Yeni Klasör Oluşturma
  - Dosya Yükleme (Windows FileOpenPicker)
  - Yenile
  - Görünüm Değiştirici (Büyük Simgeler / Ayrıntılı Liste)
- **Çift Tıklamayla Açma**: Tıklanan dosyayı anlık olarak önbelleğe alıp varsayılan Windows uygulamasında (Word, Excel, Adobe Reader, Medya Oynatıcı vb.) açar.
- **Yerel Eşitleme (OneDrive Modu)**: Dosyaları arka planda `%USERPROFILE%\HDrive - Cloudreve` klasörüne eşitler.

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
     dotnet publish -c Release -r win-x64 --self-contained -p:PublishSingleFile=true
     ```
