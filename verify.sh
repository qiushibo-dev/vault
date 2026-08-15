#!/usr/bin/env bash
#
# 加密層的驗證。動過 Crypto.swift 或 KeyStore.swift 就跑一次。
#
#   ./verify.sh
#
# 這不是 SwiftPM 的測試 target。Vault 是 executable target，
# 把它拉進 XCTest 會撞到重複的 main symbol；而要驗的東西
# （派生金鑰、封裝、拆封）本來就跟畫面無關，直接編成一支 CLI 最省事。
#
# Tests/main.swift 裡自帶一個 VaultPaths 替身，指向暫存目錄，
# **不會碰到 ~/Library/Application Support/Vault 底下的真實資料。**
set -euo pipefail

cd "$(dirname "$0")"

OUT="$HOME/.cache/vault-build/verify"
mkdir -p "$(dirname "$OUT")"

swiftc -O -swift-version 6 \
    Sources/Vault/Crypto.swift \
    Sources/Vault/KeyStore.swift \
    Sources/Vault/Storage.swift \
    Sources/Vault/Model.swift \
    Sources/Vault/Strings.swift \
    Sources/Vault/Theme.swift \
    Tests/main.swift \
    -o "$OUT"

"$OUT"
