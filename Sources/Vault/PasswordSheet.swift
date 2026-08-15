import SwiftUI

/// 建立密碼／變更密碼。同一張表，差別只在最上面多不多一欄「目前的密碼」。
struct PasswordSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let mode: PasswordSheetMode

    @State private var current = ""
    @State private var pw = ""
    @State private var again = ""
    @State private var hint = ""
    @State private var error: String? = nil
    @FocusState private var focus: Field?

    private enum Field { case current, pw, again, hint }
    private var t: L { store.t }

    var body: some View {
        ZStack {
            Color.peach

            VStack(spacing: 0) {
                DoodleView(kind: .key, size: 54, angle: -14)
                    .padding(.top, 26)

                Text(mode == .create ? t.createPwTitle : t.changePwTitle)
                    .font(Typo.headingSm)
                    .padding(.top, 12)

                Text(t.createPwSub)
                    .font(Typo.caption)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 360)
                    .padding(.top, 8)

                VStack(spacing: 10) {
                    if mode == .change {
                        field(t.currentPw, $current, focus: .current)
                    }
                    field(mode == .create ? t.createPw : t.newPw, $pw, focus: .pw)
                    field(t.pwAgain, $again, focus: .again)

                    // 提示句只在建立時問。之後要改在設定裡改。
                    if mode == .create {
                        field(t.sHint, $hint, focus: .hint, secure: false, hint: t.hintPh)
                    }
                }
                .padding(.top, 22)

                // 錯誤訊息佔一個固定高度，不然出現時整張表會跳動
                Text(error ?? " ")
                    .font(Typo.caption)
                    .frame(height: 18)
                    .padding(.top, 10)

                HStack(spacing: 8) {
                    Button { dismiss() } label: {
                        Pill(radius: Metric.pill, padH: 20, padV: 9) {
                            Text(t.cancel).font(Typo.nav)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button(action: submit) {
                        Pill(fill: .ember, radius: Metric.pill, padH: 24, padV: 9) {
                            Text(mode == .create ? t.createPw : t.save).font(Typo.nav)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 6)

                Spacer(minLength: 22)
            }
        }
        .frame(width: 440, height: mode == .create ? 480 : 430)
        .onAppear {
            hint = store.passwordHint
            focus = mode == .change ? .current : .pw
        }
    }

    @ViewBuilder
    private func field(_ label: String, _ v: Binding<String>, focus f: Field,
                       secure: Bool = true, hint ph: String = "") -> some View {
        ZStack(alignment: .leading) {
            Group {
                if secure {
                    SecureField("", text: v)
                } else {
                    TextField("", text: v)
                }
            }
            .textFieldStyle(.plain)
            .font(Typo.body)
            .focused($focus, equals: f)
            .onSubmit(submit)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .frame(width: 360)
            .background(RoundedRectangle(cornerRadius: Metric.pill).fill(Color.snow))
            .overlay(RoundedRectangle(cornerRadius: Metric.pill)
                .stroke(Color.ink, lineWidth: Metric.border))

            // 有焦點就讓開——中文輸入法組字階段綁定值還是空的，
            // 提示會跟正在打的字疊在一起（提示問題那一欄最明顯）
            if v.wrappedValue.isEmpty && focus != f {
                Text(ph.isEmpty ? label : ph)
                    .font(ph.isEmpty ? Typo.nav : Typo.caption)
                    .foregroundStyle(Color.ink.opacity(ph.isEmpty ? 1 : 0.4))
                    .padding(.leading, 22)
                    .allowsHitTesting(false)
            }
        }
    }

    /// 舊密碼的驗證交給 `KeyStore`——它會拿舊密碼去拆封主金鑰，拆不開就是打錯了。
    /// **這裡不能自己比對字串**，因為根本沒有一份儲存的密碼可以拿來比。
    private func submit() {
        guard !store.working else { return }
        error = nil

        guard pw.count >= 8 else { error = t.pwTooShort; return }
        guard pw == again else { error = t.pwMismatch; return }

        Task {
            if mode == .create {
                let h = hint.trimmingCharacters(in: .whitespaces)
                guard await store.createVault(password: pw, hint: h) else {
                    error = store.lastError ?? t.pwWrong
                    return
                }
            } else {
                guard !current.isEmpty else { error = t.pwWrong; return }
                guard await store.changePassword(current: current, new: pw) else {
                    error = t.pwWrong
                    return
                }
            }
            dismiss()
        }
    }
}
