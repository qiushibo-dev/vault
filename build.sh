#!/usr/bin/env bash
#
# 編譯並組成 Vault.app，然後開起來。
#
#   ./build.sh          編譯 → 打包 → 執行
#   ./build.sh --norun  只編譯打包
#
# 建置產物刻意放在 ~/.cache 底下。這個專案在 ~/Desktop，而 Desktop 在
# iCloud 的 File Provider 管理下——生成物留在那裡的話，剛做好的 .app 會被
# 同步機制加上 com.apple.FinderInfo，codesign 直接拒絕簽章。
set -euo pipefail

cd "$(dirname "$0")"

SCRATCH="$HOME/.cache/vault-build"
APP="$SCRATCH/Vault.app"

swift build -c release --scratch-path "$SCRATCH"

BIN="$SCRATCH/release/Vault"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts"
cp "$BIN" "$APP/Contents/MacOS/Vault"

# 同梱フォント。Info.plist の ATSApplicationFontsPath がこのフォルダを指すので、
# 起動時に macOS が登録してくれる。
cp Resources/Fonts/*.ttf "$APP/Contents/Resources/Fonts/"

# アイコン。Resources/makeicon.swift で作り直せる：
#   swiftc -O Resources/makeicon.swift -o /tmp/makeicon
#   /tmp/makeicon Resources/Fonts/AlfaSlabOne-Regular.ttf Resources/icon1024.png
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>              <string>Vault</string>
  <key>CFBundleDisplayName</key>       <string>Vault</string>
  <key>CFBundleExecutable</key>        <string>Vault</string>
  <key>CFBundleIdentifier</key>        <string>com.shihbo.vault</string>
  <key>CFBundleVersion</key>           <string>0.3.6</string>
  <key>CFBundleShortVersionString</key><string>0.3.6</string>
  <key>CFBundlePackageType</key>       <string>APPL</string>
  <key>NSHighResolutionCapable</key>   <true/>
  <key>LSMinimumSystemVersion</key>    <string>14.0</string>
  <key>ATSApplicationFontsPath</key>   <string>Fonts</string>
  <key>CFBundleIconFile</key>          <string>AppIcon</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" 2>/dev/null || true

echo "→ $APP"

if [ "${1:-}" != "--norun" ]; then
  pkill -f "Vault.app/Contents/MacOS/Vault" 2>/dev/null || true
  sleep 0.5
  open "$APP"
fi
