import SwiftUI
import AppKit
import CoreText

/// 字體。DESIGN.md 指定兩支：
///   Alfa Slab One — 標題，只有一個字重，46px 以上才用，16px 以下不准用
///   Manrope       — 其他全部。500 給導覽、400 給內文、700-800 只給行內強調
///
/// 兩支都沒有中日文。這個 app 的內容大量是日文（在留カード、賃貸契約書），
/// 所以靠 CoreText 的 cascade list 接到 Noto。`Font.custom` 只吃單一字體、
/// 沒有 fallback 鏈，指定 Manrope 之後日文會落到系統的 Hiragino，
/// 嵌進 bundle 的 Noto 根本用不到。（Babos 踩過，直接沿用結論。）
enum Typo {
    private static func cascaded(_ primary: String, size: CGFloat,
                                 weight: NSFont.Weight) -> Font {
        let fallbacks = ["Noto Sans TC", "Noto Sans JP"]
            .map { CTFontDescriptorCreateWithNameAndSize($0 as CFString, size) }
        let desc = CTFontDescriptorCreateWithAttributes([
            kCTFontNameAttribute: primary,
            kCTFontSizeAttribute: size,
            kCTFontCascadeListAttribute: fallbacks,
            kCTFontTraitsAttribute: [kCTFontWeightTrait: weight.rawValue],
        ] as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(desc, size, nil))
    }

    /// 標題用的粗襯線。DESIGN.md：不要小於 16px。
    static func slab(_ size: CGFloat) -> Font {
        cascaded("Alfa Slab One", size: max(size, 16), weight: .black)
    }
    /// 其他全部。
    static func sans(_ size: CGFloat, _ w: NSFont.Weight = .regular) -> Font {
        cascaded("Manrope", size: size, weight: w)
    }

    // ── Type scale（照 DESIGN.md 的表）──────────────────
    static var display:    Font { slab(50) }    // 鎖定畫面的 VAULT
    static var heading:    Font { slab(35) }
    static var headingSm:  Font { slab(25) }

    static var nav:        Font { sans(16, .medium) }    // 藥丸導覽
    static var body:       Font { sans(16) }
    static var bodyBold:   Font { sans(16, .bold) }
    static var row:        Font { sans(17, .medium) }    // 列表左欄
    static var rowValue:   Font { sans(16) }             // 列表右欄
    static var caption:    Font { sans(12) }
    static var tag:        Font { sans(13, .bold) }      // 標籤藥丸
    static var button:     Font { sans(18, .bold) }
}
