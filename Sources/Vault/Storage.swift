import Foundation
import AppKit

// ── 位置 ──────────────────────────────────────────────
enum VaultPaths {
    /// 只給 `verify.sh` 用：把整個保管箱改指到暫存目錄。
    /// **正式執行時永遠是 nil**，驗證程式才不會動到真實資料。
    nonisolated(unsafe) static var overrideRoot: URL? = nil

    /// `~/Library/Application Support/Vault/`
    static var dir: URL {
        if let o = overrideRoot { return o }
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vault", isDirectory: true)
    }

    static var data: URL { dir.appendingPathComponent("vault.dat") }
    static var blobs: URL { dir.appendingPathComponent("blobs", isDirectory: true) }

    /// 解密後的影片暫存區。**放在 Caches 是刻意的**——系統在空間不足時可以自己清掉，
    /// 而且不會被 Time Machine 備份走（那會是一份沒加密的副本躺在備份裡）。
    static var scratch: URL {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vault", isDirectory: true)
    }

    /// 目錄權限設 0700：只有這個帳號讀得到。同一台機器的其他使用者連檔名都列不出來。
    static func ensureDir() throws {
        for d in [dir, blobs] {
            if !FileManager.default.fileExists(atPath: d.path) {
                try FileManager.default.createDirectory(
                    at: d, withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
            }
        }
    }
}

// ── 存進去的東西 ──────────────────────────────────────
/// 整個保管箱的內容，加密後就是 `vault.dat` 那一塊密文。
///
/// 設定也包在裡面，不放 UserDefaults。因為「閒置多久上鎖」「Touch ID 開不開」
/// 這些設定本身就是安全設定，**放在明文的 plist 裡等於讓人可以從外面改掉它們**。
struct VaultPayload: Codable {
    var version = 1
    var items: [Item] = []
    var tags: [TagDef] = []
    var prefs = Prefs()

    /// 提示問題的答案，明文。
    ///
    /// **這一份存在這裡而不是 `keys.json` 是有講究的。**
    /// 金鑰檔在還沒解鎖時就要讀（鎖定畫面要顯示提示問題），所以裡面不能有機密；
    /// 而這份是用主金鑰加密的，只有已經解鎖的人看得到——那個人本來就看得到
    /// 裡面所有密碼了，再看到自己設的答案並不會多洩漏什麼。
    ///
    /// 目的很單純：讓使用者能回頭確認自己當初有沒有打錯字。
    /// 驗證答案用的仍然是 `keys.json` 裡那份包裝過的主金鑰，**不是拿這裡的字串來比對**。
    var answerPlain = ""

    init(items: [Item] = [], tags: [TagDef] = [], prefs: Prefs = Prefs(), answerPlain: String = "") {
        self.items = items; self.tags = tags; self.prefs = prefs; self.answerPlain = answerPlain
    }

    /// 跟 `Item` 同樣的理由：加欄位不能讓舊存檔變成解不開。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        items   = try c.decodeIfPresent([Item].self, forKey: .items) ?? []
        tags    = try c.decodeIfPresent([TagDef].self, forKey: .tags) ?? []
        prefs   = try c.decodeIfPresent(Prefs.self, forKey: .prefs) ?? Prefs()
        answerPlain = try c.decodeIfPresent(String.self, forKey: .answerPlain) ?? ""
    }
}

struct Prefs: Codable {
    var touchIDOn = true
    var icloudSync = false
    var autoLockSeconds = 30
    var clipboardSeconds = 30
    var lang: Lang = .zh

    init(touchIDOn: Bool = true, icloudSync: Bool = false,
         autoLockSeconds: Int = 30, clipboardSeconds: Int = 30, lang: Lang = .zh) {
        self.touchIDOn = touchIDOn; self.icloudSync = icloudSync
        self.autoLockSeconds = autoLockSeconds; self.clipboardSeconds = clipboardSeconds
        self.lang = lang
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        touchIDOn       = try c.decodeIfPresent(Bool.self, forKey: .touchIDOn) ?? true
        icloudSync      = try c.decodeIfPresent(Bool.self, forKey: .icloudSync) ?? false
        autoLockSeconds = try c.decodeIfPresent(Int.self, forKey: .autoLockSeconds) ?? 30
        clipboardSeconds = try c.decodeIfPresent(Int.self, forKey: .clipboardSeconds) ?? 30
        lang            = try c.decodeIfPresent(Lang.self, forKey: .lang) ?? .zh
    }
}

// ── 讀寫 ──────────────────────────────────────────────
enum Storage {

    static var exists: Bool { FileManager.default.fileExists(atPath: VaultPaths.data.path) }

    /// 寫檔用 atomic：先寫暫存檔再一次換過去。
    /// 直接覆寫的話，寫到一半當機就會留下一個半截的檔案——而半截的密文是**永遠解不開的**，
    /// 不像純文字還能救回前半段。
    static func save(_ payload: VaultPayload, key: Data) throws {
        try VaultPaths.ensureDir()
        let json = try JSONEncoder().encode(payload)
        let blob = try Crypto.seal(json, key: key)
        try blob.write(to: VaultPaths.data, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: VaultPaths.data.path)
    }

    static func load(key: Data) throws -> VaultPayload {
        // **「檔案不存在」和「檔案讀不到」必須分開。**
        //
        // 原本兩種都回一個空的 payload，後果是：磁碟出問題或權限跑掉的時候，
        // 使用者解鎖後看到的是一個空的保管箱，接著任何一次自動存檔就會用這個空的
        // 蓋掉原本好好的密文——**東西還在硬碟上卻被我們自己抹掉**。
        // 讀不到就要丟錯，讓它連進都進不去。
        guard exists else {
            return VaultPayload()      // 有金鑰檔但還沒存過任何東西，正常情況
        }
        guard let blob = try? Data(contentsOf: VaultPaths.data) else {
            throw VaultError.ioFailed("資料檔存在但讀不到，請檢查檔案權限")
        }
        let json = try Crypto.open(blob, key: key)
        do {
            return try JSONDecoder().decode(VaultPayload.self, from: json)
        } catch {
            throw VaultError.corrupted
        }
    }

    // ── 附件 ──────────────────────────────────────────
    /// 匯入一個檔案：整份讀進來、加密、寫成 `blobs/<id>`。
    ///
    /// 回傳的 id 存進 `Item.attachment`。**存的是 id 不是路徑**——
    /// 存路徑的話保管箱裡放的其實是一條指向桌面明文檔的捷徑，原檔一搬走就變空白。
    ///
    /// 是圖片的話順便存一份加密縮圖。**格狀畫面絕對不能去解原圖**——
    /// 九宮格等於一次解九張全尺寸照片，捲動時每次重繪都再解一遍，畫面會直接凍住。
    static func importFile(_ source: URL, key: Data) throws -> String {
        try VaultPaths.ensureDir()
        let raw = try Data(contentsOf: source)
        let id = UUID().uuidString
        let sealed = try Crypto.seal(raw, key: key)
        try sealed.write(to: VaultPaths.blobs.appendingPathComponent(id), options: [.atomic])

        if let thumb = makeThumbnail(raw, maxSide: 512) {
            let t = try Crypto.seal(thumb, key: key)
            try? t.write(to: thumbURL(id), options: [.atomic])
        }
        return id
    }

    private static func thumbURL(_ id: String) -> URL {
        VaultPaths.blobs.appendingPathComponent("\(id).thumb")
    }

    /// 縮圖讀不到就回 nil，呼叫端顯示占位圖即可——不要退回去解原圖，那正是要避免的事。
    static func readThumbnail(_ id: String, key: Data) -> Data? {
        guard !id.isEmpty, let blob = try? Data(contentsOf: thumbURL(id)) else { return nil }
        return try? Crypto.open(blob, key: key)
    }

    /// 縮圖存 JPEG。這裡不保留透明度也不管色彩描述檔——它只是九宮格裡一個 100 點寬的方塊。
    private static func makeThumbnail(_ raw: Data, maxSide: CGFloat) -> Data? {
        guard let rep = NSBitmapImageRep(data: raw) else { return nil }

        // 用 pixelsWide/High，不是 size——後者是點不是像素，Retina 來源會少一半
        let w = CGFloat(rep.pixelsWide), h = CGFloat(rep.pixelsHigh)
        guard w > 0, h > 0 else { return nil }
        let scale = min(1, maxSide / max(w, h))
        let size = NSSize(width: max(1, (w * scale).rounded()),
                          height: max(1, (h * scale).rounded()))

        guard let out = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        out.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        NSGraphicsContext.current?.imageInterpolation = .high
        rep.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()

        return out.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }

    /// 把附件解密回記憶體。照片走這條，不落地。
    static func readBlob(_ id: String, key: Data) throws -> Data {
        guard !id.isEmpty else { throw VaultError.notInitialised }
        let url = VaultPaths.blobs.appendingPathComponent(id)
        guard let blob = try? Data(contentsOf: url) else {
            throw VaultError.ioFailed("附件不存在")
        }
        return try Crypto.open(blob, key: key)
    }

    static func deleteBlob(_ id: String) {
        guard !id.isEmpty else { return }
        try? FileManager.default.removeItem(at: VaultPaths.blobs.appendingPathComponent(id))
        try? FileManager.default.removeItem(at: thumbURL(id))
    }

    static func blobExists(_ id: String) -> Bool {
        !id.isEmpty && FileManager.default.fileExists(
            atPath: VaultPaths.blobs.appendingPathComponent(id).path)
    }

    // ── 影片的暫存檔 ──────────────────────────────────
    /// AVPlayer 沒辦法直接播記憶體裡的密文，只能先解密到一個真的檔案。
    ///
    /// **這是整套設計裡唯一會讓明文落地的地方**，所以：檔案權限 0600、放在 Caches、
    /// 而且上鎖時一定要呼叫 `clearScratch()` 掃掉。
    static func materialise(_ id: String, name: String, ext: String, key: Data) throws -> URL {
        let data = try readBlob(id, key: key)
        try FileManager.default.createDirectory(
            at: VaultPaths.scratch, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])

        let safe = name.isEmpty ? id : name.replacingOccurrences(of: "/", with: "-")
        let url = VaultPaths.scratch
            .appendingPathComponent(safe)
            .appendingPathExtension(ext.isEmpty ? "dat" : ext)
        try data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    /// 上鎖時清空暫存區。漏掉這步的話，鎖上的保管箱旁邊會躺著一份沒加密的影片。
    static func clearScratch() {
        try? FileManager.default.removeItem(at: VaultPaths.scratch)
    }

    // ── 整個砍掉 ──────────────────────────────────────
    /// 只在「重設保管箱」時用。走垃圾桶不走永久刪除，因為這個動作沒有回頭路。
    static func destroyAll() {
        clearScratch()
        try? FileManager.default.trashItem(at: VaultPaths.dir, resultingItemURL: nil)
    }

    // ── 匯出 ──────────────────────────────────────────
    /// 倒出一份未加密的副本。密碼和文件寫成一個 CSV，附件還原成原本的檔案。
    ///
    /// **不用 JSON。** 這份東西的用途是「哪天 app 不能跑了還讀得到自己的密碼」，
    /// 那時候需要的是試算表打得開的東西，不是要另外找工具才能看的格式。
    ///
    /// 放在 Storage 而不是 Store，是因為它得在背景執行緒跑——附件多的時候
    /// 這裡要解密好幾百 MB，留在主執行緒畫面會整個凍住。
    static func exportPlaintext(_ items: [Item], key: Data, to dir: URL, stamp: String) throws -> URL {
        let root = dir.appendingPathComponent("Vault 未加密備份 \(stamp)")
        let files = root.appendingPathComponent("附件", isDirectory: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)

        var csv = "分類,名稱,內容,網址,備註,標籤,附件檔名,建立時間,更新時間\n"
        let iso = ISO8601DateFormatter()

        for it in items {
            var filename = ""
            if !it.attachment.isEmpty, let data = try? readBlob(it.attachment, key: key) {
                // 同名的項目會互相覆蓋，補上編號前八碼區隔
                let base = it.name.isEmpty ? "未命名" : it.name
                filename = "\(base)_\(it.attachment.prefix(8))"
                    .replacingOccurrences(of: "/", with: "-")
                if !it.ext.isEmpty { filename += ".\(it.ext)" }
                try? data.write(to: files.appendingPathComponent(filename), options: [.atomic])
            }

            let cols = [it.kind.rawValue, it.name, it.value, it.url, it.note,
                        it.tags.joined(separator: " "), filename,
                        iso.string(from: it.created), iso.string(from: it.updated)]
            csv += cols.map(csvEscape).joined(separator: ",") + "\n"
        }

        // 加 BOM，否則 Excel 會把中日文的 UTF-8 讀成亂碼
        var out = Data([0xEF, 0xBB, 0xBF])
        out.append(csv.data(using: .utf8) ?? Data())
        try out.write(to: root.appendingPathComponent("vault.csv"), options: [.atomic])
        return root
    }

    /// 密碼裡出現逗號和引號是家常便飯，跳脫沒做好整份 CSV 的欄位就全錯開了。
    private static func csvEscape(_ s: String) -> String {
        guard s.contains(",") || s.contains("\"") || s.contains("\n") else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // ── 大小 ──────────────────────────────────────────
    /// **不要在 SwiftUI 的 body 裡呼叫。** 這會走訪整個目錄，
    /// 而 body 每次重繪都會再走一次。算一次存起來就好。
    static var footprint: String {
        let keys = [URLResourceKey.fileSizeKey]
        var total: Int64 = 0
        if let e = FileManager.default.enumerator(at: VaultPaths.dir,
                                                  includingPropertiesForKeys: keys) {
            for case let u as URL in e {
                total += Int64((try? u.resourceValues(forKeys: Set(keys)).fileSize) ?? 0)
            }
        }
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: total)
    }
}
