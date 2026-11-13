#!/bin/bash
# Сборка YCopyPaste.app
#   ./scripts/build-app.sh             — собрать для этого Mac
#   ./scripts/build-app.sh --install   — собрать и установить в /Applications
#   ./scripts/build-app.sh --universal — универсальная сборка (Apple Silicon + Intel, нужен Xcode)
set -eo pipefail

cd "$(dirname "$0")/.."
APP_NAME="YCopyPaste"
VERSION="$(cat VERSION 2>/dev/null || echo 1.0.0)"
BUILD_NUMBER="$(date +%Y%m%d%H%M)"
OUT_DIR="build"
APP="$OUT_DIR/$APP_NAME.app"

INSTALL=0
ARCH_FLAGS=""
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --universal) ARCH_FLAGS="--arch arm64 --arch x86_64" ;;
    *) echo "Неизвестный параметр: $arg"; exit 1 ;;
  esac
done

if ! command -v swift >/dev/null 2>&1; then
  echo "❌ Не найден Swift. Установите инструменты разработчика командой:"
  echo "   xcode-select --install"
  exit 1
fi

echo "▶︎ Компиляция ($APP_NAME $VERSION)…"
swift build -c release $ARCH_FLAGS
BIN_DIR="$(swift build -c release $ARCH_FLAGS --show-bin-path)"

echo "▶︎ Сборка пакета приложения…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Иконка: из PNG 1024×1024 делаем .icns системными утилитами.
if [ -f Resources/AppIcon.png ]; then
  ICONSET="$OUT_DIR/AppIcon.iconset"
  rm -rf "$ICONSET" && mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
fi

# Подпись. По умолчанию — локальная (ad-hoc). Если есть сертификат разработчика,
# укажите его: SIGN_IDENTITY="Developer ID Application: …" ./scripts/build-app.sh
echo "▶︎ Подпись…"
codesign --force --deep --sign "${SIGN_IDENTITY:--}" "$APP"

echo "✅ Готово: $APP"

if [ "$INSTALL" = "1" ]; then
  echo "▶︎ Установка в /Applications…"
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 0.5
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" "/Applications/$APP_NAME.app"
  open "/Applications/$APP_NAME.app"
  echo "✅ Установлено и запущено: /Applications/$APP_NAME.app"
fi
