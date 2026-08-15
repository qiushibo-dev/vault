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

## 設計

視覺來自 `DESIGN.md`（refero 抓的一份 style reference，兒童繪本風）。核心規則：

- **桃色畫布 `#f6e0db`**，白卡 ＋ 2px 純黑框，圓角 47（藥丸）／40（卡片）／10（小元件）
- **完全不用陰影**。層次靠框線和色塊，不靠 elevation
- **不用灰色**做線或字。所有結構線都是純黑，這是「紙上的墨」這個比喻的前提
- 顏色是一盒蠟筆：每個元件挑一支，不在同一個元件裡混兩支
- 標題 Alfa Slab One（不小於 16px），其他 Manrope，中日文靠 CoreText cascade 接到 Noto

畫布上的線稿塗鴉在 `Theme.swift` 的 `Doodle`，全部是手寫路徑，沒有外部素材。

`Metric.win` 是 760×880 的固定視窗，不可縮放——這個設計的節奏靠固定尺寸撐著。

## 目前的狀態（v0.1.0）

**這是可以用的骨架，但加密還沒接上去。** 明確的缺口：

1. **沒有存檔。** 資料全在記憶體，關掉 app 就沒了，包括密碼。
   這是刻意的：加密層沒好之前，不該把真的密碼寫進磁碟
2. **密碼是字串比對。** 正確的做法是拿主密碼派生金鑰、解得開才算對，
   「比對密碼」這個步驟根本不該存在
3. **Touch ID 只拿到一個是非題。** 正確的做法是把主金鑰放進 Keychain 並標記
   `.biometryCurrentSet`，由 Secure Enclave 決定要不要交出金鑰——驗證失敗時
   金鑰根本不會出現，而不是 app 自己判斷放不放行（見 `Biometrics.swift`）
4. **匯入檔案只記路徑。** 原檔在 Finder 被移走或刪掉，Vault 這邊就變空白。
   真正要做的是加密後複製進 vault 目錄
5. 復原金鑰、iCloud 同步、匯出、變更密碼在 UI 上都在，但底下還沒有東西

換句話說：**現在不要拿它放真的機密資料。**

## 檔案

```
Sources/Vault/
  VaultApp.swift     進入點、鎖定與解鎖的切換、sheet 掛載
  Store.swift        全部狀態（@Observable）
  Model.swift        Item / Tab / Kind
  LockView.swift     鎖定畫面（建立密碼 / 輸入密碼 / 忘記密碼三態）
  PasswordSheet.swift 建立與變更密碼共用的表單
  MainView.swift     四分頁、橫線紙、格狀、detail 抽屜
  PhotoViewer.swift  雙擊打開的照片／影片檢視
  Settings.swift     設定
  Biometrics.swift   Touch ID
  IdleLock.swift     閒置自動上鎖
  Theme.swift        配色、Pill / OutlineCard、線稿塗鴉
  Typography.swift   Alfa Slab One ＋ Manrope ＋ CJK cascade
  Strings.swift      三語字串表
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
