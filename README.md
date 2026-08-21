# MemWatch

MemWatch, macOS menü çubuğunda RAM, memory pressure, swap davranışı, depolama durumu, enerji akışı ve sistem sağlığını akıllı şekilde izleyen hafif bir uygulamadır.

## Amaç

Ham sayaçları göstermek yerine macOS kaynak kullanımını yorumlamak hedeflenir. Özellikle swap için yalnızca `Swap Used > 0` durumuna bakılmaz; aktif swap trafiği, memory pressure ve süreklilik birlikte değerlendirilir.

MemWatch gerçek bir menu-bar-only uygulamadır: Dock'ta uygulama ikonu göstermez.

## Mevcut Özellikler

### Memory Monitoring

- Menü çubuğunda anlık RAM yüzdesi
- Kullanılan ve kullanılabilir RAM
- Wired Memory
- Compressed Memory
- Cached Memory
- Native macOS memory-pressure event takibi
- Swap total / used / free
- Mach swap-in / swap-out sayaçları

### Swap Intelligence

- Idle Swap ile aktif swap ayrımı
- Swap readback algılama
- 60 saniyelik rolling history
- Transient spike filtreleme ve hysteresis
- Stable / Idle Swap / Readback / Active Swap / Pressure / Critical durumları
- Akıllı macOS bildirimleri

### Storage Monitoring

- Dahili diskleri otomatik algılama
- Bağlı fiziksel harici yerel diskleri otomatik algılama
- Mounted DMG / disk image volume'lerini depolama listesinden çıkarma
- Toplam kapasite
- Kullanılan alan
- Boş alan
- Doluluk yüzdesi
- Normal / Low Space / Critical durumları
- Disk listesini 30 saniyede bir yenileme
- Düşük alan bildirimleri
- Kritik seviyeye geçişte anında yeni uyarı
- Süregelen depolama uyarıları için 6 saat cooldown

### Energy Monitoring

- Güç kaynağını AC / Battery olarak algılama
- Batarya yüzdesi ve şarj durumunu gösterme
- Bataryadayken canlı Mac güç çekişini akım × voltaj üzerinden Watt olarak hesaplama
- Şarj olurken bataryaya giden canlı şarj gücünü Watt olarak gösterme
- Adaptörün nominal Watt kapasitesini ayrı gösterme
- Adapter → Mac, Adapter → Battery ve Battery → Mac yönlerini hareketli akışla gösterme
- 5 saniyelik enerji örnekleme
- Son 10 dakikalık canlı güç grafiği
- Son 10 dakikanın ortalama Watt değeri
- Tahmini kalan süre / doluma kalan süre bilgisi mevcutsa gösterme

> Adaptörün 70 W / 96 W gibi nominal değeri anlık tüketim değildir. macOS public API'leri AC'de Mac'in toplam priz tüketimini her modelde güvenilir şekilde sunmadığı için MemWatch bu değeri tahmin ederek göstermez. AC'de şarj varsa bataryaya giden gerçek şarj gücü gösterilir; bataryadayken ise Mac'in bataryadan çektiği güç gösterilir.

### Advanced Diagnostics

- Anlık sistem CPU kullanımı
- Son 10 dakikalık CPU + RAM geçmişi
- macOS sistem termal durumu: Nominal / Warm / Hot / Critical
- Low Power Mode durumu
- Çalışan uygulamaların resident-memory snapshot'ı
- Uygulama RAM toplamına helper/child process'leri dahil etme
- En çok RAM kullanan uygulamaların sıralanması
- Ağır süreç taramasını 30 saniyede bir yenileyerek düşük overhead
- Login-at-startup kontrolü
- macOS Login Items durumunu ve onay ihtiyacını gösterme
- Login Items ayarlarına doğrudan geçiş
- Termal durum ciddi veya kritik olduğunda ana durum özetine yansıtma

### Notifications

- Active Swap, Memory Pressure ve Critical memory durumlarında uyarı
- Düşük ve kritik depolama uyarıları
- Bellek uyarılarında escalation ve recovery davranışı
- Bildirimleri uygulama içinden açma/kapatma
- macOS bildirim izin durumunu gösterme
- Bildirim engelliyse System Settings bildirim sayfasına doğrudan geçiş

## Release Quality

MemWatch artık release-candidate kalite hattına sahiptir:

- Collector performans bütçeleri
- Arka plan polling / batarya-etkisi regresyon koruması
- Universal `arm64 + x86_64` Release build
- Ad-hoc imza doğrulaması
- DMG oluşturma, doğrulama ve mount testi
- SHA-256 checksum
- Her başarılı CI koşusunda indirilebilir DMG artifact
- Tag veya manuel çalıştırılabilen Release Package workflow

CI artifact'i Developer ID ile imzalanmış veya Apple tarafından notarize edilmiş bir public distribution paketi değildir. Gatekeeper uyarısı olmayan genel dağıtım için Developer ID signing + Apple notarization gerekir.

Ayrıntılı kalite ve fiziksel MacBook batarya A/B test protokolü `docs/RELEASE_QUALITY.md` içindedir.

## Teknoloji

- Platform: macOS 13+
- Dil: Swift
- UI: SwiftUI + native AppKit status-item/popover shell
- Native APIs: Mach, Foundation, Dispatch, UserNotifications, AppKit, IOKit / IOPowerSources, ServiceManagement, libproc
- Dock davranışı: `LSUIElement=YES` + `.accessory` activation policy

## Durum

Sprint 1-7 release-candidate kapsamı tamamlandı:

1. Core Memory Monitoring
2. Swap Intelligence
3. Menu Bar Experience & Smart Notifications
4. Storage Monitoring
5. Energy Monitoring
6. Advanced Diagnostics
7. Release Quality

Public dağıtım öncesinde kalan gerçek-dünya kapıları:

- Fiziksel MacBook üzerinde tekrarlı batarya A/B doğrulaması
- Developer ID Application signing
- Apple notarization + stapling

## Lisans

TBD
