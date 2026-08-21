# MemWatch

MemWatch, macOS menü çubuğunda RAM, memory pressure, swap davranışı, depolama durumu ve enerji akışını akıllı şekilde izleyen hafif bir sistem sağlık uygulamasıdır.

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
- Bağlı harici yerel diskleri otomatik algılama
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

### Notifications

- Active Swap, Memory Pressure ve Critical memory durumlarında uyarı
- Düşük ve kritik depolama uyarıları
- Bellek uyarılarında escalation ve recovery davranışı
- Bildirimleri uygulama içinden açma/kapatma
- macOS bildirim izin durumunu gösterme

## Teknoloji

- Platform: macOS 13+
- Dil: Swift
- UI: SwiftUI + MenuBarExtra
- Native APIs: Mach, Foundation, Dispatch, UserNotifications, AppKit, IOKit / IOPowerSources
- Dock davranışı: `LSUIElement=YES` + `.accessory` activation policy

## Durum

Sprint 1-5 tamamlandı:

1. Core Memory Monitoring
2. Swap Intelligence
3. Menu Bar Experience & Smart Notifications
4. Storage Monitoring
5. Energy Monitoring

Tüm mevcut çekirdek özellikler macOS CI build ve davranış testleriyle doğrulanmaktadır.

Sıradaki ana faz: Advanced Diagnostics.

## Lisans

TBD
