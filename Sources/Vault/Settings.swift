import SwiftUI
import AppKit

struct SettingsSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var newTag = ""
    @State private var hintText = ""
    @State private var answerText = ""
    @State private var footprint = ""
    /// 剛產生的復原金鑰。只活在這個視窗開著的期間，關掉就沒了——
    /// 它從來沒有被存成明文，這裡是唯一一次能看到它的地方。
    @State private var freshKey: String? = nil
    @State private var copied = false
    @FocusState private var focus: Field?
    private enum Field { case hint, answer, tag }
    @State private var renaming: String? = nil
    @State private var renameText = ""
    @State private var pendingDelete: TagDef? = nil

    private var t: L { store.t }

    var body: some View {
        ZStack {
            Color.peach

            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 14) {
                        unlockGroup
                        recoveryGroup
                        tagGroup
                        dataGroup
                        aboutGroup
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 26)
                }
            }
        }
        .frame(width: 580, height: 720)
        .onAppear {
            hintText = store.passwordHint
            answerText = store.answerPlain
            Task.detached(priority: .utility) {
                let size = Storage.footprint
                await MainActor.run { footprint = size }
            }
        }
        // 提示問題和答案在關窗時一次寫回。沒有「儲存」按鈕是刻意的——
        // 這份設計裡留一顆要記得按的按鈕，遲早會有人改完直接關掉然後以為改好了。
        .onDisappear {
            store.passwordHint = hintText
            // 答案要派生金鑰所以是非同步的。空的就代表「不動現有的設定」，
            // 不是「清掉答案」——清掉要另外做，免得一次沒填就把入口弄丟。
            // 只有真的改過才重設。沒改就重設等於白跑一次金鑰派生，
            // 而且會無謂地換掉 salt。
            let a = answerText
            if a != store.answerPlain, !a.trimmingCharacters(in: .whitespaces).isEmpty {
                Task { await store.setAnswer(a) }
            }
        }
        .alert(pendingDelete.map {
                String(format: t.tagDeleteWarnFmt, $0.name, store.usage($0.name))
               } ?? "",
               isPresented: .init(get: { pendingDelete != nil },
                                  set: { if !$0 { pendingDelete = nil } })) {
            Button(t.cancel, role: .cancel) { pendingDelete = nil }
            Button(t.delete, role: .destructive) {
                if let d = pendingDelete { store.deleteTag(d.id) }
                pendingDelete = nil
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(t.settings).font(Typo.headingSm).kerning(-0.5)
            Spacer()
            Button { dismiss() } label: {
                Pill(radius: Metric.pill, padH: 16, padV: 6) {
                    Text(t.close).font(Typo.caption)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 26)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    // ── 解鎖 ──────────────────────────────────────────
    private var unlockGroup: some View {
        @Bindable var s = store
        return OutlineCard {
            VStack(spacing: 0) {
                groupTitle(t.gUnlock)

                // 說明文字換成**當下的實際狀態**。
                // 開關開著但按鈕不出現是最難查的那種狀況——闔蓋接外接螢幕就會這樣，
                // 使用者只會覺得是這個 app 壞了。
                row(t.sTouchID, touchIDStatus) {
                    Toggle("", isOn: $s.touchIDOn)
                        .labelsHidden()
                        .toggleStyle(PillToggle())
                        .disabled(!touchIDUsable)
                        // 這套設計本來禁用灰色，但一個「撥得動卻沒有作用」的開關比
                        // 破一次色彩規則更糟。用降低不透明度而不是換成灰色，
                        // 至少還是同一支蠟筆。**說明文字保持全黑**——那行字正是在解釋
                        // 為什麼撥不動，把它一起淡掉就本末倒置了。
                        .opacity(touchIDUsable ? 1 : 0.3)
                }

                row(t.sAutoLock, t.sAutoLockSub) {
                    Menu {
                        ForEach(store.autoLockChoices, id: \.0) { sec, label in
                            Button(label) { store.autoLockSeconds = sec }
                        }
                    } label: {
                        Pill(fill: .mint, radius: Metric.pill, padH: 14, padV: 5) {
                            Text(store.autoLockLabel).font(Typo.caption)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }

                row(t.sChangePw, t.sChangePwSub, last: true) {
                    pillButton(t.changeBtn) {
                        dismiss()               // 設定關掉再開表單，兩層 sheet 疊起來會卡住
                        store.pwSheet = .change
                    }
                }
            }
        }
    }

    // ── 救援 ──────────────────────────────────────────
    private var recoveryGroup: some View {
        OutlineCard {
            VStack(spacing: 0) {
                groupTitle(t.gForgot)

                // last: true ——標題說明跟它底下的輸入框是同一件事，
                // 中間畫線會把一個項目切成兩半。
                row(t.sHint, t.sHintSub, last: true) { EmptyView() }

                // 綁本地 state，不直接綁 `store.passwordHint`。
                // 那個屬性讀寫的是金鑰檔，直接綁的話**每打一個字就重寫一次檔案**，
                // 而且它不在 @Observable 的追蹤範圍內，畫面該不該更新變成看運氣。
                TextField("", text: $hintText)
                    .textFieldStyle(.plain)
                    .font(Typo.body)
                    .focused($focus, equals: .hint)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: Metric.small).fill(Color.snow))
                    .overlay(RoundedRectangle(cornerRadius: Metric.small)
                        .stroke(Color.ink, lineWidth: Metric.border))
                    .overlay(alignment: .leading) {
                        // **要看焦點不能只看空值。**中文輸入法組字階段綁定值還是空的，
                        // 提示文字會跟正在組的那個字疊在一起。
                        if hintText.isEmpty && focus != .hint {
                            Text(t.hintPh).font(Typo.caption)
                                .foregroundStyle(Color.ink.opacity(0.4))
                                .padding(.leading, 18)
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                divider

                // 答案。**欄位一定是空的**——存的是被答案包裝過的主金鑰，
                // 不是答案本身，所以還原不出來給你看。填了就是換一組新的。
                row(t.sAnswer, t.sAnswerSub, last: true) { EmptyView() }

                // **明碼不遮點點。** 答案設錯了就等於少一條救援路徑，
                // 而使用者沒辦法從一排圓點看出自己打錯字。這一欄是在「已經解鎖」
                // 的狀態下填的，遮起來擋不到任何人。
                TextField("", text: $answerText)
                    .textFieldStyle(.plain)
                    .font(Typo.body)
                    .focused($focus, equals: .answer)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: Metric.small).fill(Color.snow))
                    .overlay(RoundedRectangle(cornerRadius: Metric.small)
                        .stroke(Color.ink, lineWidth: Metric.border))
                    .overlay(alignment: .leading) {
                        if answerText.isEmpty && focus != .answer {
                            Text(store.hasAnswer ? t.answerSaved : t.answerPh)
                                .font(Typo.caption)
                                .foregroundStyle(Color.ink.opacity(0.4))
                                .padding(.leading, 18)
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                divider

                row(t.sKey, t.sKeySub, last: true) { EmptyView() }

                // 平常是一排點：金鑰檔存的是「被這串字包裝過的主金鑰」，不是這串字本身，
                // 所以還原不出來。剛產生的那一次才有實體可以顯示——**就地展開**，
                // 不關窗也不開新視窗，按下去就出現。
                VStack(spacing: 10) {
                    Text(freshKey ?? "••••-••••-••••-••••-••••-••••")
                        .font(Typo.bodyBold)
                        .kerning(1)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: Metric.small)
                            .fill(freshKey == nil ? Color.sunbeam : Color.lime))
                        .overlay(RoundedRectangle(cornerRadius: Metric.small)
                            .stroke(Color.ink, lineWidth: Metric.border))

                    HStack(spacing: 8) {
                        if freshKey != nil {
                            pillButton(copied ? t.copied : t.copy, fill: copied ? .lime : .snow) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(freshKey ?? "", forType: .string)
                                copied = true
                            }
                        }
                        Spacer()
                        pillButton(store.working ? t.busy : t.regenerate, fill: .ember) {
                            guard !store.working else { return }
                            copied = false
                            Task { freshKey = await store.regenerateRecoveryKey() }
                        }
                    }

                    Text(freshKey == nil ? t.recoveryGone : t.recoveryOnce)
                        .font(Typo.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if freshKey != nil {
                        Text(t.regenWarn)
                            .font(Typo.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .animation(.easeOut(duration: 0.18), value: freshKey == nil)
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
        }
    }

    // ── 標籤 ──────────────────────────────────────────
    private var tagGroup: some View {
        OutlineCard {
            VStack(spacing: 0) {
                groupTitle(t.gTags)

                VStack(spacing: 9) {
                    ForEach(store.tagList) { tag in
                        tagRow(tag)
                    }

                    // 新增
                    HStack(spacing: 10) {
                        Circle().fill(Color.snow)
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(Color.ink,
                                style: StrokeStyle(lineWidth: Metric.border, dash: [3, 3])))
                        TextField("", text: $newTag)
                            .textFieldStyle(.plain)
                            .font(Typo.body)
                            .focused($focus, equals: .tag)
                            .overlay(alignment: .leading) {
                                if newTag.isEmpty && focus != .tag {
                                    Text(t.tagAddPh).font(Typo.body)
                                        .foregroundStyle(Color.ink.opacity(0.3))
                                        .allowsHitTesting(false)
                                }
                            }
                            .onSubmit {
                                store.addTag(newTag)
                                newTag = ""
                            }
                    }
                    .padding(.top, 3)

                    Text(t.tagColourHint)
                        .font(Typo.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
        }
    }

    private func tagRow(_ tag: TagDef) -> some View {
        HStack(spacing: 10) {
            // 色塊。點一下換一支蠟筆。
            Button { store.cycleTagColour(tag.id) } label: {
                Circle().fill(tag.swatch)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(Color.ink, lineWidth: Metric.border))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if renaming == tag.id {
                TextField("", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(Typo.body)
                    .onSubmit {
                        store.renameTag(tag.id, to: renameText)
                        renaming = nil
                    }
                    .onExitCommand { renaming = nil }
            } else {
                Text(tag.name).font(Typo.body)
                let n = store.usage(tag.name)
                Text(n == 0 ? t.tagUnused : String(format: t.tagUsedFmt, n))
                    .font(Typo.caption)
                    .opacity(0.65)
            }

            Spacer()

            if renaming != tag.id {
                pillButton(t.rename) {
                    renameText = tag.name
                    renaming = tag.id
                }
                pillButton(t.delete) { pendingDelete = tag }
            }
        }
    }

    // ── 資料 ──────────────────────────────────────────
    private var dataGroup: some View {
        @Bindable var s = store
        return OutlineCard {
            VStack(spacing: 0) {
                groupTitle(t.gData)

                row(t.sLanguage, t.sLanguageSub) {
                    HStack(spacing: 6) {
                        ForEach(Lang.allCases) { l in
                            Button { store.lang = l } label: {
                                Pill(fill: store.lang == l ? .lilac : .snow,
                                     radius: Metric.pill, padH: 12, padV: 5) {
                                    Text(l.short).font(Typo.caption)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // 開關拿掉了。**能撥動的開關等於承諾它有作用**，
                // 而 iCloud 同步整段還沒接——留著只會讓人以為資料已經備份在雲端。
                row(t.sICloud, t.sICloudSub) {
                    Pill(fill: .powder, radius: Metric.pill, padH: 14, padV: 5) {
                        Text(t.notYet).font(Typo.caption)
                    }
                }

                row(t.sClipboard, t.sClipboardSub) {
                    Pill(fill: .powder, radius: Metric.pill, padH: 14, padV: 5) {
                        Text("\(store.clipboardSeconds)s").font(Typo.caption)
                    }
                }

                // footprint 走訪整個目錄，**不能寫在 body 裡**——每次重繪都會再掃一遍。
                // 開設定時算一次就夠了。
                row(t.sLocation, footprint.isEmpty ? store.dataPath
                                                   : "\(store.dataPath)　（\(footprint)）") {
                    pillButton(t.revealFinder) {
                        NSWorkspace.shared.selectFile(
                            VaultPaths.data.path,
                            inFileViewerRootedAtPath: VaultPaths.dir.path)
                    }
                }

                row(t.sExport, t.sExportSub, last: true) {
                    pillButton(store.working ? t.busy : t.exportBtn) { exportPlaintext() }
                }
            }
        }
    }

    /// 這台機器 ＋ 這個版本，Touch ID 到底撥得動撥不動。
    ///
    /// **不能寫成 `Biometrics.enrolled`。** 使用者把開關關掉時金鑰會從 Keychain 收回，
    /// enrolled 變 false，開關就會自己鎖死再也開不回來。
    /// 判斷依據是「有沒有嘗試過而且失敗」，不是「現在有沒有註冊」。
    private var touchIDUsable: Bool {
        guard Biometrics.unavailableReason(t) == nil else { return false }
        if let s = Biometrics.lastEnrolStatus, s != errSecSuccess { return false }
        return true
    }

    /// Touch ID 那一列的說明文字：用不了就講為什麼，能用就說已就緒。
    private var touchIDStatus: String {
        if let reason = Biometrics.unavailableReason(t) { return reason }
        if Biometrics.enrolled { return t.bioReady }
        // 生物辨識保護的 Keychain 項目需要 Apple 簽發的憑證。
        // ad-hoc 簽名會被系統以 errSecMissingEntitlement 擋下來，
        // 而**補上 entitlement 之後 app 會整個無法啟動**（沒有 profile 背書），
        // 所以這是死路，不是設定問題。
        if Biometrics.lastEnrolStatus == errSecMissingEntitlement { return t.bioNeedsSigning }
        return t.sTouchIDSub
    }

    // ── 匯出 ──────────────────────────────────────────
    /// 把保管箱的內容倒成一個**沒有加密**的資料夾。
    ///
    /// 這是備份和搬家的唯一出路（加密的好處就是別的路都走不通），
    /// 但它同時也是繞過整套加密最快的方法，所以：先明講、再驗一次身分、
    /// 而且產出的資料夾名稱裡就寫著「未加密」。
    private func exportPlaintext() {
        guard !store.working else { return }

        let warn = NSAlert()
        warn.messageText = "匯出的內容沒有加密"
        warn.informativeText = "會產生一個任何人都讀得開的資料夾，裡面是所有密碼、文件和照片的原始內容。確定要繼續嗎？"
        warn.addButton(withTitle: "繼續")
        warn.addButton(withTitle: t.cancel)
        warn.alertStyle = .warning
        guard warn.runModal() == .alertFirstButtonReturn else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = t.exportBtn
        guard panel.runModal() == .OK, let dir = panel.url else { return }

        Task {
            // Touch ID 在這裡是**確認本人**，不是解鎖——保管箱早就開著了。
            // 這道關卡防的是「人離開座位、螢幕沒鎖」的那種場合。
            if Biometrics.available {
                guard await Biometrics.confirm(reason: "匯出未加密的內容") else { return }
            }
            await store.exportPlaintext(to: dir)
        }
    }

    // ── 關於 ──────────────────────────────────────────
    private var aboutGroup: some View {
        OutlineCard {
            HStack(alignment: .center, spacing: 14) {
                DoodleView(kind: .lock, size: 34, stroke: 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Vault \(store.version)").font(Typo.bodyBold)
                    Text("2026 Chiu Shihbo").font(Typo.caption)
                }
                Spacer()

                switch store.updateState {
                case .idle, .failed:
                    pillButton(t.checkUpdate) {
                        Task { await store.checkUpdate() }
                    }
                case .checking:
                    Pill(radius: Metric.pill, padH: 14, padV: 5) {
                        Text(t.checking).font(Typo.caption)
                    }
                case .latest:
                    Pill(fill: .lime, radius: Metric.pill, padH: 14, padV: 5) {
                        Text(t.isLatest).font(Typo.caption)
                    }
                case .available(let tag):
                    // 不在 app 裡下載安裝，開瀏覽器到 releases 頁
                    Button {
                        if let u = URL(string: Store.releasesURL) { NSWorkspace.shared.open(u) }
                    } label: {
                        Pill(fill: .ember, radius: Metric.pill, padH: 14, padV: 5) {
                            Text("\(t.newVersion) \(tag)").font(Typo.caption)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .overlay(alignment: .bottomTrailing) {
                // 失敗不要默默吞掉——要分得出是離線還是 GitHub 那邊的問題
                if case .failed(let msg) = store.updateState {
                    Text(msg)
                        .font(Typo.caption)
                        .lineLimit(2)
                        .frame(maxWidth: 300, alignment: .trailing)
                        .padding(.trailing, 20)
                        .padding(.bottom, 3)
                }
            }
        }
    }

    // ── 零件 ──────────────────────────────────────────
    private func groupTitle(_ s: String) -> some View {
        Text(s)
            .font(Typo.tag)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)
    }

    private var divider: some View {
        Rectangle().fill(Color.ink).frame(height: 1.5).padding(.horizontal, 14)
    }

    @ViewBuilder
    private func row<C: View>(_ title: String, _ sub: String, last: Bool = false,
                              @ViewBuilder trailing: () -> C) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Typo.body)
                Text(sub).font(Typo.caption).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            trailing().padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)

        if !last { divider }
    }

    private func pillButton(_ label: String, fill: Color = .snow,
                            _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Pill(fill: fill, radius: Metric.pill, padH: 14, padV: 5) {
                Text(label).font(Typo.caption)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// ── 藥丸開關 ──────────────────────────────────────────
// 系統的 Toggle 是藍色圓角，跟這套語言完全不搭（那是整個畫面唯一會出現的 iOS 藍）。
struct PillToggle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: Metric.pill)
                    .fill(configuration.isOn ? Color.lime : Color.snow)
                    .frame(width: 54, height: 30)
                    .overlay(RoundedRectangle(cornerRadius: Metric.pill)
                        .stroke(Color.ink, lineWidth: Metric.border))
                Circle()
                    .fill(Color.snow)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().stroke(Color.ink, lineWidth: Metric.border))
                    .padding(.horizontal, 5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.16), value: configuration.isOn)
    }
}
