import Foundation
import SwiftUI

// ── 標籤 ──────────────────────────────────────────────
/// 顏色從固定的蠟筆盒裡挑，不讓使用者自由選色——
/// 這套視覺的前提是所有顏色都出自同一盒，自由選色會立刻破功。
struct TagDef: Identifiable, Equatable, Codable {
    var id = UUID().uuidString
    var name: String
    var colour: Int

    /// `palette` 和 `swatch` 是畫面用的，不進存檔（存的只有 `colour` 這個索引）
    static let palette: [Color] = [.ember, .mint, .sunbeam, .lilac, .powder, .lime, .magenta]
    var swatch: Color { TagDef.palette[colour % TagDef.palette.count] }

    enum CodingKeys: String, CodingKey { case id, name, colour }
}

// ── 分頁 ──────────────────────────────────────────────
// Figma 上的三個標籤。順序就是畫面上的順序，不要改。
enum Tab: String, CaseIterable, Identifiable {
    case passwords, documents, photos, videos
    var id: String { rawValue }

    var label: String {
        switch self {
        case .passwords: "PASSWORDS"
        case .documents: "DOCUMENTS"
        case .photos:    "PHOTOS"
        case .videos:    "VIDEO"
        }
    }
    /// 照片和影片都是用看的，走格狀；密碼和文件走橫線紙。
    var isGrid: Bool { self == .photos || self == .videos }
}

/// 建立密碼跟變更密碼是同一張表單，差別只在要不要驗舊的。
enum PasswordSheetMode: String, Identifiable {
    case create, change
    var id: String { rawValue }
}

// ── 一筆資料 ──────────────────────────────────────────
// 三個分頁共用同一個型別。分頁只是 kind 的篩選，
// 因為一筆東西常常同時是兩種（銀行密碼掛一張提款卡照片）。
struct Item: Identifiable, Codable, Equatable {
    var id = UUID().uuidString
    var kind: Kind
    var name = ""              // 左欄
    /// 中欄，**只有密碼分頁會顯示**。一組密碼幾乎都連著一個帳號，
    /// 少了它就得把帳號硬塞進名稱欄或備註裡。選填。
    var username = ""
    var value = ""             // 右欄（密碼／檔案摘要）
    var url = ""
    var note = ""
    var tags: [String] = []
    /// 附件在 `blobs/` 底下的編號。**不是路徑**——實體檔已經加密複製進保管箱，
    /// 原檔搬走刪掉都不影響。
    var attachment = ""
    /// 原始副檔名。影片要解密成暫存檔才播得動，那個檔需要正確的副檔名。
    var ext = ""
    var created = Date()
    var updated = Date()

    enum Kind: String, Codable { case password, document, photo, video }

    /// **每個欄位都用 `decodeIfPresent`。**
    /// 這樣以後版本加新欄位時，舊存檔還是讀得進來（缺的欄位吃預設值）。
    /// 用預設的合成 init 的話，加一個欄位就會讓所有既有資料整包解不開——
    /// 而且因為外層是加密的，看起來會像「密碼錯了」，非常難查。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        kind       = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .password
        name       = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        username   = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        value      = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
        url        = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        note       = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        tags       = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        attachment = try c.decodeIfPresent(String.self, forKey: .attachment) ?? ""
        ext        = try c.decodeIfPresent(String.self, forKey: .ext) ?? ""
        created    = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date()
        updated    = try c.decodeIfPresent(Date.self, forKey: .updated) ?? Date()
    }

    init(kind: Kind) { self.kind = kind }

    var isBlank: Bool {
        name.trimmingCharacters(in: .whitespaces).isEmpty &&
        username.trimmingCharacters(in: .whitespaces).isEmpty &&
        value.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 底部搜尋欄的比對。大小寫和前後空白在這裡就正規化掉——
    /// 要求呼叫端先處理的話，哪天有第二個呼叫端忘了做，症狀是
    /// 「打大寫字母搜不到東西」，而那看起來像資料壞了，不像少呼叫一個函式。
    ///
    /// **`value` 刻意不比對。** 密碼分頁的 value 就是密碼本身，
    /// 讓它參與搜尋等於開了一個猜測管道——輸入幾個字元、看清單剩幾筆，
    /// 就能一格一格試出內容，畫面上什麼都不用顯示。
    /// 文件分頁的 value 只是「類型 · 大小」，一起排除比較單純。
    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return true }
        for field in [name, username, url, note] where field.lowercased().contains(q) {
            return true
        }
        // 標籤存的是名字本身，不是 id（改名時整批換掉），所以直接比字串。
        return tags.contains { $0.lowercased().contains(q) }
    }

    static func kind(for tab: Tab) -> Kind {
        switch tab {
        case .passwords: .password
        case .documents: .document
        case .photos:    .photo
        case .videos:    .video
        }
    }
}
