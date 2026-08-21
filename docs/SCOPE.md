# MemWatch Scope

## Vision

MemWatch, macOS kullanıcılarına RAM kullanımını değil, gerçek bellek baskısını ve sistem kaynak durumunu anlamlandırarak gösteren hafif bir menü çubuğu uygulamasıdır.

Amaç sadece değer göstermek değil; kullanıcının Mac'in neden yavaşladığını, neden ısındığını veya neden pil tükettiğini anlamasını sağlamaktır.

## Problem

macOS swap kullanımı, depolama ve enerji kullanımı tek başına yeterli şekilde görünmez. Kullanıcılar genellikle:

- RAM doldu mu?
- Mac SSD'yi RAM olarak kullanıyor mu?
- Yavaşlığın sebebi hangi uygulama?
- Dahili veya harici diskimde ne kadar alan kaldı?
- MacBook kaç watt enerji çekiyor?
- Harcanan enerji bataryadan mı geliyor yoksa bataryaya mı gidiyor?

sorularına hızlı cevap bulamaz.

## Target Users

- 16 GB RAM Mac kullanıcıları
- Local LLM çalıştıran kullanıcılar
- Geliştiriciler
- Ağır uygulamalar kullanan profesyoneller
- Harici SSD kullanan Mac kullanıcıları
- Pil tüketimini takip etmek isteyen MacBook kullanıcıları

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

### Energy Monitoring

MemWatch, AlDente benzeri bir enerji görünümü sunmayı hedefler.

Gösterilecek veriler:

- Anlık güç tüketimi (Watt)
- Ortalama güç tüketimi
- Gerçek zamanlı enerji grafiği
- Adaptörden gelen güç
- Sistemin kullandığı güç
- Bataryadan çekilen güç
- Bataryaya giden şarj gücü
- Şarj/deşarj durumu
- Tahmini pil tüketim hızı

Görsel deneyim:

- Hareketli enerji grafiği
- Enerji akış animasyonu
- Gücün sistem tarafından tüketimi veya bataryaya aktarımının görsel ayrımı

### Menu Bar

- Anlık durum göstergesi
- Renkli durum sistemi
- Detay paneli
- RAM, disk ve enerji özet görünümü

## Out of Scope (İlk Sürüm)

- RAM temizleme
- Otomatik uygulama kapatma
- Sistem optimizasyonu
- Kernel extension kullanımı
- Disk temizleme işlemleri
- Donanım kontrolü

## Technical Scope

- Swift
- SwiftUI
- macOS native APIs
- Düşük CPU/RAM tüketimi
- Apple Silicon öncelikli destek

## Success Criteria

- Arka planda fark edilmeyecek kadar hafif çalışması
- Swap başlangıcını doğru tespit etmesi
- Disk doluluk durumunu doğru göstermesi
- Enerji kullanımını anlaşılır şekilde görselleştirmesi
- Kullanıcıya teknik veri yerine anlamlı bilgi vermesi
