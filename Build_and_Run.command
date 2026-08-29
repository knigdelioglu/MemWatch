#!/bin/bash
set -euo pipefail

# Finder'dan çift tıklandığında doğru dizinde çalışmasını sağla
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

echo "=========================================="
echo " MemWatch: Build, Install & Run"
echo "=========================================="

echo "📦 1. Son sürüm derleniyor ve paketleniyor..."
bash "$ROOT_DIR/Scripts/package_release.sh"

APP_SOURCE="$ROOT_DIR/build/DerivedData/Build/Products/Release/MemWatch.app"
APP_TARGET="/Applications/MemWatch.app"

if [[ ! -d "$APP_SOURCE" ]]; then
  echo "❌ Hata: Derlenen uygulama bulunamadı: $APP_SOURCE"
  exit 1
fi

echo "🛑 2. Çalışan eski MemWatch süreci varsa kapatılıyor..."
pkill -x MemWatch 2>/dev/null || true
sleep 0.5

echo "📂 3. Uygulama /Applications klasörüne yükleniyor..."
rm -rf "$APP_TARGET"
ditto "$APP_SOURCE" "$APP_TARGET"

echo "🔐 4. İmza doğrulanıyor..."
codesign --verify --deep --strict "$APP_TARGET"

echo "🚀 5. MemWatch başlatılıyor..."
open "$APP_TARGET"

echo "=========================================="
echo "✅ MemWatch başarıyla güncellendi ve başlatıldı!"
echo "=========================================="
sleep 2
