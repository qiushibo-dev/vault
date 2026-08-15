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
        value.trimmingCharacters(in: .whitespaces).isEmpty
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
