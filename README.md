# HDrive 🚀
> Cloudreve ve Uzak WebDAV Sunucularına Bağlanan, **Mac Finder ve Windows Dosya Gezgini içerisine doğrudan bir disk (Z:\ / Volumes) olarak bağlanabilen**, hem iOS hem de macOS native Swift masaüstü uygulaması.

---

## 🌟 Öne Çıkan Özellikler

- ☁️ **Cloudreve & Uzak WebDAV Entegrasyonu:**
  - Sunucunuzdaki Cloudreve sistemine WebDAV (`/dav`) protokolü üzerinden güvenli (HTTPS / Basic Auth) bağlanır.
  - **PC'de Doğrudan Disk Olarak Açma:**
    - **macOS:** Tek tıkla Cloudreve'i Mac Finder'a `/Volumes/` altına gerçek bir harici disk gibi bağlar. Dosyaları doğrudan Mac Finder'da açabilir, sürükle-bırak yapabilir, silebilirsiniz.
    - **Windows:** Tek komutla (`net use Z: https://cloudreve.com/dav /user:...`) Windows Gezgini'ne `Z:\` sürücüsü olarak ekler.
- 📱 **Native Swift iOS Uygulaması (`iOS/HDrive.xcodeproj`):**
  - iPhone'unuzdan Cloudreve sunucunuza bağlanıp dosyalara göz atma, fotoğraf ve videoları doğrudan sunucuya yedekleme/yükleme.
  - İki yönlü yerel Wi-Fi WebDAV paylaşımı.
- 💻 **Native macOS Masaüstü Uygulaması (`macOS/HDrive.app`):**
  - SwiftUI & AppKit ile yazılmış gerçek masaüstü penceresi + Menü Çubuğu (Menu Bar Tray) simgesi.
  - Cloudreve bağlantı yöneticisi, kimlik doğrulama testi ve Finder disk mount motoru.

---

## 🚀 Cloudreve Kurulum ve Kullanım Adımları

### 1. Cloudreve WebDAV Bilgilerinizi Alma
1. Cloudreve web panelinize giriş yapın.
2. Sağ üst profil simgenize tıklayıp **WebDAV** veya **Hesap Ayarları** bölümüne gidin.
3. Bir WebDAV hesabı oluşturun veya var olan hesap bilgilerinizi alın:
   - **WebDAV Adresi:** `https://siteniz.com/dav`
   - **Kullanıcı Adı:** E-posta adresiniz veya WebDAV kullanıcı adınız
   - **Şifre:** WebDAV şifreniz (veya uygulama şifresi)

---

### 2. Mac Bilgisayarınızda Cloudreve'i Finder'a Bağlama

1. Bilgisayarınızdaki **HDrive** masaüstü uygulamasını açın:
   - Dosya yolu: `macOS/HDrive.app`
2. **Cloudreve Sunucusu** sekmesine gelin.
3. Sunucu adresi, kullanıcı adı ve WebDAV şifrenizi girin.
4. **"Bağlantıyı Test Et"** butonuna basarak sunucunun yanıt verdiğini doğrulayın.
5. **"Finder'a Disk Olarak Bağla"** butonuna tıklayın!
6. 🎉 **Cloudreve sunucunuz Mac Finder yan menüsünde ve masaüstünüzde harici bir sabit disk gibi açılacaktır!**
   - Dosyaları sanki bilgisayarınızın kendi klasöründeymiş gibi açabilir, düzenleyebilir ve içine dosya sürükleyebilirsiniz.

---

### 3. Windows PC'den Cloudreve'e Ağ Sürücüsü Olarak Bağlanma

Windows yüklü bir bilgisayardan Cloudreve'e doğrudan Dosya Gezgini üzerinden bağlanmak için:

1. **Komut İstemi (CMD)** veya **PowerShell**'i açın.
2. Şu komutu yazıp Enter'a basın:
   ```cmd
   net use Z: https://siteniz.com/dav /user:KULLANICI_ADI SIFRENIZ /persistent:yes
   ```
3. Dosya Gezgini'ni açtığınızda **`Z:\`** harfinde Cloudreve sunucunuz yer alacaktır!

---

### 4. iPhone Üzerinden Cloudreve'e Bağlanma

1. `iOS/HDrive.xcodeproj` projesini Mac'inizde Xcode ile açıp iPhone'unuza yükleyin.
2. İlk sekme olan **Cloudreve** sekmesine gelin.
3. Sunucu WebDAV adresinizi ve bilgilerinizi kaydedin.
4. Telefondan tüm Cloudreve dosyalarınıza anında erişin, fotoğraf arşivinizden sunucuya tek dokunuşla yükleme yapın.
