# HDrive

HDrive; Google Drive, OneDrive, WebDAV, Amazon S3 uyumlu depolar ve SMB hesapları
üzerindeki dosyaları yerel bir arayüzden yönetmek için geliştirilmiş bir masaüstü
ve iOS istemcisidir.

| Platform | Teknoloji | Kaynak / geliştirme hedefi |
| --- | --- | --- |
| Windows | C# / .NET 8 / WinUI 3 | `windows/HDriveWin`, x64 dağıtımı |
| macOS | Swift / SwiftUI / AppKit | `macOS/HDriveMac`, macOS 14+, Universal (arm64 ve x86_64) geliştirme derlemesi |
| iOS | Swift / SwiftUI | `iOS/HDrive.xcodeproj`, iOS simülatörü ve cihaz projesi |

## Dosya işlemleri

- Birden çok hesabı kaydetme, hesap değiştirme ve bağlantıyı kesme.
- Bulut klasörlerini sayfalayarak listeleme; dosya yükleme ve indirme.
- Google Docs/Sheets/Slides dosyalarını uygun Office/PDF formatında dışa aktarma.
- Windows'ta harici uygulamada kaydedilen dosyayı açıldığı hesaba ve özgün uzak
  dosyaya geri yükleme.
- S3 Signature Version 4 istekleri, bucket/prefix listeleme ve nesne işlemleri.
- iOS kaynaklarında yerel WebDAV paylaşımı; paylaşım klasörü ve yazma izinlerinin
  GET/PUT/COPY/MOVE/DELETE işlemlerinde denetlenmesi.

WebDAV hesabı, işletim sisteminin ağ sürücüsü araçlarıyla ayrıca bağlanabilir.
Hazır paketler [GitHub Releases](https://github.com/ReJOnSTR/HDrive/releases)
sayfasındadır. Önceden yayımlanmış paketler yeni kaynak değişikliklerini içermez.

## Dosyalar ve çalışma alanı

- Çevrimdışı dosya kopyaları, korunan çalışma kopyaları ve önbellek yönetimi.
- Yeniden açılışta geri gelen aktarım kuyruğu; Windows'ta doğrulayıcıyla korunan
  kısmi indirmelere devam etme.
- Klasör eşitleme önizlemesi, hariç tutma kuralları ve çakışma kararları.
- Google Drive çöp kutusu; Google/OneDrive paylaşım bağlantıları ve sürüm listeleri.
- iOS'ta güvenli içe aktarma, yerel çöp kutusu ve çoklu dosya işlemleri.

Platformlara ve sağlayıcılara göre kapsam ve sınırlamalar:
[UX-IMPLEMENTATION.md](docs/UX-IMPLEMENTATION.md).

## Geliştirme

Windows için Visual Studio 2022, .NET 8 SDK ve Windows App SDK geliştirme
araçları gerekir. Çalıştırma ve teşhis bilgileri: [Windows README](windows/README.md).

macOS üzerinde Xcode kuruluysa:

```sh
bash macOS/build-macos.sh
```

Universal uygulama `build/macos/HDrive.app` altında oluşturulur. iOS projesi
Xcode'da açılabilir veya imzalama gerektirmeyen simülatör derlemesi alınabilir:

```sh
xcodebuild -project iOS/HDrive.xcodeproj -scheme HDrive -sdk iphonesimulator \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

## Hesap güvenliği ve testler

Windows parola, token ve istemci sırlarını DPAPI/Windows kasasında; Apple
istemcileri Keychain'de saklar. Hesap dosyaları sır içermez. Eski hesaplar güvenli
kayda taşınır; kayıt hatasında mevcut dosya korunur ve hata kullanıcıya bildirilir.

```sh
dotnet run --project windows/tests/CoreRegression/CoreRegression.csproj
bash macOS/test-regressions.sh
```

Testler geçici hesaplar ve yerel HTTP fixture'ları kullanır. Yayın imzalama
kurulumu ve doğrulama sınırları: [RELEASE-SIGNING.md](docs/RELEASE-SIGNING.md).
