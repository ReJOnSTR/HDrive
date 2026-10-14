# v1.2.7 sonrası Windows açılış regresyonu

## Karşılaştırma

| Alan | v1.2.7 | Mevcut kaynak | Sonuç |
| --- | --- | --- | --- |
| Windows App SDK | `1.5.240607001` | `1.5.240607001` | SDK zaten çalışan sürümle aynı; hesap geçişindeki hata sürüyor. |
| Hesap kaydı | Tek hesap, `config.json` | Çoklu hesap, `servers.json`; eski dosyadan ilk açılışta geçiş | Geçiş sırasında `CloudreveManager` kurucusu `Persist()` çağırıyor. |
| Hesap modeli | Kaydedilen veri özellikleri | Ek olarak `IsActive`, durum metinleri ve WinUI fırçaları | Varsayılan JSON yazımı bu public getter'ları da değerlendiriyordu. |
| İlk hesap yüklemesi | Yöneticiyi yeniden çağıran bir getter yok | `IsActive` → `CloudreveManager.Instance` | Singleton henüz atanmadan yeniden oluşturulup yığın taşmasına neden oluyor. |

`IsActive` ve durum fırçaları `df8d965` değişikliğinde eklendi. Bu değişikliği içeren
ilk yerel sürüm etiketi `v1.3.1`. `v1.2.8` ve `v1.2.9` hesap modelinde bu getter yok.
Sonraki SDK ve açılış değişiklikleri bu döngüyü ortadan kaldırmıyor.

## Hata zinciri

```text
CloudreveManager.Instance
  → new CloudreveManager()
    → LoadServers(): eski config.json bulundu
      → Persist()
        → JsonSerializer.Serialize(ServerConfig)
          → ServerConfig.IsActive
            → CloudreveManager.Instance
              → new CloudreveManager() ...
```

`_instance ??= new CloudreveManager()` ataması kurucu döndükten sonra tamamlanır.
Bu nedenle kurucu içindeki kayıt işlemi henüz var olmayan singleton'ı tekrar
oluşturur. Yığın taşması normal hata yakalama/loglama akışını tamamlamadan
süreci kapatır. Temiz profille açılış testi eski hesap geçişini çalıştırmadığı için
bu hatayı yakalayamaz.

## Düzeltme

`ServerConfig` içindeki hesaplanan dokuz arayüz özelliğine `[JsonIgnore]` eklendi.
Hesap verileri aynı alanlarla kaydedilir; kayıt sırasında yöneticiye erişilmez ve
WinUI fırçaları oluşturulmaz. Bu, Microsoft'un
[özellikleri JSON kayıt işleminden çıkarma yöntemini](https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/ignore-properties)
kullanır.

## Doğrulama

- Gerçek `ServerConfig` ve .NET 8 `System.Text.Json` ile çalışan altı kontrol geçti:
  WebDAV, S3, SMB, Google Drive, OneDrive alanlarının korunması ve v1.2.7 hesabının
  yeni formatta kaydedilmesi. Testte yöneticiye veya arayüz fırçalarına erişim
  doğrudan hata üretir. Düzeltme öncesindeki model bu testte `IsActive` üzerinden
  yöneticiye eriştiği için başarısız oldu.
- Üretimdeki `CloudreveManager` ve hesap modeliyle ayrı bir geçici profilde
  eski hesap geçişi yeniden üretildi. Yalnızca profil yolu ve işletim sistemi
  bağımlılıkları test için değiştirildi. Önceki model `Stack overflow` ile çıktı
  (çıkış kodu 134); düzeltilmiş model hesabı ve aktif hesap seçimini koruyarak
  başarıyla çıktı (0). Aynı profil ile ikinci çalıştırma da başarılı oldu (0).
- Yayın akışına gerçek Windows EXE'siyle eski profil geçişi, kaydedilen alanların
  kontrolü ve ikinci açılış eklendi. Buradaki macOS ortamında Windows/WinUI
  arayüz testi çalıştırılmadı; bu kontrol GitHub Actions Windows runner'ında
  yayın paketinden önce çalışacak.

Yerel, arayüz bağımsız regresyon kontrolü:

```sh
dotnet run --project windows/tests/AccountSerialization/AccountSerialization.csproj -c Release
```

İzole GitHub Actions Windows runner'ındaki geçiş kontrolü:

```powershell
./windows/test-startup-upgrade.ps1 -ExePath ./windows/HDriveWin/publish_x64/HDrive.exe -VerifyMigration
```
