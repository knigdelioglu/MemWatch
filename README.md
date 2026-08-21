# MemWatch

MemWatch, macOS menü çubuğunda RAM, memory pressure, swap davranışı ve depolama durumunu akıllı şekilde izleyen hafif bir sistem sağlık uygulamasıdır.

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

### Notifications

- Active Swap, Memory Pressure ve Critical memory durumlarında uyarı
- Düşük ve kritik depolama uyarıları
- Bellek uyarılarında escalation ve recovery davranışı
- Bildirimleri uygulama içinden açma/kapatma
- macOS bildirim izin durumunu gösterme

## Planlanan Energy Monitoring

- Anlık güç tüketimi (Watt)
- Adaptörden gelen güç
- Sistemin kullandığı güç
- Bataryaya giden şarj gücü
- Bataryadan çekilen güç
- Animasyonlu enerji akışı
- Canlı enerji grafiği

## Teknoloji

- Platform: macOS 13+
- Dil: Swift
- UI: SwiftUI + MenuBarExtra
- Native APIs: Mach, Foundation, Dispatch, UserNotifications, AppKit
- Dock davranışı: `LSUIElement=YES` + `.accessory` activation policy

## Durum

Sprint 1-4 tamamlandı:

1. Core Memory Monitoring
2. Swap Intelligence
3. Menu Bar Experience & Smart Notifications
4. Storage Monitoring

Sıradaki ana faz: Energy Monitoring.

## Lisans

TBD
