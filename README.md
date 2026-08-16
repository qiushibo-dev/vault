# Vault

本機加密的保管箱，放密碼、文件、照片、影片。macOS，SwiftUI。

沒有帳號、沒有登入、不連任何伺服器。資料只在這台機器上。

## 執行

```bash
./build.sh          # 編譯 → 組 .app → 開起來
./build.sh --norun  # 只編譯打包
./package.sh        # 產 dmg 到 dist/
```

不需要完整的 Xcode，command line tools 就夠。

## 畫面

**建立密碼 → 進入 → 放資料 → 鎖起來**，之後每次開啟輸入密碼或按 Touch ID。

四個分頁共用一份資料結構，差別只在 `kind`：

| 分頁 | 呈現 | 新增方式 |
|---|---|---|
| PASSWORDS | 橫線紙，一行一筆 | 在空白行打字 |
| DOCUMENTS | 同上 | 打字，或按「＋ 加入檔案」 |
| PHOTOS | 格狀縮圖 | 虛線框開 Finder |
| VIDEO | 格狀，底片 icon | 同上 |

照片和影片**雙擊**打開檢視窗：照片可以匯出原圖或長邊 1024 的縮圖，影片可以匯出原檔或用系統播放器開啟。

分頁的四個字刻意不翻譯，那是版面的一部分。介面其他地方有中／日／英，在設定裡切換。

底部有一個搜尋欄（⌘F），過濾當前分頁。比對的是**項目摘要／使用者名稱／網址／備註／標籤**——
**密碼本身不參與比對**，讓它參與就等於開了一個猜測管道：輸入幾個字元、看清單剩幾筆，
就能一格一格試出內容，畫面上什麼都不用顯示。

## 設計

視覺來自 `DESIGN.md`（refero 抓的一份 style reference，兒童繪本風）。核心規則：

- **桃色畫布 `#f6e0db`**，白卡 ＋ 2px 純黑框，圓角 47（藥丸）／40（卡片）／10（小元件）
- **完全不用陰影**。層次靠框線和色塊，不靠 elevation
- **不用灰色**做線或字。所有結構線都是純黑，這是「紙上的墨」這個比喻的前提
- 顏色是一盒蠟筆：每個元件挑一支，不在同一個元件裡混兩支
- 標題 Alfa Slab One（不小於 16px），其他 Manrope，中日文靠 CoreText cascade 接到 Noto

畫布上的線稿塗鴉在 `Theme.swift` 的 `Doodle`，全部是手寫路徑，沒有外部素材。

`Metric.win` 是 760×880 的固定視窗，不可縮放——這個設計的節奏靠固定尺寸撐著。

## 加密（v0.2.0）

### 一把主金鑰，三把鑰匙包它

資料永遠用**主金鑰**加密。主金鑰是 32 bytes 純亂數，跟密碼沒有數學關係，
它本身不明文存在任何地方，而是被三個東西各包裝一份：

| 包裝者 | 角色 | 存在哪 |
|---|---|---|
| 密碼 | 根 | PBKDF2 派生後包一份，寫進 `keys.json` |
| Touch ID | 日常捷徑 | 主金鑰整把交給 Keychain，標記 `.biometryCurrentSet` |
| 復原金鑰 | 忘記密碼時 | 派生後包一份，寫進 `keys.json` |

隔這一層的理由：**改密碼不必把所有資料重新加密一遍**，只要重新包裝主金鑰；
而且一份密文只能有一把鑰匙，要同時支援密碼和復原金鑰兩種入口就非得這樣不可。

### 沒有「比對密碼」這個步驟

密碼錯誤的表現是 **AES-GCM 拆封失敗**，不是某個比對回傳 false。
程式裡不存在一份「儲存起來的密碼」可以被偷，也沒有一個判斷式可以被繞過。

Touch ID 同理：舊版是問系統「這個人通過了沒」，拿到布林值自己決定放不放行；
現在是驗證沒過**金鑰根本不會出現**，要繞的對象不是這個 app，是 Secure Enclave。

### 硬碟上長這樣

```
~/Library/Application Support/Vault/     （0700）
  keys.json          被包裝的主金鑰 ×2、salt、KDF 參數、提示問題
  vault.dat          全部項目＋標籤＋設定，AES-256-GCM
  blobs/<id>         每個附件一個檔，各自加密
  blobs/<id>.thumb   加密縮圖（格狀畫面用，不去解原圖）
```

- **提示問題是明文**，因為鎖定畫面要在解開任何東西之前顯示它
- **設定也在密文裡**，不放 UserDefaults——「閒置多久上鎖」本身就是安全設定，
  放在明文 plist 等於讓人從外面改掉
- 附件存的是**編號不是路徑**。原檔搬走刪掉都不影響
- 影片播放會解密成暫存檔放 `~/Library/Caches/Vault`，上鎖時清空。
  這是**唯一會讓明文落地的地方**

### 參數

PBKDF2-HMAC-SHA256，600,000 次迭代（OWASP 2023 建議值），一次派生約 135 ms。
`Crypto.iterations` **寫死不能改**——改了既有的 vault 就派生不出同一把金鑰。

### 驗證

```bash
./verify.sh
```

58 項，跑真的加解密：派生的決定性、密文竄改與截斷、錯誤金鑰、換密碼後舊密碼失效、
復原金鑰重產後舊的作廢、存檔 round-trip（含日文與 emoji）、附件與縮圖、暫存檔清除。
指向暫存目錄，不會碰到真實資料。

### 還沒做的

- **iCloud 同步**。設定裡標「尚未支援」，開關已經拿掉——能撥動的開關等於承諾它有作用
- **密碼和復原金鑰都遺失就是救不回來**。`Store.destroyVault()` 存在但沒接進 UI

### Touch ID 在自簽版本上是做不到的

程式碼寫好了，但**這個版本啟用不了**。註冊金鑰時系統回
`errSecMissingEntitlement (-34018)`，所以鎖定畫面那顆按鈕永遠不會出現。

原因：帶 `.biometryCurrentSet` 的 Keychain 項目要求 app 有 Apple 簽發的憑證，
而 `build.sh` 用的是 ad-hoc 自簽（`codesign --sign -`）。
**試過補 `keychain-access-groups` entitlement，結果 app 直接無法啟動**
（`Launch failed`，POSIX 163）——宣告了需要 provisioning profile 背書的 entitlement
卻拿不出背書，系統寧可不讓它跑。那條路是死的，不是設定沒調對。

要啟用只有一條路：**Apple Developer Program（99 美元／年）→ Developer ID 憑證 → 正式簽名**。
順帶一提，那也是讓別人下載 dmg 不被 Gatekeeper 擋的同一條路（見下方「發布」）。

另外一件跟簽名無關的事：**MacBook 闔蓋接外接螢幕時 Touch ID 本來就用不了**，
感應器在筆電鍵盤上。系統這時回 `LAError.systemCancel (-4)`，
而不是比較好懂的 `biometryNotAvailable`。設定頁的 Touch ID 那一列會直接寫出當下的原因，
不會讓按鈕神秘消失。

診斷：`Biometrics.diagnose()` 會把 `canEvaluatePolicy`、`biometryType`、`enrolled`、
最後一次註冊的 OSStatus 寫進 `~/.cache/vault-build/diag.log`。
開關是 `~/.cache/vault-build/VAULT_DEBUG` 這個檔案存不存在。
**寫檔不寫 stderr 是有原因的**——從終端機直接跑 binary 的話 LocalAuthentication 會回
systemCancel，量到的不是正常啟動時的狀態；而用 `open` 啟動又看不到 stderr。

### 發布

現在的 dmg **別人下載會被 Gatekeeper 擋**（「無法驗證開發者」，要手動到系統設定放行）。
本機自己做的 dmg 不會被擋，因為 `com.apple.quarantine` 只有從網路下載才會被加上。

要讓一般人雙擊就能開，需要 Developer ID 憑證簽名 → 上傳 Apple 公證（notarization）
→ 把票據釘進 dmg，三步都做完才沒有警告。`build.sh` 和 `package.sh` 目前只做到 ad-hoc 簽名。

## 檔案

```
Sources/Vault/
  Crypto.swift       PBKDF2 派生、AES-GCM 封裝／拆封。不認識「密碼對不對」這個概念
  KeyStore.swift     主金鑰的產生、包裝、交付；keys.json 的讀寫
  Storage.swift      vault.dat 與附件的加解密讀寫、縮圖、暫存檔
  Biometrics.swift   Keychain ＋ Secure Enclave（金鑰的第三條入口）
  VaultApp.swift     進入點、鎖定與解鎖的切換、sheet 掛載、結束前存檔
  Store.swift        全部狀態（@Observable）、存檔排程
  Model.swift        Item / TagDef / Tab / Kind
  LockView.swift     鎖定畫面（建立密碼 / 輸入密碼 / 忘記密碼三態）
  PasswordSheet.swift 建立與變更密碼共用的表單
  RecoveryKeySheet.swift 復原金鑰唯一一次的顯示
  MainView.swift     四分頁、橫線紙、格狀、detail 抽屜
  PhotoViewer.swift  雙擊打開的照片／影片檢視
  Settings.swift     設定
  IdleLock.swift     閒置自動上鎖
  Theme.swift        配色、Pill / OutlineCard、線稿塗鴉
  Typography.swift   Alfa Slab One ＋ Manrope ＋ CJK cascade
  Strings.swift      三語字串表
Tests/
  main.swift         加密層的驗證，用 ./verify.sh 跑
                     （檔名必須是 main.swift，swiftc 的 top-level code 限制）
Resources/
  Fonts/             四支字體，Info.plist 的 ATSApplicationFontsPath 指這裡
  AppIcon.icns
  makeicon.swift     icon 產生器，改字或改色重跑就好
```

## 踩過的坑

- **`preferredColorScheme(.light)` 不能拿掉。** 這個設計是 light-only，
  不鎖住的話系統在深色模式時 SwiftUI 的預設文字色變白，白卡上整片消失
- **不規則形狀的按鈕要 `.contentShape(Rectangle())`。** Shape 只有實心處吃得到點擊，
  齒輪的齒縫和中心孔都是死區
- **`Store.binding` 不能把 index 包進 closure。** 刪掉一筆之後 index 立刻失效，
  SwiftUI 不保證此刻已重建畫面，舊 binding 會再讀一次然後陣列越界閃退
- **格狀裡的格子高度要一致。** 日文標題走 Noto、空標題走 Manrope，行高不同，
  `aspectRatio(.fit)` 的方框會在多出來的空間裡自己置中，看起來就是往下掉一截
- **建置產物放 `~/.cache`**，不放專案底下——桌面在 iCloud 管理範圍，
  生成的 `.app` 會被加上 `com.apple.FinderInfo` 導致 codesign 失敗
- **預設值不要塞進輸入欄位。** `passwordHint` 曾經給了預設字串，表單一開就被帶進去，
  看起來像 placeholder 但其實是真的內容
- **兩張 sheet 不能疊。** 復原金鑰是在「建立密碼」或「設定」裡產生的，那時畫面上
  已經有一張 sheet；直接設 `freshRecoveryKey` 的話第二張根本不出現，使用者會永遠
  錯過那串金鑰而且不知道自己錯過了。改成擱在 `pendingRecovery`，等前一張 `onDismiss` 放行
- **格狀畫面絕對不能解原圖。** 九宮格等於一次解九張全尺寸照片，而且 SwiftUI 每次
  重繪都會再解一遍。匯入時就存一份加密縮圖，記憶體再快取一層
- **`thumbCache` 要標 `@ObservationIgnored`。** 它在 SwiftUI 的 body 裡被寫入，
  被 @Observable 追蹤的話會「寫入→通知重繪→再寫入」當場無限迴圈
- **Codable 的欄位要用 `decodeIfPresent`。** 加一個新欄位會讓所有既有存檔解不開，
  而且因為外層是加密的，症狀會偽裝成「密碼錯誤」，極難查
- **swiftc 的 top-level code 只認 `main.swift`。** 測試檔叫 `verify.swift` 會得到
  「expressions are not allowed at the top level」
