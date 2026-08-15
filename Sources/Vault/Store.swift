import SwiftUI
import AppKit

/// 標籤定義。顏色從固定的蠟筆盒裡挑，不讓使用者自由選色——
/// 這套視覺的前提是所有顏色都出自同一盒，自由選色會立刻破功。
struct TagDef: Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var colour: Int

    static let palette: [Color] = [.ember, .mint, .sunbeam, .lilac, .powder, .lime, .magenta]
    var swatch: Color { TagDef.palette[colour % TagDef.palette.count] }
}

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

    // ── 密碼 ──────────────────────────────────────────
    // wireframe 階段就存字串，真正的實作是拿密碼派生金鑰、
    // 存的是驗證用的雜湊，比對字串這個步驟根本不存在。
    var password: String? = nil
    var hasPassword: Bool { password != nil }
    /// 建立／變更密碼的表單
    var pwSheet: PasswordSheetMode? = nil
    /// 雙擊照片打開的檢視窗
    var photoViewer: Item? = nil
    /// 檢查更新的結果
    var updateState: UpdateState = .idle

    func createPassword(_ p: String) {
        password = p
        regenerateRecoveryKey()   // 有了密碼才有金鑰可包，這時候才產生復原金鑰
        locked = false            // 建立完直接進去，不用再輸入一次
    }

    func changePassword(_ p: String) { password = p }

    // ── 救援 ──────────────────────────────────────────
    /// 忘記密碼時給自己看的提示。存在 app 裡，鎖定畫面看得到，
    /// 所以**不能寫成密碼本身**——寫「母親的舊姓」可以，寫「Kaoru1987」不行。
    /// 預設必須是空字串。給了預設值的話，建立密碼的表單一開就把它帶進欄位裡，
    /// 看起來像 placeholder 但其實是真的內容，使用者不改就直接存進去了。
    var passwordHint = ""

    /// 復原金鑰。建立 Vault 時產生一次，之後只能重新產生（舊的作廢）。
    /// 真正的實作是拿它包裝主金鑰，跟密碼那把是平行的兩把鑰匙。
    var recoveryKey: String? = nil

    // ── 設定 ──────────────────────────────────────────
    var touchIDOn = true
    var icloudSync = true
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
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }
    var dataPath: String {
        "~/Library/Application Support/Vault/vault.db"
    }

    func regenerateRecoveryKey() {
        let set = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")   // 去掉易混淆的 I O 0 1
        recoveryKey = (0..<6).map { _ in
            String((0..<4).map { _ in set.randomElement()! })
        }.joined(separator: "-")
    }

    // ── 篩選 ──────────────────────────────────────────
    func rows(for tab: Tab) -> [Item] {
        let k = Item.kind(for: tab)
        return items.filter { $0.kind == k }
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
            }
        )
    }

    /// 在空白行打字 → 補一筆新的
    @discardableResult
    func append(_ kind: Item.Kind, name: String = "") -> Item {
        var it = Item(kind: kind)
        it.name = name
        items.append(it)
        return it
    }

    func delete(_ id: String) {
        items.removeAll { $0.id == id }
        if expanded == id { expanded = nil }
    }

    func toggleDetail(_ id: String) {
        expanded = (expanded == id) ? nil : id
    }

    // ── 上鎖 ──────────────────────────────────────────
    func lock() {
        locked = true
        expanded = nil
        showSettings = false   // 設定開著時被自動上鎖，關掉才不會鎖完還看得到內容
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
    }

    func deleteTag(_ id: String) {
        guard let i = tagList.firstIndex(where: { $0.id == id }) else { return }
        let name = tagList[i].name
        tagList.remove(at: i)
        for j in items.indices {
            items[j].tags.removeAll { $0 == name }
        }
    }

    func cycleTagColour(_ id: String) {
        guard let i = tagList.firstIndex(where: { $0.id == id }) else { return }
        tagList[i].colour = (tagList[i].colour + 1) % TagDef.palette.count
    }

    func colour(ofTag name: String) -> Color {
        tagList.first { $0.name == name }?.swatch ?? .powder
    }

    // ── 匯入檔案 ──────────────────────────────────────
    /// wireframe 只記路徑。真正的實作要把檔案加密後複製進 vault，
    /// 不然「保管箱」裡放的其實是一條指向桌面明文檔的捷徑。
    func pickFiles(_ kind: Item.Kind) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        switch kind {
        case .photo: panel.allowedContentTypes = [.image]
        case .video: panel.allowedContentTypes = [.movie, .video]
        default: break
        }
        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            var it = Item(kind: kind)
            it.name = url.deletingPathExtension().lastPathComponent
            it.attachment = url.path
            it.value = Store.summary(url)
            items.append(it)
        }
    }

    private static func summary(_ url: URL) -> String {
        let ext = url.pathExtension.uppercased()
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let f = ByteCountFormatter()
        f.countStyle = .file
        return bytes > 0 ? "\(ext) · \(f.string(fromByteCount: Int64(bytes)))" : ext
    }
}
