import SwiftUI
import AppKit

/// 復原金鑰只能在「剛產生」的那一刻顯示。
///
/// 加密之後這不是設計取捨，是必然：金鑰檔裡存的是**被這串字包裝過的主金鑰**，
/// 不是這串字本身。要能顯示它就得把它存下來，而存下來就等於在保管箱旁邊
/// 附一把備用鑰匙——那整套加密就白做了。
/// **只在建立保管箱時用。** 設定裡重新產生走的是就地展開，不再開這張。
struct RecoveryKey: Identifiable {
    let id = UUID().uuidString
    let value: String
}

struct RecoveryKeySheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let key: RecoveryKey

    @State private var copied = false
    private var t: L { store.t }

    var body: some View {
        ZStack {
            Color.peach

            VStack(spacing: 0) {
                DoodleView(kind: .key, size: 56, angle: -12)
                    .padding(.top, 26)

                Text(t.sKey)
                    .font(Typo.headingSm)
                    .padding(.top, 12)

                Text(t.recoveryOnce)
                    .font(Typo.caption)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 360)
                    .padding(.top, 8)

                Text(key.value)
                    .font(Typo.bodyBold)
                    .kerning(1)
                    .textSelection(.enabled)
                    .frame(width: 360)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: Metric.small).fill(Color.sunbeam))
                    .overlay(RoundedRectangle(cornerRadius: Metric.small)
                        .stroke(Color.ink, lineWidth: Metric.border))
                    .padding(.top, 20)

                HStack(spacing: 8) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(key.value, forType: .string)
                        copied = true
                    } label: {
                        Pill(fill: copied ? .lime : .snow, radius: Metric.pill, padH: 20, padV: 9) {
                            Text(copied ? t.copied : t.copy).font(Typo.nav)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button { dismiss() } label: {
                        Pill(fill: .ember, radius: Metric.pill, padH: 24, padV: 9) {
                            Text(t.gotIt).font(Typo.nav)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 22)

                Spacer(minLength: 24)
            }
        }
        .frame(width: 440, height: 380)
    }
}
