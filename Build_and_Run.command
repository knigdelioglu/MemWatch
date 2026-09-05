#!/bin/bash
set -euo pipefail

# Finder'dan çift tıklandığında doğru dizinde çalışmasını sağla
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

echo "=========================================="
echo " MemWatch: Build, Install & Run"
echo "=========================================="

TEMP_ROOT="${TMPDIR:-/private/tmp}"
DERIVED_DATA="$(mktemp -d "${TEMP_ROOT%/}/MemWatchBuild.XXXXXX")"
STAGING_DIR=""
BACKUP_APP=""
INSTALL_MOVED=false

cleanup() {
  if [[ -n "$STAGING_DIR" && -d "$STAGING_DIR" ]]; then
    if [[ -n "$BACKUP_APP" && ( -e "$BACKUP_APP" || -L "$BACKUP_APP" ) ]]; then
      echo "⚠️ Önceki uygulama kurtarma için burada bırakıldı: $BACKUP_APP" >&2
    else
      rm -rf "$STAGING_DIR"
    fi
  fi
  if [[ -n "$DERIVED_DATA" && -d "$DERIVED_DATA" ]]; then
    rm -rf "$DERIVED_DATA"
  fi
}
trap cleanup EXIT

restore_previous_app() {
  if [[ -n "$BACKUP_APP" && ( -e "$BACKUP_APP" || -L "$BACKUP_APP" ) ]]; then
    if [[ -e "$APP_TARGET" || -L "$APP_TARGET" ]]; then
      if ! rm -rf "$APP_TARGET"; then
        return 1
      fi
    fi
    mv "$BACKUP_APP" "$APP_TARGET"
  elif [[ "$INSTALL_MOVED" == true && ( -e "$APP_TARGET" || -L "$APP_TARGET" ) ]]; then
    rm -rf "$APP_TARGET"
  fi
}

echo "📦 1. Son sürüm derleniyor..."
bash "$ROOT_DIR/Scripts/package_release.sh" "$DERIVED_DATA" "$ROOT_DIR/dist" --app-only

APP_SOURCE="$DERIVED_DATA/Build/Products/Release/MemWatch.app"
APP_TARGET="${MEMWATCH_APP_TARGET:-/Applications/MemWatch.app}"
APP_PARENT="$(dirname "$APP_TARGET")"

if [[ ! -d "$APP_SOURCE" ]]; then
  echo "❌ Hata: Derlenen uygulama bulunamadı: $APP_SOURCE"
  exit 1
fi

if [[ ! -d "$APP_PARENT" ]]; then
  echo "❌ Hata: Uygulama hedef klasörü bulunamadı: $APP_PARENT"
  exit 1
fi

echo "🔐 2. Yeni uygulama staging alanında doğrulanıyor..."
STAGING_DIR="$(mktemp -d "$APP_PARENT/.MemWatch-install.XXXXXX")"
STAGED_APP="$STAGING_DIR/MemWatch.app"
ditto "$APP_SOURCE" "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"

echo "🛑 3. Çalışan eski MemWatch süreci varsa kapatılıyor..."
pkill -x MemWatch 2>/dev/null || true
sleep 0.5

echo "📂 4. Uygulama $APP_PARENT klasörüne yükleniyor..."
if [[ -e "$APP_TARGET" || -L "$APP_TARGET" ]]; then
  BACKUP_APP="$STAGING_DIR/Previous-MemWatch.app"
  mv "$APP_TARGET" "$BACKUP_APP"
fi

if ! mv "$STAGED_APP" "$APP_TARGET"; then
  if ! restore_previous_app; then
    echo "⚠️ Önceki uygulama otomatik olarak geri yüklenemedi: $BACKUP_APP" >&2
  fi
  echo "❌ Hata: Uygulama hedefe taşınamadı: $APP_TARGET" >&2
  exit 1
fi
INSTALL_MOVED=true

echo "🔐 5. Kurulu uygulama imzası doğrulanıyor..."
if ! codesign --verify --deep --strict "$APP_TARGET"; then
  if restore_previous_app; then
    echo "❌ Hata: Kurulu uygulamanın imzası doğrulanamadı; önceki sürüm geri yüklendi." >&2
  else
    echo "❌ Hata: Kurulu uygulamanın imzası doğrulanamadı ve önceki sürüm geri yüklenemedi: $BACKUP_APP" >&2
  fi
  exit 1
fi
if [[ ! -x "$APP_TARGET/Contents/MacOS/MemWatch" ]]; then
  if restore_previous_app; then
    echo "❌ Hata: Kurulu uygulama çalıştırılabilir dosyayı içermiyor; önceki sürüm geri yüklendi." >&2
  else
    echo "❌ Hata: Kurulu uygulama çalıştırılabilir dosyayı içermiyor ve önceki sürüm geri yüklenemedi: $BACKUP_APP" >&2
  fi
  exit 1
fi
BACKUP_APP=""

echo "🚀 6. MemWatch başlatılıyor..."
open "$APP_TARGET"

echo "=========================================="
echo "✅ MemWatch başarıyla güncellendi ve başlatıldı!"
echo "=========================================="
sleep 2
