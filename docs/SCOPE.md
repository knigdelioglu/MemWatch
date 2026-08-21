# MemWatch Scope

## Vision

MemWatch, macOS kullanıcılarına RAM kullanımını değil, gerçek bellek baskısını anlamlandırarak gösteren hafif bir menü çubuğu uygulamasıdır.

## Problem

macOS swap kullanımı tek başına yeterli bir gösterge değildir. Kullanıcılar genellikle:

- RAM doldu mu?
- Mac SSD'yi RAM olarak kullanıyor mu?
- Yavaşlığın sebebi hangi uygulama?

sorularına hızlı cevap bulamaz.

## Target Users

- 16 GB RAM Mac kullanıcıları
- Local LLM çalıştıran kullanıcılar
- Geliştiriciler
- Ağır uygulamalar kullanan profesyoneller

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

### Menu Bar

- Anlık durum göstergesi
- Renkli durum sistemi
- Detay paneli

## Out of Scope (İlk Sürüm)

- RAM temizleme
- Otomatik uygulama kapatma
- Sistem optimizasyonu
- Kernel extension kullanımı

## Technical Scope

- Swift
- SwiftUI
- macOS native APIs
- Düşük CPU/RAM tüketimi

## Success Criteria

- Arka planda fark edilmeyecek kadar hafif çalışması
- Swap başlangıcını doğru tespit etmesi
- Kullanıcıya anlaşılır bilgi vermesi
