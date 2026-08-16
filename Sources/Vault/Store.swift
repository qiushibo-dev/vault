import SwiftUI
import AppKit

@MainActor
@Observable
final class Store {
    var locked = true
    var tab: Tab = .passwords
    var items: [Item] = []
    /// 目前展開 detail 抽屜的那一筆
    var expanded: String? = nil
    /// 設定視窗
    var showSettings = false

    /// 底部的搜尋欄。空字串＝不過濾。
    /// **不進存檔，上鎖時一併清掉**——留著的話下次解鎖會對著一個過濾過的清單，
    /// 而那個過濾條件是上一次的，人不會記得。
    var query = ""

    // ── 金鑰 ──────────────────────────────────────────
    /// 解鎖後的主金鑰。**只活在記憶體裡，上鎖就抹掉。**
    ///
    /// 舊版這裡放的是 `password: String?`——使用者的密碼原封不動存著，
    /// 誰讀到這個物件就等於拿到密碼。現在這裡是一把跟密碼無關的隨機金鑰，
    /// 而且 app 一關就沒了，硬碟上永遠只有被包裝過的版本。
    private(set) var masterKey: Data? = nil

    /// 這台機器上建立過保管箱沒有。看的是金鑰檔在不在，不是記憶體裡的狀態。
    var hasPassword: Bool { KeyStore.exists }

    /// 建立／變更密碼的表單
    var pwSheet: PasswordSheetMode? = nil
    /// 雙擊照片打開的檢視窗
    var photoViewer: Item? = nil
    /// 檢查更新的結果
    var updateState: UpdateState = .idle
    /// 解鎖或存檔出錯時給畫面顯示的訊息
    var lastError: String? = nil

    /// 忙碌中（派生金鑰要跑幾百毫秒，按鈕要能反映出來）
    var working = false

    /// 剛產生、還沒給使用者看過的復原金鑰。顯示完就丟掉，**不進存檔**。
    var freshRecoveryKey: RecoveryKey? = nil

    /// 等前一張 sheet 關掉才能顯示的金鑰。
    ///
    /// **兩張 sheet 不能疊。** 產生金鑰的動作發生在「建立密碼」表單或「設定」裡，
    /// 那時候畫面上已經有一張 sheet；直接設 `freshRecoveryKey` 的話第二張根本不會出現，
    /// 而使用者永遠看不到那串金鑰——他甚至不會知道自己錯過了什麼。
    /// 所以先擱著，等前一張 `onDismiss` 再放行。
    @ObservationIgnored private var pendingRecovery: RecoveryKey? = nil

    func flushPendingRecovery() {
        guard let p = pendingRecovery else { return }
        pendingRecovery = nil
        freshRecoveryKey = p
    }

    // ── 建立 ──────────────────────────────────────────
    /// 第一次建立保管箱。
    @discardableResult
    func createVault(password: String, hint: String) async -> Bool {
        working = true
        defer { working = false }
        do {
            let (master, recovery) = try await KeyStore.create(password: password, hint: hint)
            masterKey = master
            items = []
            tagList = []
            try Storage.save(payload, key: master)
            if touchIDOn && Biometrics.available { Biometrics.enrol(master: master) }
            locked = false
            pendingRecovery = RecoveryKey(value: recovery)
            return true
        } catch {
            lastError = (error as? VaultError)?.message ?? "建立失敗"
            return false
        }
    }

    // ── 解鎖 ──────────────────────────────────────────
    /// 密碼解鎖。成功與否完全取決於**解不解得開**，這裡沒有任何字串比對。
    func unlock(password: String) async -> Bool {
        working = true
        defer { working = false }
        do {
            let master = try await KeyStore.unlock(password: password)
            try adopt(master)
            // 密碼走通了就順手把 Keychain 補回去，使用者不必自己去設定裡重開 Touch ID。
            //
            // **在自簽版本上這一步一定會失敗**（errSecMissingEntitlement），
            // 那是預期的——生物辨識保護的 Keychain 項目要 Apple 簽發的憑證。
            // 失敗不影響登入，`Biometrics.lastEnrolStatus` 會留下代碼給設定頁顯示原因。
            if touchIDOn && Biometrics.available && !Biometrics.enrolled {
                Biometrics.enrol(master: master)
                Biometrics.diagnose("密碼登入後補註冊")
            }
            return true
        } catch {
            lastError = (error as? VaultError)?.message ?? "解鎖失敗"
            return false
        }
    }

    /// 復原金鑰解鎖
    func unlock(recovery: String) async -> Bool {
        working = true
        defer { working = false }
        do {
            try adopt(try await KeyStore.unlock(recovery: recovery))
            return true
        } catch {
            lastError = (error as? VaultError)?.message ?? "復原金鑰不正確"
            return false
        }
    }

    /// 用提示問題的答案解鎖。第三把鑰匙，跟密碼、復原金鑰平行。
    func unlock(answer: String) async -> Bool {
        working = true
        defer { working = false }
        do {
            try adopt(try await KeyStore.unlock(answer: answer))
            return true
        } catch {
            lastError = (error as? VaultError)?.message ?? "答案不正確"
            return false
        }
    }

    var hasAnswer: Bool { KeyStore.hasAnswer }

    /// 答案的明文，存在加密過的 `vault.dat` 裡，純粹是讓使用者回頭確認有沒有打錯字。
    /// **驗證從來不看它**——那是 `KeyStore` 用包裝過的主金鑰在做的。
    var answerPlain = ""

    /// 設定或更改答案。**需要主金鑰**，所以只能在已經解鎖的狀態下做。
    @discardableResult
    func setAnswer(_ answer: String) async -> Bool {
        guard let m = masterKey else { return false }
        working = true
        defer { working = false }
        do {
            try await KeyStore.setAnswer(master: m, answer: answer)
            answerPlain = answer
            saveNow()
            return true
        } catch {
            lastError = "答案設定失敗"
            return false
        }
    }

    func clearAnswer() {
        KeyStore.clearAnswer()
        answerPlain = ""
        saveNow()
    }

    /// Touch ID 解鎖。金鑰是 Secure Enclave 交出來的，不是這裡判斷來的。
    func unlockBiometric() async -> Bool {
        guard let master = await Biometrics.fetchMaster(reason: "解鎖保管箱") else { return false }
        do {
            try adopt(master)
            return true
        } catch {
            // 金鑰拿到了卻解不開資料，代表 Keychain 裡那把是舊的（改過密碼之類）
            Biometrics.forget()
            lastError = "請改用密碼登入一次"
            return false
        }
    }

    /// 拿到主金鑰之後的共同流程：載入資料、進去。
    private func adopt(_ master: Data) throws {
        let loaded = try Storage.load(key: master)
        masterKey = master
        items = loaded.items
        tagList = loaded.tags
        answerPlain = loaded.answerPlain
        apply(loaded.prefs)
        lastError = nil
        locked = false
    }

    // ── 變更密碼 ──────────────────────────────────────
    func changePassword(current: String, new: String) async -> Bool {
        working = true
        defer { working = false }
        do {
            try await KeyStore.changePassword(current: current, new: new)
            // 主金鑰沒變，所以資料不用動；但 Keychain 那份要重寫，
            // 讓「舊密碼時期註冊的指紋」不會繼續有效
            if let m = masterKey, touchIDOn, Biometrics.available {
                Biometrics.enrol(master: m)
            }
            return true
        } catch {
            lastError = (error as? VaultError)?.message ?? "變更失敗"
            return false
        }
    }

    /// 重新產生復原金鑰。**舊的當場失效**——包裝主金鑰的那一份被覆蓋掉，
    /// 拿舊金鑰派生出來的鑰匙再也拆不開任何東西。
    ///
    /// 直接把金鑰回傳給設定頁**就地顯示**，不再走「關設定 → 開另一張 sheet」。
    /// 那條路要等兩段動畫接力（各約 0.35 秒），按下去要愣將近一秒才有反應，
    /// 而真正在算的只有 135 毫秒。
    func regenerateRecoveryKey() async -> String? {
        guard let m = masterKey else { return nil }
        working = true
        defer { working = false }
        guard let k = try? await KeyStore.regenerateRecovery(master: m) else {
            lastError = "產生失敗"
            return nil
        }
        return k
    }

    // ── 救援 ──────────────────────────────────────────
    /// 忘記密碼時給自己看的提示。存在金鑰檔裡，鎖定畫面看得到，
    /// 所以**不能寫成密碼本身**——寫「母親的舊姓」可以，寫「Kaoru1987」不行。
    var passwordHint: String {
        get { KeyStore.hint }
        set { KeyStore.updateHint(newValue) }
    }

    // ── 設定 ──────────────────────────────────────────
    var touchIDOn = true
    /// iCloud 同步。**還沒實作**，設定頁那個開關現在是唯讀的說明文字。
    var icloudSync = false
    /// 閒置多久自動上鎖。秒，0 表示關閉。
    var autoLockSeconds = 30
    var clipboardSeconds = 30

    // ── 語言 ──────────────────────────────────────────
    var lang: Lang = .zh
    var t: L { L.of(lang) }

    var autoLockChoices: [(Int, String)] {
        [(0, t.off), (30, t.sec30), (60, t.min1), (300, t.min5), (900, t.min15)]
    }
    var autoLockLabel: String {
        autoLockChoices.first { $0.0 == autoLockSeconds }?.1 ?? "\(autoLockSeconds)s"
    }

    var version: String {
        // 讀不到就老實顯示問號。給一個假的版本號會讓人以為自己裝的是那一版
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
    var dataPath: String { VaultPaths.dir.path }

    // ── 存檔 ──────────────────────────────────────────
    private var saveTask: Task<Void, Never>?

    private var payload: VaultPayload {
        VaultPayload(items: items, tags: tagList,
                     prefs: Prefs(touchIDOn: touchIDOn, icloudSync: icloudSync,
                                  autoLockSeconds: autoLockSeconds,
                                  clipboardSeconds: clipboardSeconds, lang: lang),
                     answerPlain: answerPlain)
    }

    private func apply(_ p: Prefs) {
        touchIDOn = p.touchIDOn
        icloudSync = p.icloudSync
        autoLockSeconds = p.autoLockSeconds
        clipboardSeconds = p.clipboardSeconds
        lang = p.lang
    }

    /// 打字時每個字元都寫一次檔太浪費，延遲一下再寫。
    /// **但延遲期間關掉 app 就會掉資料**，所以上鎖和結束時一定要走 `saveNow()`。
    func scheduleSave() {
        guard masterKey != nil else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    @discardableResult
    func saveNow() -> Bool {
        guard let key = masterKey else { return false }
        saveTask?.cancel()
        do {
            try Storage.save(payload, key: key)
            return true
        } catch {
            lastError = "存檔失敗：\(error.localizedDescription)"
            return false
        }
    }

    // ── 篩選 ──────────────────────────────────────────
    func rows(for tab: Tab) -> [Item] {
        let k = Item.kind(for: tab)
        let all = items.filter { $0.kind == k }
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return all }
        // 比對規則在 `Item.matches`，那裡才進得了 ./verify.sh。
        return all.filter { $0.matches(query) }
    }

    // ── 編輯 ──────────────────────────────────────────
    /// **不能把 index 包進 closure。**
    /// 刪掉一筆之後 index 立刻失效，而 SwiftUI 不保證此刻已經重建畫面——
    /// 舊的 binding 還會被讀一次，然後陣列越界當場閃退。每次都用 id 重找。
    func binding(_ id: String) -> Binding<Item>? {
        guard items.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.items.first { $0.id == id } ?? Item(kind: .password) },
            set: { new in
                guard let i = self.items.firstIndex(where: { $0.id == id }) else { return }
                self.items[i] = new
                self.items[i].updated = .now
                self.scheduleSave()
            }
        )
    }

    /// 在空白行打字 → 補一筆新的
    @discardableResult
    func append(_ kind: Item.Kind, name: String = "", username: String = "", value: String = "") -> Item {
        var it = Item(kind: kind)
        it.name = name
        it.username = username
        it.value = value
        items.append(it)
        scheduleSave()
        return it
    }

    /// 刪一筆的時候**連它的附件一起刪**，不然 blobs 目錄會慢慢囤滿再也讀不到的密文。
    func delete(_ id: String) {
        if let it = items.first(where: { $0.id == id }), !it.attachment.isEmpty {
            Storage.deleteBlob(it.attachment)
        }
        items.removeAll { $0.id == id }
        if expanded == id { expanded = nil }
        scheduleSave()
    }

    /// 照片和影片走格狀，沒有 detail 抽屜可以改名字，改名的入口在檢視窗的標題。
    func rename(_ id: String, to name: String) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].name != name else { return }
        items[i].name = name
        items[i].updated = .now
        scheduleSave()
    }

    func toggleDetail(_ id: String) {
        expanded = (expanded == id) ? nil : id
    }

    // ── 上鎖 ──────────────────────────────────────────
    /// 上鎖要做四件事，缺一不可：存檔、**抹掉主金鑰**、清掉解密過的暫存影片、收畫面。
    func lock() {
        // 存檔失敗還照樣清空記憶體的話，剛剛打的東西就真的消失了，而且**無聲無息**。
        // 鎖還是要鎖（安全優先），但一定要讓人知道。
        if masterKey != nil && !saveNow() {
            let a = NSAlert()
            a.messageText = "存檔失敗"
            a.informativeText = (lastError ?? "") + "\n\n這次的變更可能沒有寫進保管箱。"
            a.alertStyle = .critical
            a.runModal()
        }
        masterKey = nil
        Storage.clearScratch()
        thumbCache = [:]      // 解密過的縮圖也是明文，不能留在記憶體裡
        items = []
        tagList = []
        answerPlain = ""
        locked = true
        expanded = nil
        query = ""
        showSettings = false   // 設定開著時被自動上鎖，關掉才不會鎖完還看得到內容
        photoViewer = nil
    }

    // ── 標籤 ──────────────────────────────────────────
    // 標籤本身是有顏色的物件，不只是字串。這套設計每個元件挑一支蠟筆，
    // 標籤是唯一適合讓顏色帶意義的地方（顏色在別處都只是裝飾）。
    var tagList: [TagDef] = []

    /// 這個標籤被幾筆用到
    func usage(_ name: String) -> Int {
        items.filter { $0.tags.contains(name) }.count
    }

    func addTag(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !tagList.contains(where: { $0.name == n }) else { return }
        tagList.append(TagDef(name: n, colour: tagList.count % TagDef.palette.count))
        scheduleSave()
    }

    /// 改名要同步改掉所有項目上的那個字串，否則標籤會斷開。
    func renameTag(_ id: String, to newName: String) {
        let n = newName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty,
              let i = tagList.firstIndex(where: { $0.id == id }),
              !tagList.contains(where: { $0.name == n && $0.id != id }) else { return }
        let old = tagList[i].name
        tagList[i].name = n
        for j in items.indices {
            items[j].tags = items[j].tags.map { $0 == old ? n : $0 }
        }
        scheduleSave()
    }

    func deleteTag(_ id: String) {
        guard let i = tagList.firstIndex(where: { $0.id == id }) else { return }
        let name = tagList[i].name
        tagList.remove(at: i)
        for j in items.indices {
            items[j].tags.removeAll { $0 == name }
        }
        scheduleSave()
    }

    func cycleTagColour(_ id: String) {
        guard let i = tagList.firstIndex(where: { $0.id == id }) else { return }
        tagList[i].colour = (tagList[i].colour + 1) % TagDef.palette.count
        scheduleSave()
    }

    func colour(ofTag name: String) -> Color {
        tagList.first { $0.name == name }?.swatch ?? .powder
    }

    // ── 匯入檔案 ──────────────────────────────────────
    /// 選檔 → **整份讀進來加密複製進 vault** → 問要不要清掉原檔。
    ///
    /// 舊版只記路徑，等於保管箱裡放的是一條指向桌面明文檔的捷徑。
    func pickFiles(_ kind: Item.Kind) {
        guard let key = masterKey else { return }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        switch kind {
        case .photo: panel.allowedContentTypes = [.image]
        case .video: panel.allowedContentTypes = [.movie, .video]
        default: break
        }
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls

        Task {
            working = true
            var imported: [URL] = []

            for url in urls {
                // 加密大檔要跑一段時間，這期間可能被閒置自動上鎖。
                // **鎖了就得停**——否則會把資料 append 進一個已經清空的陣列，
                // 而 `saveNow` 因為沒有金鑰不會寫檔，那筆就這樣消失，
                // 只在 blobs 底下留一個沒人指向的孤兒密文。
                guard masterKey != nil else { break }
                do {
                    let size = Store.summary(url)
                    let id = try await Task.detached(priority: .userInitiated) {
                        try Storage.importFile(url, key: key)
                    }.value

                    // 加密的期間被鎖住的話，這個 blob 就沒有歸屬了，直接清掉
                    guard masterKey != nil else { Storage.deleteBlob(id); break }

                    var it = Item(kind: kind)
                    it.name = url.deletingPathExtension().lastPathComponent
                    it.ext = url.pathExtension
                    it.attachment = id
                    it.value = size
                    items.append(it)
                    imported.append(url)
                } catch {
                    lastError = "「\(url.lastPathComponent)」匯入失敗"
                }
            }

            saveNow()
            working = false
            if !imported.isEmpty { offerToTrashOriginals(imported) }
        }
    }

    /// 匯入之後原檔還躺在桌面上。**不問就自動刪太危險，不刪則保管箱等於白鎖**，
    /// 所以每次問一次，而且走垃圾桶不走永久刪除。
    private func offerToTrashOriginals(_ urls: [URL]) {
        let a = NSAlert()
        a.messageText = urls.count == 1
            ? "已加密收進保管箱。原始檔案要移到垃圾桶嗎？"
            : "已加密收進保管箱（\(urls.count) 個）。原始檔案要移到垃圾桶嗎？"
        a.informativeText = "原始檔案還在原本的位置，那份是沒有加密的。"
        a.addButton(withTitle: "移到垃圾桶")
        a.addButton(withTitle: "保留原檔")
        a.alertStyle = .informational

        guard a.runModal() == .alertFirstButtonReturn else { return }
        for u in urls {
            try? FileManager.default.trashItem(at: u, resultingItemURL: nil)
        }
    }

    /// 幫某一筆既有項目掛上附件（DOCUMENTS 分頁的「＋ 加入檔案」走這條）。
    func attach(_ url: URL, to id: String) {
        guard let key = masterKey else { return }
        Task {
            working = true
            defer { working = false }
            let size = Store.summary(url)
            do {
                let blob = try await Task.detached(priority: .userInitiated) {
                    try Storage.importFile(url, key: key)
                }.value
                // 這筆在加密期間被刪掉、或整個保管箱被鎖上了，都不能留孤兒密文
                guard masterKey != nil,
                      let i = items.firstIndex(where: { $0.id == id }) else {
                    Storage.deleteBlob(blob)
                    return
                }
                if !items[i].attachment.isEmpty { Storage.deleteBlob(items[i].attachment) }
                items[i].attachment = blob
                items[i].ext = url.pathExtension
                if items[i].value.isEmpty { items[i].value = size }
                items[i].updated = .now
                saveNow()
                offerToTrashOriginals([url])
            } catch {
                lastError = "「\(url.lastPathComponent)」匯入失敗"
            }
        }
    }

    private static func summary(_ url: URL) -> String {
        let ext = url.pathExtension.uppercased()
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let f = ByteCountFormatter()
        f.countStyle = .file
        return bytes > 0 ? "\(ext) · \(f.string(fromByteCount: Int64(bytes)))" : ext
    }

    // ── 附件讀取 ──────────────────────────────────────
    /// 照片直接在記憶體解密，不落地。
    func imageData(_ item: Item) -> Data? {
        guard let key = masterKey, !item.attachment.isEmpty else { return nil }
        return try? Storage.readBlob(item.attachment, key: key)
    }

    /// 格狀畫面用的縮圖。
    ///
    /// **`@ObservationIgnored` 不能拿掉。** 這個函式是在 SwiftUI 的 body 裡被呼叫的，
    /// 而它會寫入這個字典——被 @Observable 追蹤的話，寫入會通知畫面重繪、
    /// 重繪又呼叫它、再寫入……當場無限迴圈。
    @ObservationIgnored private var thumbCache: [String: NSImage] = [:]

    func thumbnail(_ item: Item) -> NSImage? {
        guard let key = masterKey, !item.attachment.isEmpty else { return nil }
        if let cached = thumbCache[item.attachment] { return cached }
        guard let data = Storage.readThumbnail(item.attachment, key: key),
              let img = NSImage(data: data) else { return nil }
        thumbCache[item.attachment] = img
        return img
    }

    /// 影片得先解密成真的檔案才能播。上鎖時 `clearScratch()` 會掃掉。
    func materialise(_ item: Item) -> URL? {
        guard let key = masterKey, !item.attachment.isEmpty else { return nil }
        return try? Storage.materialise(item.attachment, name: item.name,
                                        ext: item.ext, key: key)
    }

    // ── 匯出 ──────────────────────────────────────────
    /// 倒出一份未加密的副本。實際的工作在 `Storage.exportPlaintext`，
    /// **丟到背景跑**——附件多的時候這裡要解密好幾百 MB，留在主執行緒畫面會凍住。
    func exportPlaintext(to dir: URL) async {
        guard let key = masterKey else { return }
        working = true
        defer { working = false }

        let f = ISO8601DateFormatter()
        f.formatOptions = [.withYear, .withMonth, .withDay]
        let stamp = f.string(from: .now)
        let snapshot = items      // Item 是值型別，帶去背景是安全的

        do {
            let root = try await Task.detached(priority: .userInitiated) {
                try Storage.exportPlaintext(snapshot, key: key, to: dir, stamp: stamp)
            }.value
            NSWorkspace.shared.activateFileViewerSelecting([root])
        } catch {
            lastError = "匯出失敗：\(error.localizedDescription)"
        }
    }

    // ── 重設 ──────────────────────────────────────────
    /// 密碼和復原金鑰都丟了的唯一出路：整個砍掉重建。**資料救不回來**，
    /// 這是加密的必然結果，不是 bug。
    func destroyVault() {
        Storage.destroyAll()
        Biometrics.forget()
        masterKey = nil
        items = []
        tagList = []
        locked = true
    }
}
