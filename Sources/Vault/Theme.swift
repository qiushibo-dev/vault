import SwiftUI

// ── 配色 ──────────────────────────────────────────────
// DESIGN.md 的 crayon box。原則：所有結構線都是純黑，
// 顏色只當裝飾與分頁標記，不表達狀態（不用紅色表示危險那種）。
// 灰色一律不用——那會破壞「紙上的墨」這個比喻。
extension Color {
    static let peach   = Color(hex: 0xf6e0db)   // 畫布
    static let ink     = Color.black            // 所有線與字
    static let snow    = Color.white            // 卡片
    static let ember   = Color(hex: 0xef724f)   // 橘
    static let magenta = Color(hex: 0x981082)   // 洋紅
    static let sunbeam = Color(hex: 0xe7db4c)   // 黃
    static let mint    = Color(hex: 0xace2df)   // 薄荷
    static let powder  = Color(hex: 0x84bfff)   // 天藍
    static let lilac   = Color(hex: 0xe69dff)   // 淡紫
    static let lime    = Color(hex: 0x6ed311)   // 綠

    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >>  8) & 0xff) / 255,
                  blue:  Double( hex        & 0xff) / 255)
    }
}

// ── 尺寸 ──────────────────────────────────────────────
enum Metric {
    static let border: CGFloat = 2       // 所有黑框都是 2px
    static let pill:   CGFloat = 47      // 藥丸與主要容器
    static let card:   CGFloat = 40      // 卡片
    static let small:  CGFloat = 10      // 巢狀的小元件
    static let win     = CGSize(width: 760, height: 880)
    /// 橫線紙上固定寬度的欄（名稱、使用者名稱）。
    /// 密碼那頁是三欄，760 的視窗扣掉分隔線和右邊兩顆按鈕之後，
    /// 這個數字再大就會把密碼欄擠到只剩一小條。
    static let col:    CGFloat = 132
}

// ── 藥丸容器 ──────────────────────────────────────────
// 白底、2px 黑框、全圓角。這個風格的招牌，導覽、按鈕、標籤共用。
struct Pill<C: View>: View {
    var fill: Color = .snow
    var radius: CGFloat = Metric.pill
    var padH: CGFloat = 20
    var padV: CGFloat = 10
    @ViewBuilder var content: C

    var body: some View {
        content
            .padding(.horizontal, padH)
            .padding(.vertical, padV)
            .background(RoundedRectangle(cornerRadius: radius).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: radius)
                .stroke(Color.ink, lineWidth: Metric.border))
    }
}

// ── 黑框白卡 ──────────────────────────────────────────
struct OutlineCard<C: View>: View {
    var fill: Color = .snow
    var radius: CGFloat = Metric.card
    @ViewBuilder var content: C

    var body: some View {
        content
            .background(RoundedRectangle(cornerRadius: radius).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: radius)
                .stroke(Color.ink, lineWidth: Metric.border))
    }
}

// ── 線稿塗鴉 ──────────────────────────────────────────
// 這個風格的靈魂是散落在畫布上、角度不一的手繪線稿。
// 全部單線黑色、不填色，刻意不對齊格線。
enum Doodle: CaseIterable {
    case key, lock, fingerprint, star, spiral, eye, gear, clip, film, magnifier

    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        switch self {
        case .gear:
            // 方齒齒輪。中心孔用 evenOdd 挖空，所以填色時要傳 FillStyle(eoFill: true)。
            let c = CGPoint(x: w / 2, y: h / 2)
            let n = 8
            let rO = w * 0.50, rI = w * 0.38
            let unit = Double.pi * 2 / Double(n)
            var first = true
            for i in 0..<n {
                let a = Double(i) * unit - .pi / 2
                for (da, rr) in [(-unit * 0.21, rI), (-unit * 0.13, rO),
                                 ( unit * 0.13, rO), ( unit * 0.21, rI)] {
                    let pt = CGPoint(x: c.x + cos(a + da) * rr, y: c.y + sin(a + da) * rr)
                    if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
                }
            }
            p.closeSubpath()
            p.addEllipse(in: CGRect(x: w * 0.37, y: h * 0.37, width: w * 0.26, height: h * 0.26))
        case .key:
            p.addEllipse(in: CGRect(x: 0, y: h * 0.12, width: w * 0.42, height: w * 0.42))
            p.move(to: CGPoint(x: w * 0.36, y: h * 0.40))
            p.addLine(to: CGPoint(x: w * 0.96, y: h * 0.78))
            p.move(to: CGPoint(x: w * 0.74, y: h * 0.64))
            p.addLine(to: CGPoint(x: w * 0.66, y: h * 0.80))
            p.move(to: CGPoint(x: w * 0.86, y: h * 0.72))
            p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.88))
        case .lock:
            p.addRoundedRect(in: CGRect(x: w * 0.10, y: h * 0.44, width: w * 0.80, height: h * 0.50),
                             cornerSize: CGSize(width: 5, height: 5))
            p.move(to: CGPoint(x: w * 0.27, y: h * 0.46))
            p.addCurve(to: CGPoint(x: w * 0.73, y: h * 0.46),
                       control1: CGPoint(x: w * 0.24, y: h * 0.02),
                       control2: CGPoint(x: w * 0.76, y: h * 0.02))
        case .fingerprint, .spiral:
            // 阿基米德螺線，一筆到底。
            //
            // 步長要夠小。第一版用 0.18 弧度，畫出來是多邊形，轉角看得一清二楚；
            // 指紋那版更糟，用逐圈錯開缺口的斷弧拼，結果像破掉的靶心。
            let c = CGPoint(x: w / 2, y: h / 2)
            let turns: CGFloat = self == .fingerprint ? 2.6 : 3.4
            let total = .pi * 2 * turns
            var a: CGFloat = 0
            p.move(to: c)
            while a <= total {
                let rr = (a / total) * (w / 2 - 1.5)   // 留線寬的一半，不然外圈會被切到
                p.addLine(to: CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr))
                a += 0.05
            }
        case .star:
            for i in 0..<5 {
                let a = CGFloat(i) * .pi * 4 / 5 - .pi / 2
                let pt = CGPoint(x: w / 2 + cos(a) * w / 2, y: h / 2 + sin(a) * h / 2)
                i == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
            p.closeSubpath()
        case .film:
            // 底片格：外框 ＋ 兩側齒孔 ＋ 中間播放三角
            p.addRoundedRect(in: CGRect(x: 0, y: h * 0.14, width: w, height: h * 0.72),
                             cornerSize: CGSize(width: 5, height: 5))
            for i in 0..<4 {
                let y = h * (0.22 + Double(i) * 0.18)
                p.addRect(CGRect(x: w * 0.05, y: y, width: w * 0.10, height: h * 0.09))
                p.addRect(CGRect(x: w * 0.85, y: y, width: w * 0.10, height: h * 0.09))
            }
            p.move(to: CGPoint(x: w * 0.41, y: h * 0.38))
            p.addLine(to: CGPoint(x: w * 0.64, y: h * 0.50))
            p.addLine(to: CGPoint(x: w * 0.41, y: h * 0.62))
            p.closeSubpath()

        case .clip:
            // 迴紋針。一筆繞兩圈半，外圈長、內圈短。
            p.move(to: CGPoint(x: w * 0.70, y: h * 0.34))
            p.addLine(to: CGPoint(x: w * 0.70, y: h * 0.70))
            p.addArc(center: CGPoint(x: w * 0.50, y: h * 0.70), radius: w * 0.20,
                     startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            p.addLine(to: CGPoint(x: w * 0.30, y: h * 0.26))
            p.addArc(center: CGPoint(x: w * 0.44, y: h * 0.26), radius: w * 0.14,
                     startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            p.addLine(to: CGPoint(x: w * 0.58, y: h * 0.60))

        case .magnifier:
            // 放大鏡。圓心 (0.38, 0.38)、半徑 0.30，柄從圓上 45 度那一點接出去——
            // 0.38 + 0.30 × cos45° = 0.59，所以柄起點寫 0.59 才會貼著圓而不是穿進去。
            p.addEllipse(in: CGRect(x: w * 0.08, y: h * 0.08, width: w * 0.60, height: h * 0.60))
            p.move(to: CGPoint(x: w * 0.59, y: h * 0.59))
            p.addLine(to: CGPoint(x: w * 0.93, y: h * 0.93))

        case .eye:
            p.move(to: CGPoint(x: 0, y: h / 2))
            p.addQuadCurve(to: CGPoint(x: w, y: h / 2), control: CGPoint(x: w / 2, y: -h * 0.15))
            p.addQuadCurve(to: CGPoint(x: 0, y: h / 2), control: CGPoint(x: w / 2, y: h * 1.15))
            p.addEllipse(in: CGRect(x: w * 0.38, y: h * 0.30, width: w * 0.24, height: w * 0.24))
        }
        return p
    }
}

/// 同一份路徑當 Shape 用，才能填色（齒輪那種實心元件需要）。
struct DoodleShape: Shape {
    let kind: Doodle
    func path(in rect: CGRect) -> Path { kind.path(in: rect) }
}

struct DoodleView: View {
    let kind: Doodle
    var size: CGFloat = 60
    var angle: Double = 0
    var stroke: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            kind.path(in: CGRect(origin: .zero, size: geo.size))
                .stroke(Color.ink, style: StrokeStyle(lineWidth: stroke,
                                                      lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(angle))
    }
}
