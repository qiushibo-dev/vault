import Foundation

enum Lang: String, CaseIterable, Identifiable {
    case zh, ja, en
    var id: String { rawValue }
    var label: String {
        switch self {
        case .zh: "繁體中文"
        case .ja: "日本語"
        case .en: "English"
        }
    }
    /// 設定裡那排藥丸上的短標
    var short: String {
        switch self {
        case .zh: "中"
        case .ja: "日"
        case .en: "EN"
        }
    }
}

/// 三語系的字串表。
///
/// 分頁的 PASSWORDS / DOCUMENTS / PHOTOS **刻意不翻譯**——那三個大寫字是版面的
/// 一部分，換成「密碼／文件／照片」會讓寬度和節奏整個垮掉。VAULT 同理。
struct L {
    // 鎖定
    let subtitle:      String
    let recoveryTitle: String
    let passwordPh:    String
    let touchID:       String
    let forgot:        String
    let hintTitle:     String
    let useKeyBelow:   String
    let backToPw:      String

    // 主畫面
    let lockNow:       String
    let detail:        String
    let newPassword:   String
    let newDocument:   String
    let fURL:          String
    let fNote:         String
    let fTags:         String
    let fAttach:       String
    let addFile:       String
    let phName:        String
    let phSecret:      String
    let phFileMeta:    String
    let exportOriginal: String
    let exportThumb:   String
    let thumbNote:     String
    let preview:       String
    let previewNote:   String

    // 設定
    let settings:      String
    let close:         String
    let gUnlock:       String
    let gForgot:       String
    let gData:         String
    let sTouchID:      String
    let sTouchIDSub:   String
    let sAutoLock:     String
    let sAutoLockSub:  String
    let sChangePw:     String
    let sChangePwSub:  String
    let changeBtn:     String
    let sHint:         String
    let sHintSub:      String
    let sKey:          String
    let sKeySub:       String
    let show:          String
    let hide:          String
    let copy:          String
    let copied:        String
    let print:         String
    let regenerate:    String
    let regenWarn:     String
    let sICloud:       String
    let sICloudSub:    String
    let sClipboard:    String
    let sClipboardSub: String
    let sLocation:     String
    let revealFinder:  String
    let sExport:       String
    let sExportSub:    String
    let exportBtn:     String
    let sLanguage:     String
    let sLanguageSub:  String
    let gTags:         String
    let tagAddPh:      String
    let tagUsedFmt:    String    // %d
    let tagUnused:     String
    let tagColourHint: String
    let tagDeleteWarnFmt: String // %@ 標籤名, %d 筆數
    let rename:        String
    let delete:        String
    let cancel:        String
    let checkUpdate:   String
    let checking:      String
    let isLatest:      String
    let newVersion:    String

    // 建立／變更密碼
    let createPw:      String   // 鎖定畫面上那顆按鈕
    let createPwTitle: String
    let createPwSub:   String
    let changePwTitle: String
    let currentPw:     String
    let newPw:         String
    let pwAgain:       String
    let pwMismatch:    String
    let pwTooShort:    String
    let pwWrong:       String
    let hintPh:        String
    let save:          String

    let off:           String
    let sec30:         String
    let min1:          String
    let min5:          String
    let min15:         String

    static func of(_ l: Lang) -> L {
        switch l {
        case .zh: zh
        case .ja: ja
        case .en: en
        }
    }

    // ── 繁體中文 ──────────────────────────────────────
    static let zh = L(
        subtitle: "這台機器上的保管箱",
        recoveryTitle: "用復原金鑰進入",
        passwordPh: "PASSWORD",
        touchID: "Touch ID",
        forgot: "忘記密碼？",
        hintTitle: "你設定的提示問題",
        useKeyBelow: "想不起來的話，用當初抄下來的復原金鑰",
        backToPw: "回去輸入密碼",

        lockNow: "鎖起來",
        detail: "detail",
        newPassword: "在這裡寫下一筆…",
        newDocument: "在這裡打字，或按右邊加入檔案…",
        fURL: "網址", fNote: "備註", fTags: "標籤", fAttach: "附件",
        addFile: "加入檔案",
        phName: "名稱", phSecret: "密碼", phFileMeta: "類型 · 大小",
        exportOriginal: "匯出原圖",
        exportThumb: "匯出縮圖",
        thumbNote: "縮圖是長邊 1024 的 JPEG，用來貼進表單或寄出去。",
        preview: "用系統播放器預覽",
        previewNote: "預覽會用 macOS 內建的播放器開啟原檔。影片不在這裡播——內建播放器要處理一堆編碼，不值得。",

        settings: "SETTINGS",
        close: "關閉",
        gUnlock: "解鎖",
        gForgot: "忘記密碼時",
        gData: "資料",
        sTouchID: "Touch ID",
        sTouchIDSub: "在這台機器上用指紋解鎖。金鑰存在 Secure Enclave，換電腦不會跟著走。",
        sAutoLock: "閒置自動上鎖",
        sAutoLockSub: "在 app 裡沒有任何操作超過這個時間就回到鎖定畫面。切到別的 app 也照樣計時——離開電腦正是最需要鎖上的時候。",
        sChangePw: "變更主密碼",
        sChangePwSub: "主密碼是唯一的根。變更會重新包裝金鑰，資料本身不用重新加密。",
        changeBtn: "變更…",
        sHint: "提示問題",
        sHintSub: "鎖定畫面按「忘記密碼」會看到這句。這裡要寫的是問題，不是答案——任何拿到這台電腦的人都讀得到。",
        sKey: "復原金鑰",
        sKeySub: "密碼真的想不起來時唯一的出路。抄下來收在 Vault 以外的地方——放在裡面等於沒有。",
        show: "顯示", hide: "隱藏", copy: "複製", copied: "已複製",
        print: "列印", regenerate: "重新產生",
        regenWarn: "重新產生會讓舊的那一組立刻失效。抄在紙上的那張要換掉。",
        sICloud: "金鑰同步到 iCloud 鑰匙圈",
        sICloudSub: "開啟後，新電腦登入同一個 Apple 帳號就能直接用 Touch ID 解鎖，不必輸入主密碼。代價是安全性等於你 Apple 帳號的安全性。",
        sClipboard: "複製後清除剪貼簿",
        sClipboardSub: "複製密碼後自動清空，免得留在剪貼簿歷史裡。",
        sLocation: "資料位置",
        revealFinder: "在 Finder 顯示",
        sExport: "匯出全部",
        sExportSub: "匯出成加密封存檔，需要主密碼才能還原。這是你的備份路徑。",
        exportBtn: "匯出…",
        sLanguage: "語言",
        sLanguageSub: "分頁上的 PASSWORDS／DOCUMENTS／PHOTOS 不會跟著翻譯，那三個字是版面的一部分。",
        gTags: "標籤",
        tagAddPh: "新增一個標籤…",
        tagUsedFmt: "用在 %d 筆",
        tagUnused: "還沒用過",
        tagColourHint: "點色塊換一支蠟筆。顏色只能從這盒裡挑，自由選色會讓整個畫面散掉。",
        tagDeleteWarnFmt: "刪除「%@」會從 %d 筆上一起移除，那些資料本身不會消失。",
        rename: "改名", delete: "刪除", cancel: "取消",
        checkUpdate: "檢查更新",
        checking: "查詢中…", isLatest: "已是最新", newVersion: "有新版本",

        createPw: "建立密碼",
        createPwTitle: "設定主密碼",
        createPwSub: "所有東西都從這個密碼長出來。它沒有存在任何地方，所以誰都查不到，你自己也一樣。",
        changePwTitle: "變更主密碼",
        currentPw: "目前的密碼",
        newPw: "新密碼",
        pwAgain: "再打一次",
        pwMismatch: "兩次不一樣",
        pwTooShort: "至少要 8 個字",
        pwWrong: "密碼不對",
        hintPh: "提示問題　例：母親的舊姓是什麼？",
        save: "儲存",

        off: "關閉", sec30: "30 秒", min1: "1 分鐘", min5: "5 分鐘", min15: "15 分鐘"
    )

    // ── 日本語 ────────────────────────────────────────
    static let ja = L(
        subtitle: "このマシンの中の金庫",
        recoveryTitle: "復旧キーで開ける",
        passwordPh: "PASSWORD",
        touchID: "Touch ID",
        forgot: "パスワードを忘れた",
        hintTitle: "自分で決めた質問",
        useKeyBelow: "思い出せないときは、控えておいた復旧キーを",
        backToPw: "パスワード入力に戻る",

        lockNow: "ロックする",
        detail: "detail",
        newPassword: "ここに書き足す…",
        newDocument: "ここに入力、または右のボタンでファイルを追加…",
        fURL: "URL", fNote: "メモ", fTags: "タグ", fAttach: "添付",
        addFile: "ファイルを追加",
        phName: "名前", phSecret: "パスワード", phFileMeta: "種類 · サイズ",
        exportOriginal: "元画像を書き出す",
        exportThumb: "縮小版を書き出す",
        thumbNote: "縮小版は長辺 1024 の JPEG です。フォームに貼るときや送るときに。",
        preview: "システムのプレイヤーで再生",
        previewNote: "macOS 標準のプレイヤーで元ファイルを開きます。アプリ内では再生しません。内蔵プレイヤーは対応コーデックの手当てが多すぎて割に合わないからです。",

        settings: "SETTINGS",
        close: "閉じる",
        gUnlock: "ロック解除",
        gForgot: "パスワードを忘れたとき",
        gData: "データ",
        sTouchID: "Touch ID",
        sTouchIDSub: "このマシンで指紋を使って解錠します。鍵は Secure Enclave にあり、機種を変えても移りません。",
        sAutoLock: "自動ロック",
        sAutoLockSub: "アプリ内で操作がないまま この時間が過ぎるとロック画面に戻ります。他のアプリに移っていても計測は続きます。席を離れたときこそロックが要るからです。",
        sChangePw: "マスターパスワードの変更",
        sChangePwSub: "マスターパスワードが唯一の根です。変更しても鍵を包み直すだけで、データ自体の再暗号化は起きません。",
        changeBtn: "変更…",
        sHint: "ヒントの質問",
        sHintSub: "ロック画面の「パスワードを忘れた」で表示されます。ここに書くのは質問であって、答えではありません。このマシンを手にした人は誰でも読めます。",
        sKey: "復旧キー",
        sKeySub: "パスワードをどうしても思い出せないときの唯一の出口。Vault の外に控えてください。中に入れたら意味がありません。",
        show: "表示", hide: "隠す", copy: "コピー", copied: "コピー済み",
        print: "印刷", regenerate: "再生成",
        regenWarn: "再生成すると古いキーは即座に無効になります。紙に控えた分も差し替えを。",
        sICloud: "鍵を iCloud キーチェーンに同期",
        sICloudSub: "有効にすると、同じ Apple アカウントでログインした新しいマシンでそのまま Touch ID が使えます。引き換えに、安全性は Apple アカウントの安全性と同じになります。",
        sClipboard: "コピー後にクリップボードを消去",
        sClipboardSub: "パスワードをコピーしたあと自動で空にします。履歴に残さないため。",
        sLocation: "データの場所",
        revealFinder: "Finder で表示",
        sExport: "全体を書き出す",
        sExportSub: "暗号化アーカイブとして書き出します。復元にはマスターパスワードが必要です。これがバックアップの経路になります。",
        exportBtn: "書き出す…",
        sLanguage: "言語",
        sLanguageSub: "タブの PASSWORDS／DOCUMENTS／PHOTOS は翻訳されません。あの三語はレイアウトの一部です。",
        gTags: "タグ",
        tagAddPh: "タグを追加…",
        tagUsedFmt: "%d 件で使用",
        tagUnused: "未使用",
        tagColourHint: "色をタップすると別のクレヨンに変わります。この箱の中からしか選べません。自由に選べると画面が散らかるからです。",
        tagDeleteWarnFmt: "「%@」を削除すると %d 件から外れます。データそのものは消えません。",
        rename: "名前を変更", delete: "削除", cancel: "キャンセル",
        checkUpdate: "更新を確認",
        checking: "確認中…", isLatest: "最新です", newVersion: "新しい版があります",

        createPw: "パスワードを作る",
        createPwTitle: "マスターパスワードを決める",
        createPwSub: "すべてがこのパスワードから伸びていきます。どこにも保存されないので、誰にも調べられません。あなた自身にも。",
        changePwTitle: "マスターパスワードの変更",
        currentPw: "現在のパスワード",
        newPw: "新しいパスワード",
        pwAgain: "もう一度",
        pwMismatch: "一致しません",
        pwTooShort: "8 文字以上にしてください",
        pwWrong: "パスワードが違います",
        hintPh: "ヒントの質問　例：母の旧姓は？",
        save: "保存",

        off: "オフ", sec30: "30 秒", min1: "1 分", min5: "5 分", min15: "15 分"
    )

    // ── English ───────────────────────────────────────
    static let en = L(
        subtitle: "A vault that lives on this machine",
        recoveryTitle: "Get in with a recovery key",
        passwordPh: "PASSWORD",
        touchID: "Touch ID",
        forgot: "Forgot your password?",
        hintTitle: "The question you set",
        useKeyBelow: "If it still won't come back, use the recovery key you wrote down",
        backToPw: "Back to password",

        lockNow: "Lock it",
        detail: "detail",
        newPassword: "Write the next one here…",
        newDocument: "Type here, or add a file on the right…",
        fURL: "URL", fNote: "Note", fTags: "Tags", fAttach: "Attached",
        addFile: "Add a file",
        phName: "Name", phSecret: "Password", phFileMeta: "Type · size",
        exportOriginal: "Export original",
        exportThumb: "Export smaller copy",
        thumbNote: "The smaller copy is a JPEG with a 1024px long edge, for pasting into forms or sending on.",
        preview: "Open in the system player",
        previewNote: "Opens the original in the built-in macOS player. Video does not play in here: a built-in player means handling a long tail of codecs, and it is not worth it.",

        settings: "SETTINGS",
        close: "Close",
        gUnlock: "Unlocking",
        gForgot: "When you forget",
        gData: "Data",
        sTouchID: "Touch ID",
        sTouchIDSub: "Unlock with your fingerprint on this machine. The key lives in the Secure Enclave and does not travel to a new computer.",
        sAutoLock: "Lock when idle",
        sAutoLockSub: "Go back to the lock screen after this long with no activity in the app. The count keeps running while you are in another app, because walking away is exactly when you want it locked.",
        sChangePw: "Change master password",
        sChangePwSub: "The master password is the only root. Changing it rewraps the key, so nothing has to be re-encrypted.",
        changeBtn: "Change…",
        sHint: "Hint question",
        sHintSub: "Shown when you press Forgot on the lock screen. What goes here is the question, not the answer. Anyone holding this machine can read it.",
        sKey: "Recovery key",
        sKeySub: "The only way back if the password is truly gone. Write it down and keep it somewhere outside the Vault. Inside is the same as nowhere.",
        show: "Show", hide: "Hide", copy: "Copy", copied: "Copied",
        print: "Print", regenerate: "Generate new",
        regenWarn: "Generating a new one kills the old key immediately. Replace the copy you wrote down.",
        sICloud: "Sync key to iCloud Keychain",
        sICloudSub: "With this on, a new computer signed into the same Apple account can use Touch ID straight away, no master password needed. The trade is that your Vault is only as safe as your Apple account.",
        sClipboard: "Clear clipboard after copying",
        sClipboardSub: "Empties it automatically so passwords don't sit in clipboard history.",
        sLocation: "Where the data lives",
        revealFinder: "Reveal in Finder",
        sExport: "Export everything",
        sExportSub: "Writes an encrypted archive that needs the master password to restore. This is your backup path.",
        exportBtn: "Export…",
        sLanguage: "Language",
        sLanguageSub: "The PASSWORDS / DOCUMENTS / PHOTOS tabs stay in English. Those three words are part of the layout.",
        gTags: "Tags",
        tagAddPh: "Add a tag…",
        tagUsedFmt: "on %d items",
        tagUnused: "not used yet",
        tagColourHint: "Tap a swatch to pick a different crayon. You can only choose from this box, because free colour choice would scatter the whole page.",
        tagDeleteWarnFmt: "Deleting \"%@\" takes it off %d items. The items themselves stay.",
        rename: "Rename", delete: "Delete", cancel: "Cancel",
        checkUpdate: "Check for updates",
        checking: "Checking…", isLatest: "Up to date", newVersion: "New version",

        createPw: "Create a password",
        createPwTitle: "Set a master password",
        createPwSub: "Everything grows out of this password. It is not stored anywhere, so nobody can look it up. That includes you.",
        changePwTitle: "Change master password",
        currentPw: "Current password",
        newPw: "New password",
        pwAgain: "Type it again",
        pwMismatch: "These don't match",
        pwTooShort: "At least 8 characters",
        pwWrong: "That isn't the password",
        hintPh: "Hint question   e.g. what is my mother's maiden name?",
        save: "Save",

        off: "Off", sec30: "30 seconds", min1: "1 minute", min5: "5 minutes", min15: "15 minutes"
    )
}
