import Foundation

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
    var attachment = ""        // 檔名，實體檔另外加密存放
    var created = Date()
    var updated = Date()

    enum Kind: String, Codable { case password, document, photo, video }

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
