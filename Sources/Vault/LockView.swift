import SwiftUI

/// 鎖定畫面。
///
/// 你 Figma 上是「PASSWORD ＋ 一個框」的極簡版；套上繪本風之後改成
/// 桃色畫布上的一張白卡，四周散落線稿。結構沒變，只是把那個框包進卡片裡。
struct LockView: View {
    @Environment(Store.self) private var store
    @State private var pw = ""
    @State private var key = ""
    @State private var wrong = false
    @State private var recovery = false      // 忘記密碼模式
    @FocusState private var focused: Bool

    private var t: L { store.t }

    var body: some View {
        ZStack {
            Color.peach

            // 散落的塗鴉。刻意不對齊格線，角度都不一樣。
            DoodleView(kind: .key,         size: 92, angle: -18).offset(x: -258, y: -252)
            DoodleView(kind: .lock,        size: 66, angle:  12).offset(x:  268, y: -300)
            DoodleView(kind: .spiral,      size: 54, angle:   0).offset(x:  290, y:  222)
            DoodleView(kind: .star,        size: 40, angle:  14).offset(x: -286, y:  188)
            DoodleView(kind: .eye,         size: 74, angle:  -8).offset(x: -196, y:  310)
            DoodleView(kind: .clip,        size: 60, angle: -14).offset(x:  256, y:   26)

            OutlineCard {
                VStack(spacing: 0) {
                    // VAULT 不翻譯——那是名字，不是標題。
                    Text("VAULT")
                        .font(Typo.display)
                        .kerning(-1)
                        .padding(.top, 40)

                    Text(recovery && store.hasPassword ? t.recoveryTitle : t.subtitle)
                        .font(Typo.body)
                        .padding(.top, 8)

                    if !store.hasPassword {
                        firstRunPane
                    } else if recovery {
                        recoveryPane
                    } else {
                        normalPane
                    }

                    Spacer(minLength: 16)

                    Text("2026 Chiu Shihbo v0.1")
                        .font(Typo.caption)
                        .padding(.bottom, 24)
                }
                .frame(width: 440)
            }
            .frame(width: 440, height: recovery ? 520 : 500)
        }
        .frame(width: Metric.win.width, height: Metric.win.height)
        .onAppear { focused = true }
    }

    // ── 還沒建立過密碼 ────────────────────────────────
    // 這台機器上還沒有保管箱，所以畫面上只有一件事可做。
    private var firstRunPane: some View {
        VStack(spacing: 0) {
            Text(t.createPwSub)
                .font(Typo.caption)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 320)
                .padding(.top, 26)

            Button { store.pwSheet = .create } label: {
                Pill(fill: .ember, padH: 34, padV: 14) {
                    Text(t.createPw).font(Typo.button)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 26)
        }
    }

    // ── 平常 ──────────────────────────────────────────
    private var normalPane: some View {
        VStack(spacing: 0) {
            SecureField("", text: $pw)
                .textFieldStyle(.plain)
                .font(Typo.body)
                .multilineTextAlignment(.center)
                .focused($focused)
                .onSubmit(unlock)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(width: 300)
                .background(RoundedRectangle(cornerRadius: Metric.pill).fill(Color.snow))
                .overlay(RoundedRectangle(cornerRadius: Metric.pill)
                    .stroke(Color.ink, lineWidth: Metric.border))
                .overlay(alignment: .leading) {
                    if pw.isEmpty {
                        Text(t.passwordPh).font(Typo.nav)
                            .padding(.leading, 24).allowsHitTesting(false)
                    }
                }
                .padding(.top, 32)
                .offset(x: wrong ? 8 : 0)

            // Touch ID
            //
            // Figma 上沒有這塊。前面談定的是「密碼當根、Touch ID 當日常路徑」，
            // 所以實際每天按的是這顆。這台機器沒有 Touch ID 的話整顆不出現。
            if store.touchIDOn && Biometrics.available {
                Button(action: unlockBiometric) {
                    Pill(fill: .mint) {
                        HStack(spacing: 10) {
                            DoodleView(kind: .fingerprint, size: 22, stroke: 1.6)
                            Text(t.touchID).font(Typo.nav)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
            }

            Button { withAnimation(.easeOut(duration: 0.2)) { recovery = true } } label: {
                Text(t.forgot).font(Typo.caption).underline()
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
        }
    }

    // ── 忘記密碼 ──────────────────────────────────────
    // 兩段：先給提示（多數時候看一眼就想起來了），想不起來才用復原金鑰。
    private var recoveryPane: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(t.hintTitle).font(Typo.caption)
                Text(store.passwordHint.isEmpty ? "—" : store.passwordHint)
                    .font(Typo.bodyBold)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(width: 330)
            .background(RoundedRectangle(cornerRadius: Metric.small).fill(Color.sunbeam))
            .overlay(RoundedRectangle(cornerRadius: Metric.small)
                .stroke(Color.ink, lineWidth: Metric.border))
            .padding(.top, 24)

            Text(t.useKeyBelow)
                .font(Typo.caption)
                .multilineTextAlignment(.center)
                .frame(width: 340)
                .padding(.top, 18)

            TextField("", text: $key)
                .textFieldStyle(.plain)
                .font(Typo.body)
                .multilineTextAlignment(.center)
                .onSubmit(unlockWithKey)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(width: 330)
                .background(RoundedRectangle(cornerRadius: Metric.pill).fill(Color.snow))
                .overlay(RoundedRectangle(cornerRadius: Metric.pill)
                    .stroke(Color.ink, lineWidth: Metric.border))
                .overlay(alignment: .leading) {
                    if key.isEmpty {
                        Text("XXXX-XXXX-XXXX-XXXX-XXXX-XXXX")
                            .font(Typo.caption)
                            .padding(.leading, 22).allowsHitTesting(false)
                    }
                }
                .padding(.top, 8)
                .offset(x: wrong ? 8 : 0)

            Button { withAnimation(.easeOut(duration: 0.2)) { recovery = false; key = "" } } label: {
                Text(t.backToPw).font(Typo.caption).underline()
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
        }
    }

    // ── 動作 ──────────────────────────────────────────
    /// 現在是比對字串。真正的實作是拿密碼派生金鑰、解得開才算對，
    /// 「比對密碼」這個步驟根本不存在——所以這裡之後會整段換掉。
    private func unlock() {
        guard !pw.isEmpty, pw == store.password else { shake(); pw = ""; return }
        open()
    }

    private func unlockWithKey() {
        let typed = key.uppercased().filter { $0.isLetter || $0.isNumber }
        let real = (store.recoveryKey ?? "").filter { $0.isLetter || $0.isNumber }
        guard !real.isEmpty, typed == real else { shake(); return }
        open()
    }

    private func unlockBiometric() {
        Task {
            let ok = await Biometrics.authenticate(reason: t.subtitle)
            if ok { open() } else { shake() }
        }
    }

    private func open() {
        withAnimation(.easeOut(duration: 0.24)) { store.locked = false }
        pw = ""; key = ""; recovery = false
    }

    private func shake() {
        withAnimation(.default) { wrong = true }
        withAnimation(.easeOut(duration: 0.28).delay(0.06)) { wrong = false }
    }
}
