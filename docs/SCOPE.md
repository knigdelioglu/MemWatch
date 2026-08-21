# MemWatch Scope

## Vision

MemWatch, macOS kullanıcılarına RAM kullanımını değil, gerçek bellek baskısını ve sistem kaynak durumunu anlamlandırarak gösteren hafif bir menü çubuğu uygulamasıdır.

## Problem

macOS swap kullanımı tek başına yeterli bir gösterge değildir. Kullanıcılar genellikle:

- RAM doldu mu?
- Mac SSD'yi RAM olarak kullanıyor mu?
- Yavaşlığın sebebi hangi uygulama?
- Dahili veya harici diskimde ne kadar alan kaldı?

sorularına hızlı cevap bulamaz.

## Target Users

- 16 GB RAM Mac kullanıcıları
- Local LLM çalıştıran kullanıcılar
- Geliştiriciler
- Ağır uygulamalar kullanan profesyoneller
- Harici SSD kullanan Mac kullanıcıları

## MVP Scope

### Memory Monitoring

- RAM kullanım yüzdesi
- Kullanılabilir RAM
- Compressed memory
- Memory pressure
- Swap used

### Smart Detection

Uygulama sadece swap miktarına göre alarm vermeyecek.

Değerlendirme:

- Memory pressure
- Swap hareketi
- Compression artışı
- Süreklilik

birlikte ele alınacak.

### Storage Monitoring

Uygulama sistemdeki depolama alanlarını gösterecek:

- Dahili disk kapasitesi
- Dahili disk doluluk oranı
- Boş alan miktarı
- Bağlı harici diskler
- Harici disk kapasitesi ve doluluk oranı
- Düşük disk alanı uyarıları

Amaç sadece disk kapasitesini göstermek değil, RAM/swap problemi ile disk alanı problemini birbirinden ayırmaktır.

### Menu Bar

- Anlık durum göstergesi
- Renkli durum sistemi
- Detay paneli
- RAM ve disk özet görünümü

## Out of Scope (İlk Sürüm)

- RAM temizleme
- Otomatik uygulama kapatma
- Sistem optimizasyonu
- Kernel extension kullanımı
- Disk temizleme işlemleri

## Technical Scope

- Swift
- SwiftUI
- macOS native APIs
- Düşük CPU/RAM tüketimi

## Success Criteria

- Arka planda fark edilmeyecek kadar hafif çalışması
- Swap başlangıcını doğru tespit etmesi
- Disk doluluk durumunu doğru göstermesi
- Kullanıcıya anlaşılır bilgi vermesi
