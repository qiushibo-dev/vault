#!/usr/bin/env bash
#
# 建置後打包成 dmg。
#
#   ./package.sh          → Vault_0.1.0.dmg
#
# 產物一樣放 ~/.cache（見 build.sh 的說明），最後才複製回專案。
set -euo pipefail

cd "$(dirname "$0")"

VERSION=$(grep -m1 'CFBundleShortVersionString' build.sh | sed 's/.*<string>\(.*\)<\/string>.*/\1/')
SCRATCH="$HOME/.cache/vault-build"
APP="$SCRATCH/Vault.app"
STAGE="$SCRATCH/dmg"
DMG="$SCRATCH/Vault_${VERSION}.dmg"

./build.sh --norun

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Vault" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

mkdir -p dist
cp "$DMG" "dist/"
echo "→ dist/Vault_${VERSION}.dmg"
