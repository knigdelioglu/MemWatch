# MemWatch

macOS menü çubuğu uygulaması ile RAM kullanımı, memory pressure ve swap davranışını akıllı şekilde izleme projesi.

## Amaç

MemWatch, özellikle 16 GB RAM'li Apple Silicon Mac'lerde sistemin ne zaman bellek baskısı yaşadığını ve SSD swap kullanımına geçtiğini anlaşılır şekilde göstermek için tasarlanır.

## Temel Özellikler

- Menü çubuğunda anlık RAM durumu
- Memory Pressure takibi
- Swap kullanım algılama
- Swap-in / Swap-out hareketlerini izleme
- Akıllı durum renkleri
- Kritik durumda macOS bildirimi
- Bellek tüketen uygulamaların snapshot analizi

## Tasarım İlkesi

Sadece "kaç GB swap var" bilgisini göstermek yerine macOS bellek davranışını yorumlamak hedeflenir.

Ölçümler:

- Physical RAM kullanımı
- Compressed Memory
- Wired Memory
- Cached Memory
- Memory Pressure
- Swap Used
- Swap değişim hızı

## Teknoloji Hedefi

- Platform: macOS
- Dil: Swift
- UI: SwiftUI + MenuBarExtra
- Veri kaynağı: macOS native memory APIs

## Durum

Proje başlangıç aşamasındadır.

## Lisans

TBD
