# Vault — 開發筆記（v0.2.0 之後）

最後更新：2026-08-17　現行版本 **v0.3.5**

`README.md` 寫得很完整，**但停在 v0.2.0**，而且加密那節少了一條金鑰路徑。
這份補的是之後的事。動手之前兩份都要看：

| 檔案 | 還準嗎 |
|---|---|
| `README.md` | 架構、檔案清單、踩過的坑 **仍然準確**，只有「加密」那節要用下面第 1 節覆蓋 |
| `DESIGN.md` | 視覺 token，準確 |

---

## 0. 這是什麼

本機的密碼與文件保管箱，macOS app，SwiftUI 原生。四個分頁共用同一份資料結構
（密碼／文件／照片／影片），差別只在 `kind`。

**沒有雲端、沒有帳號、沒有伺服器。** 資料是本機的兩個檔案加一個附件資料夾。

視覺是兒童繪本風：桃色紙、2px 純黑框、全圓角藥丸、手繪線稿。
**不用陰影**——那套語言裡沒有陰影，要層次就用框和填色。

⚠️ **作者本人每天在用，裡面是他真實的密碼。**
截圖、示範、測試一律另外建一個乾淨的 vault 塞假資料，不要碰
`~/Library/Application Support/Vault/`。

---

## 1. 一把主金鑰，**四**把鑰匙包它（覆蓋 README 的表）

資料永遠用**主金鑰**加密。主金鑰是 32 bytes 純亂數，跟密碼沒有數學關係，
本身不明文存在任何地方，而是被四個東西各包裝一份：

| 包裝者 | 角色 | 存在哪 |
|---|---|---|
| 密碼 | 根 | PBKDF2 派生後包一份，寫進 `keys.json` |
| 復原金鑰 | 忘記密碼時 | 同上 |
| **提示問題的答案** | 第二個密碼 | 同上。**選填**，留空就只是提醒、不能解鎖 |
| Touch ID | 日常捷徑 | 主金鑰整把交給 Keychain，標記 `.biometryCurrentSet` |

隔這一層的理由：**改密碼不必把所有資料重新加密一遍**，只要重新包裝主金鑰。

### 每條路徑各自記自己的迭代次數

```swift
var passwordSalt: Data; var passwordWrapped: Data; var passwordIterations: UInt32
var recoverySalt: Data; var recoveryWrapped: Data; var recoveryIterations: UInt32
var answerSalt:   Data?; var answerWrapped:   Data?; var answerIterations:   UInt32
```

⚠️ **三條路共用一個 `iterations` 欄位是定時炸彈。** 改密碼時如果把它升級了，
用舊次數封裝的復原金鑰就再也派生不出同一把金鑰——**而且不會報錯，
只會表現成「金鑰是錯的」**。分開存就沒有這個問題。

`keys.json` 的 `init(from:)` 用 `decodeIfPresent` 搭一個 `legacy` 欄位當後備，
所以 v0.2.0 時代寫下的舊格式還開得起來。

### 沒有「比對密碼」這個步驟

密碼錯誤的表現是 **AES-GCM 拆封失敗**，不是某個比對回傳 false。
程式裡不存在一份可以被偷的密碼，也沒有一個可以被繞過的判斷式。

---

## 2. 最嚴重的一個 bug：`await` 中間的競態

**症狀（作者回報）**：「如果我重新申請金鑰，用新的金鑰會打不開」。

**成因**：`KeyStore` 的每個寫入都是 read-modify-write，而中間夾著一個
約 135 ms 的 `await`（PBKDF2 在背景執行緒跑）：

```swift
// 壞的
var f = load()                      // ← 讀
let key = try await derive(...)     // ← 這 135ms 內別人也讀了同一份
f.recoveryWrapped = ...
save(f)                             // ← 誰後寫誰贏，另一邊的變更消失
```

設定視窗那邊的提示問題寫回，剛好落在這個空檔。

**修法**：把 `load()` 移到**所有 `await` 之後**，並把 `KeyStore` 標成 `@MainActor`。

```swift
let key = try await deriveOffMain(...)
// ↓ 這行以後不准再有 await
guard var f = load() else { throw VaultError.notInitialised }
```

**這是要記住的一類 bug，不是單一事件**：只要一個函式是「讀 → 算 → 寫」而中間有
`await`，那個 await 就是一扇窗。這個 app 裡幾乎每個金鑰操作都長這樣。

---

## 3. 存檔：讀不到 ≠ 沒有

```swift
guard exists else { return VaultPayload() }          // 真的是新的保管箱
guard let blob = try? Data(contentsOf: VaultPaths.data) else {
    throw VaultError.ioFailed("資料檔存在但讀不到，請檢查檔案權限")
}
```

⚠️ 原本兩種情況都回一個空的 payload。**檔案在但讀不到的時候，
app 會表現得像個全新的保管箱，然後下一次存檔把空的寫在真資料上面。**
「檔案不存在」和「檔案讀不到」必須分開處理。

（同一類的坑在 Babos 也踩過一次，見那邊的 `BABOS.md` 第 6 節。）

---

## 4. 搜尋欄（v0.3.5）

底部齒輪與「鎖起來」中間，藥丸形狀。⌘F 跳進去、右邊 × 清空、**上鎖時清掉**。

比對**項目摘要／使用者名稱／網址／備註／標籤**。

🔴 **`value` 刻意不參與比對。不要「順手補上」。**

密碼分頁的 `value` 就是密碼本身。讓它參與搜尋等於開了一個猜測管道：
輸入幾個字元、看清單剩幾筆，就能一格一格試出內容，而畫面上什麼都不用顯示。
文件分頁的 `value` 只是「類型 · 大小」，一起排除比較單純。

**這條有兩項驗證守著**（`🔴 密碼本身不參與搜尋`、`🔴 密碼的開頭也不行`）。

比對規則放在 `Item.matches`，**不在 Store**——`verify.sh` 只編 Crypto / KeyStore /
Storage / Model / Strings / Theme，放 Store 裡就進不了驗證。
大小寫與前後空白在 `matches` 裡面就正規化掉，不要求呼叫端先做：
少呼叫一次的症狀是「打大寫字母搜不到東西」，那看起來像資料壞了。

---

## 5. 驗證

```bash
./verify.sh          # 103 項（README 寫 58，那是舊的）
```

跑真的加解密：派生的決定性、密文竄改與截斷、錯誤金鑰、換密碼後舊密碼失效、
復原金鑰重產後舊的作廢、**提示問題答案的四條路徑**、存檔 round-trip（含日文與
emoji）、附件與縮圖、暫存檔清除、**搜尋的比對規則**。

指向暫存目錄，**不會碰到真實資料**。

⚠️ 測試檔名必須是 `main.swift`（swiftc 的 top-level code 限制）。

---

## 6. Touch ID：這個版本啟用不了

程式碼寫好了，但自簽版本拿不到 `errSecMissingEntitlement` 需要的權限。
設定裡的開關**已經灰掉並顯示原因**——能撥動但沒作用的開關等於說謊。

這是作者的決定：**等要發 public 版時付 99 美元一起處理**。那時要一次做完
入會 → Developer ID 憑證 → 簽名＋公證 → Touch ID 改回完整的 Secure Enclave 路徑，
並拿掉設定裡那句說明。

**不要建議用「問系統這個人通過了沒」的布林值版本繞過。** 那是舊寫法，
繞的對象會變成這個 app 而不是 Secure Enclave。

---

## 7. v0.3.x 的介面改動

- **密碼分頁三欄**：項目摘要｜使用者名稱｜密碼。中間那欄只有密碼分頁顯示
- **刪除移進 detail 抽屜的右下角**，而且**一定要跳確認**。
  刪照片和影片會連加密過的附件一起清掉，不可逆
- **標籤改成點擊直接操作**，按 ＋ 出現藥丸形狀的輸入框；輸入時會跳出已建過的候選
- **照片預覽一律正方形**，雙擊才看真實尺寸

### 兩個非顯而易見的修法

**中文輸入法會讓 placeholder 疊在組字上。**
注音打到一半、還沒選字的時候，綁定的值仍然是空字串，所以只看 `value.isEmpty`
會以為使用者還沒開始打。要一起看焦點：

```swift
if value.isEmpty && !focused { /* 顯示提示字 */ }
```

**非正方形照片會爆出格子。**
直接 `Image.resizable().aspectRatio(.fill)` 的話，圖片會回報一個「填滿後」的尺寸
當作自己的大小，ZStack 跟著被撐大，外面的 `clipShape` 裁的是已經變大的範圍
（等於沒裁）。要用 `Color.clear` 把格子尺寸定下來，圖片以 overlay 疊上去、
溢出的部分由 `clipped()` 切掉。

---

## 8. 發版

```
改程式 → 改 build.sh 裡的版本號（CFBundleVersion 兩處）
→ ./verify.sh        # 103 項要全過
→ ./package.sh       # 產出 dist/Vault_X.Y.Z.dmg
→ git commit / tag / push
→ gh release create vX.Y.Z dist/Vault_X.Y.Z.dmg --repo qiushibo-dev/vault
```

- repo `qiushibo-dev/vault`（private）
- 建置產物在 `~/.cache/vault-build`，**不要放專案底下**（iCloud 會加
  `com.apple.FinderInfo`，codesign 直接拒絕）
- 未公證，裝完要 `xattr -dr com.apple.quarantine /Applications/Vault.app`
- ⚠️ **裝新版之前要先把開著的 Vault 完全結束（⌘Q）。**
  bundle id 相同時 `open` 只會把已經在跑的那個叫到前面，會以為新版沒生效

---

## 9. 還沒做的

- **iCloud 同步** — 設定裡標「尚未支援」，開關已經拿掉
- **密碼和復原金鑰都遺失就是救不回來** — `Store.destroyVault()` 存在但沒接進 UI
- **public 版** — 作者說可能下個月，見第 6 節
- **介紹網站與影片** — 說好各做一份，**視覺語言要跟 Babos 完全不同**
  （繪本風、桃色紙、2px 黑框 vs 深藍星雲），不能是同一個模板換色

---

## 10. 動手之前

1. 讀 `README.md` 的檔案清單與踩過的坑，那節還準
2. 加密相關的改動，**每一個 read-modify-write 都要檢查中間有沒有 `await`**
3. 改完跑 `./verify.sh`，103 項要全過
4. **不要為了方便把搜尋擴大到 `value`**（第 4 節）
5. 需要截圖或示範時另外建一個假資料的 vault
