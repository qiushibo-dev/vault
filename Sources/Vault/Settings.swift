import SwiftUI
import AppKit

struct SettingsSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showKey = false
    @State private var copied = false
    @State private var newTag = ""
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

                row(t.sTouchID, t.sTouchIDSub) {
                    Toggle("", isOn: $s.touchIDOn).labelsHidden().toggleStyle(PillToggle())
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
        @Bindable var s = store
        return OutlineCard {
            VStack(spacing: 0) {
                groupTitle(t.gForgot)

                // last: true ——標題說明跟它底下的輸入框是同一件事，
                // 中間畫線會把一個項目切成兩半。
                row(t.sHint, t.sHintSub, last: true) { EmptyView() }

                TextField("", text: $s.passwordHint)
                    .textFieldStyle(.plain)
                    .font(Typo.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: Metric.small).fill(Color.snow))
                    .overlay(RoundedRectangle(cornerRadius: Metric.small)
                        .stroke(Color.ink, lineWidth: Metric.border))
                    .overlay(alignment: .leading) {
                        if store.passwordHint.isEmpty {
                            Text(t.hintPh).font(Typo.caption)
                                .foregroundStyle(Color.ink.opacity(0.4))
                                .padding(.leading, 18)
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                divider

                row(t.sKey, t.sKeySub, last: true) { EmptyView() }

                VStack(spacing: 10) {
                    Text(showKey ? (store.recoveryKey ?? "—")
                                 : "••••-••••-••••-••••-••••-••••")
                        .font(Typo.bodyBold)
                        .kerning(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: Metric.small).fill(Color.sunbeam))
                        .overlay(RoundedRectangle(cornerRadius: Metric.small)
                            .stroke(Color.ink, lineWidth: Metric.border))

                    HStack(spacing: 8) {
                        pillButton(showKey ? t.hide : t.show) { showKey.toggle() }
                        pillButton(copied ? t.copied : t.copy, fill: copied ? .lime : .snow) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(store.recoveryKey ?? "", forType: .string)
                            copied = true
                        }
                        pillButton(t.print) {}
                        Spacer()
                        pillButton(t.regenerate, fill: .ember) {
                            store.regenerateRecoveryKey()
                            showKey = true
                            copied = false
                        }
                    }

                    Text(t.regenWarn)
                        .font(Typo.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
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
                            .overlay(alignment: .leading) {
                                if newTag.isEmpty {
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

                row(t.sICloud, t.sICloudSub) {
                    Toggle("", isOn: $s.icloudSync).labelsHidden().toggleStyle(PillToggle())
                }

                row(t.sClipboard, t.sClipboardSub) {
                    Pill(fill: .powder, radius: Metric.pill, padH: 14, padV: 5) {
                        Text("\(store.clipboardSeconds)s").font(Typo.caption)
                    }
                }

                row(t.sLocation, store.dataPath) {
                    pillButton(t.revealFinder) {}
                }

                row(t.sExport, t.sExportSub, last: true) {
                    pillButton(t.exportBtn) {}
                }
            }
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
