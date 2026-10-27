<div align="center">

<img src="assets/logo.png" alt="GinDPI" width="120">

# GinDPI

**Discord, Roblox ve Wattpad gibi engelli sitelere erişim için sürücüsüz, yalnızca seçtiğiniz siteleri etkileyen Windows aracı.**

![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-0078D6)
![Flutter](https://img.shields.io/badge/Flutter-Dart-02569B)
![Sürücü](https://img.shields.io/badge/s%C3%BCr%C3%BCc%C3%BC-yok-success)

</div>

GinDPI, bilgisayarınızda küçük bir yerel vekil (proxy) ve DNS motoru çalıştırır. Seçtiğiniz sitelerin bağlantılarını, operatörün DPI (derin paket denetimi) sisteminin tanıyamayacağı şekilde parçalayarak gönderir. Diğer her şey (bankalar, ödeme sayfaları, oyunlar, geri kalan internet) olduğu gibi, dokunulmadan gider.

## Öne çıkanlar

- **Kur, unut.** Varsayılan olarak Windows ile birlikte sistem tepsisinde sessizce başlar ve kendiliğinden bağlanır. Discord için elle bir şey başlatmanız gerekmez.
- **Sürücü yok.** WinDivert gibi çekirdek sürücüleri yüklemez; kaldırınca arkasında iz bırakmaz.
- **Yalnızca seçtiğiniz siteler.** Discord, Roblox, Wattpad hazır paketler halindedir; kendi alan adlarınızı da ekleyebilirsiniz.
- **Otomatik yöntem arama.** İlk bağlantıda 6 farklı yöntemi paralel dener ve ağınızda çalışanı seçer.
- **Şifreli DNS (DoH).** DNS zehirlenmesini aşar (Cloudflare, Google, Quad9 veya otomatik).
- **Discord güncelleyicisi dahil.** "Tüm uygulamalar için çalış" modu, vekil ayarını dinlemeyen Discord masaüstü uygulamasını da kapsar.
- **Tanılama.** Bir şey çalışmıyorsa nedenini bulur ve tek tıkla çözüm önerir.
- **Temiz geri alma.** Windows'a yazılan her şey (otomatik proxy ayarı, DNS kuralı, zamanlanmış görev) bağlantıyı keserken, çıkarken veya kaldırırken geri alınır.

## Kurulum

[Releases](../../releases) sayfasından birini indirin:

| Dosya | Ne için |
|---|---|
| `GinDPI-Setup-x.y.z.exe` | Önerilen. Kurulum sihirbazı; Başlat menüsü, masaüstü kısayolu ve "Windows ile başlat" seçeneği. |
| `GinDPI-x.y.z-portable.zip` | Kurulumsuz. Klasörü çıkarın, `gindpi.exe`'yi çalıştırın. |

Gereksinim: Windows 10 veya 11 (64 bit). GinDPI yönetici izniyle açılır; bu izin, Windows'un DNS kuralını yazabilmesi ve açılışta sessizce başlayabilmesi için gereklidir.

## Kullanım

1. GinDPI'yı açın. İlk bağlantıda ağınıza uygun yöntem kendiliğinden aranır.
2. **Servisler** sayfasından hangi sitelerin yönlendirileceğini seçin (varsayılan: Discord).
3. Hepsi bu. Pencereyi kapatınca tepsiye küçülür ve çalışmaya devam eder. Tamamen çıkmak için tepsi simgesine sağ tıklayıp **Çıkış**'ı seçin.

Discord zaten açıksa bir kez yeniden başlatın. Sonrasında Discord her açıldığında GinDPI arka planda hazır olur.

### Sayfalar

| Sayfa | Ne yapar |
|---|---|
| Ana ekran | Bağlan / kes, canlı trafik grafiği, "Discord'u başlat" |
| Servisler | Yönlendirilecek siteleri seç, özel alan adı ekle |
| Tanılama | Sorun tespiti, "Hepsini dene" ile yöntem arama |
| Ayarlar | Yöntem, DoH, port, Windows ile başlat, tepsiye küçül |
| Günlük | Motor kayıtları |

## Nasıl çalışır?

```
Discord / tarayıcı ──► GinDPI (127.0.0.1) ──► parçalanmış TLS el sıkışması ──► internet
                         │
                         ├─ DoH ile şifreli alan adı çözümleme
                         └─ yalnızca seçili alan adları için (PAC + DNS kuralı)
```

- **Vekil (HTTP/CONNECT):** Seçili alan adlarının bağlantıları yerel vekile gelir; TLS `ClientHello` paketi, operatörün SNI'yı okuyamayacağı biçimde parçalara bölünerek gönderilir.
- **PAC:** Windows'a yalnızca seçili siteleri yönlendiren bir otomatik yapılandırma betiği tanıtılır.
- **Sistem modu:** Vekil ayarını dinlemeyen programlar için yerel bir DNS + SNI ileticisi çalışır ve yalnızca seçili alan adlarının DNS sorguları ona yönlendirilir (NRPT kuralı).
- **Başlangıç:** Pil ve süre sınırı olmayan, en yüksek yetkili bir zamanlanmış görev ile oturum açılışında başlar. Windows'un kayıt defterine "Run" girdisi eklenmez.

## Kaldırma

- **Kurulum sürümü:** Ayarlar > Uygulamalar'dan kaldırın. Kaldırıcı proxy ayarını, DNS kuralını ve zamanlanmış görevi kendisi temizler.
- **Taşınabilir sürüm:** Önce Ayarlar'dan "Windows ile birlikte başlat"ı kapatın, tepsiden **Çıkış** yapın, sonra klasörü silin.

Ayarlar `%APPDATA%\GinDPI` altında tutulur.

## Sorun giderme

| Belirti | Çözüm |
|---|---|
| Bağlanıyor ama site açılmıyor | **Tanılama** > "Hepsini dene" ile yöntemi yeniden aratın. |
| Discord sesi bağlanmıyor | Ayarlar > Gelişmiş > "Windows DNS'i şifreli yap". |
| Başka bir proxy / VPN kullanıyorum | GinDPI kullanıcının proxy ayarını ezmez; Discord'u **Discord'u başlat** düğmesiyle açın. |
| GoodbyeDPI / zapret açık | Çakışırlar; Tanılama sayfası bunları tespit edip kapatmayı önerir. |
| 53 veya 443 portu dolu | Bu portları kullanan programı kapatın; sistem modu aksi halde kapalı kalır. |

## Geliştirme

Gereksinimler: Flutter (stable, Windows desktop etkin) ve Visual Studio C++ iş yükü.

```bash
flutter pub get
flutter run -d windows          # geliştirme
flutter test                    # birim testleri
dart run bin/probe.dart         # arayüzsüz motor + yöntem denemesi (gerçek ağ)
```

Sürüm paketi (zip + kurulum sihirbazı, [Inno Setup 6](https://jrsoftware.org/isinfo.php) gerekir):

```powershell
powershell -ExecutionPolicy Bypass -File tools\package.ps1
```

Çıktılar `dist/` klasörüne yazılır. Sürüm numarası `pubspec.yaml`'dan alınır.

### Proje yapısı

```
lib/
  main.dart            Giriş, tepsi, pencere, komut satırı (--minimized, --cleanup, --startup-on)
  app/controller.dart  Arayüzün tek kaynağı: motor, Windows entegrasyonu, durum
  engine/              Vekil, DNS, DoH, TLS parçalama, tanılama (ayrı isolate'ta çalışır)
  system/              Ayar saklama, Windows entegrasyonu (PAC, NRPT, zamanlanmış görev)
  ui/                  Sayfalar ve ortak bileşenler
installer/gindpi.iss   Inno Setup betiği
tools/package.ps1      Release paketleme
```

## Uyarı

GinDPI, kendi bilgisayarınızdaki bağlantıların biçimini değiştirir; trafiğinizi başka bir sunucuya aktarmaz ve veri toplamaz. Bir VPN değildir, IP adresinizi gizlemez. Kullanımın kendi ülkenizdeki mevzuata uygunluğu sizin sorumluluğunuzdadır.

## Lisans

[MIT](LICENSE)
