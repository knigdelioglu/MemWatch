# MemWatch

macOS menü çubuğu uygulaması ile RAM kullanımı, memory pressure, swap davranışı, depolama durumu ve enerji tüketimini akıllı şekilde izleme projesi.

## Amaç

MemWatch, özellikle 16 GB RAM'li Apple Silicon Mac'lerde sistemin ne zaman bellek baskısı yaşadığını, SSD swap kullanımına geçtiğini, depolama durumunu ve enerji davranışını anlaşılır şekilde göstermek için tasarlanır.

## Temel Özellikler

### Memory Monitoring

- Menü çubuğunda anlık RAM durumu
- Memory Pressure takibi
- Swap kullanım algılama
- Swap-in / Swap-out hareketlerini izleme
- Akıllı durum renkleri
- Kritik durumda macOS bildirimi
- Bellek tüketen uygulamaların snapshot analizi

### Storage Monitoring

- Dahili disk kapasitesi
- Dahili disk doluluk oranı
- Boş alan takibi
- Harici disk algılama
- Harici disk kapasitesi ve doluluk oranı
- Düşük disk alanı uyarıları

### Energy Monitoring

- Anlık güç tüketimi (Watt)
- Hareketli enerji grafiği
- Adaptör ve batarya güç akışını gösterme
- Bataryadan çekilen güç
- Bataryaya giden şarj gücü
- Enerji kullanım geçmişi

## Tasarım İlkesi

Sadece ham değerleri göstermek yerine macOS kaynak kullanım davranışını yorumlamak hedeflenir.

Ölçümler:

- Physical RAM kullanımı
- Compressed Memory
- Wired Memory
- Cached Memory
- Memory Pressure
- Swap Used
- Swap değişim hızı
- Disk doluluk oranı
- Anlık güç tüketimi
- Enerji akış yönü

## Teknoloji Hedefi

- Platform: macOS
- Dil: Swift
- UI: SwiftUI + MenuBarExtra
- Veri kaynağı: macOS native APIs

## Vizyon

MemWatch yalnızca bir RAM göstergesi değil, Mac'in kaynak sağlık paneli olmayı hedefler.

Gelecek modüller:

- Termal durum
- CPU kullanımı
- Fan durumu
- Pil sağlığı

## Durum

Proje başlangıç aşamasındadır.

## Lisans

TBD
