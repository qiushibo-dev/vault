import SwiftUI
import AppKit

struct MainView: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var s = store
        ZStack {
            Color.peach

            VStack(spacing: 0) {
                tabs.padding(.top, 26)
                paper.padding(.top, 18)
                bottom.padding(.top, 18)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 26)
        }
        .frame(width: Metric.win.width, height: Metric.win.height)
    }

    // ── 分頁 ──────────────────────────────────────────
    // Figma 上是相疊的資料夾標籤，這裡改成藥丸列。
    // 繪本風不用相疊分頁（那需要陰影或缺口才讀得出層次，而這套語言禁用陰影）。
    private var tabs: some View {
        HStack(spacing: 8) {
            ForEach(Tab.allCases) { t in
                Button {
                    store.tab = t
                    store.expanded = nil
                } label: {
                    Pill(fill: store.tab == t ? colour(t) : .snow) {
                        Text(t.label).font(Typo.nav)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private func colour(_ t: Tab) -> Color {
        switch t {
        case .passwords: .ember
        case .documents: .mint
        case .photos:    .lilac
        case .videos:    .powder
        }
    }

    // ── 紙 ────────────────────────────────────────────
    private var paper: some View {
        OutlineCard {
            ScrollView {
                if store.tab.isGrid {
                    mediaGrid
                } else {
                    rows
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Metric.card))
        }
        .frame(maxHeight: .infinity)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(store.rows(for: store.tab)) { item in
                if let b = store.binding(item.id) {
                    Row(item: b, expanded: store.expanded == item.id)
                }
            }
            NewRow(kind: Item.kind(for: store.tab))
        }
        .padding(.vertical, 6)
    }

    /// 照片和影片共用。照片顯示縮圖，影片顯示底片 icon——
    /// 抽第一幀要 AVFoundation 而且每格都要解一次，這個規模不值得。
    private var mediaGrid: some View {
        let kind = Item.kind(for: store.tab)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14,
                                                           alignment: .top), count: 3),
                         alignment: .center, spacing: 16) {
            ForEach(store.rows(for: store.tab)) { item in
                PhotoCell(caption: item.name) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Metric.small)
                            .fill(item.kind == .video ? Color.powder : Color.peach)
                        if item.kind == .video {
                            DoodleView(kind: .film, size: 54, stroke: 2)
                        } else if let img = store.thumbnail(item) {
                            // **`Color.clear` 這層不能省。**
                            //
                            // 直接放 `Image.resizable().aspectRatio(.fill)` 的話，圖片會回報
                            // 一個「填滿後」的尺寸當作自己的大小，ZStack 跟著被撐大，
                            // 於是外面那個 clipShape 裁的是已經變大的範圍——等於沒裁。
                            // 非正方形的照片就這樣壓到隔壁格子上。
                            //
                            // Color.clear 是可伸縮的，它把格子的實際尺寸定下來，
                            // 圖片以 overlay 疊上去、溢出的部分由 clipped() 切掉。
                            Color.clear
                                .overlay(
                                    Image(nsImage: img)
                                        .resizable()
                                        .scaledToFill()
                                )
                                .clipped()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Metric.small))
                    .overlay(RoundedRectangle(cornerRadius: Metric.small)
                        .stroke(Color.ink, lineWidth: Metric.border))
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { store.photoViewer = item }
                    .contextMenu {
                        Button(store.t.delete) { store.delete(item.id) }
                    }
                }
            }
            // 上傳。標題留空但保留同一份結構，否則格線置中會讓它跟旁邊錯開。
            PhotoCell(caption: "") {
                Button { store.pickFiles(kind) } label: {
                    RoundedRectangle(cornerRadius: Metric.small)
                        .stroke(Color.ink, style: StrokeStyle(lineWidth: Metric.border, dash: [7, 6]))
                        .overlay(Text("＋").font(Typo.headingSm))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
    }

    // ── 底部 ──────────────────────────────────────────
    private var bottom: some View {
        HStack {
            Button { store.showSettings = true } label: {
                ZStack {
                    DoodleShape(kind: .gear)
                        .fill(Color.sunbeam, style: FillStyle(eoFill: true))
                    DoodleShape(kind: .gear)
                        .stroke(Color.ink, style: StrokeStyle(lineWidth: Metric.border,
                                                              lineJoin: .round))
                }
                .frame(width: 48, height: 48)
                // 齒輪是不規則形狀，Shape 只有實心處吃得到點擊，
                // 點在齒縫或中心孔就沒反應。（Babos 的重要度圓點踩過同一個坑。）
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            // Figma 上這裡是 Save。
            // 但每一格離開焦點就已經寫進去了，留一顆「希望你別忘記按」的按鈕
            // 遲早會丟資料，所以換成離開電腦時真正會用到的動作。
            Button { store.lock() } label: {
                Pill(fill: .ember, padH: 30, padV: 13) {
                    Text(store.t.lockNow).font(Typo.button)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// ── 照片格 ────────────────────────────────────────────
// 有標題和沒標題的格子必須共用同一份結構，否則在格線裡會上下錯開。
private struct PhotoCell<C: View>: View {
    let caption: String
    @ViewBuilder var thumb: C

    var body: some View {
        VStack(spacing: 7) {
            thumb.aspectRatio(1, contentMode: .fit)
            // 高度必須寫死。日文標題走 Noto、空標題走 Manrope，兩者行高不同，
            // 格子高度就跟著不同；方框是 aspectRatio fit，會在多出來的空間裡
            // 自己置中，看起來就是往下掉一截。
            Text(caption.isEmpty ? " " : caption)
                .font(Typo.caption)
                .lineLimit(1)
                .frame(height: 17)
        }
    }
}

// ── 一列 ──────────────────────────────────────────────
private struct Row: View {
    @Environment(Store.self) private var store
    @Binding var item: Item
    let expanded: Bool

    @FocusState private var focus: Field?
    private enum Field { case name, username, value }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TextField("", text: $item.name)
                    .textFieldStyle(.plain)
                    .font(Typo.row)
                    .frame(width: Metric.col, alignment: .leading)
                    .focused($focus, equals: .name)
                    .overlay(alignment: .leading) {
                        ghost(item.name, store.t.phName, Typo.row, focused: focus == .name)
                    }

                divider

                // 帳號欄**只有密碼分頁有**。文件那頁的中欄放帳號沒有意義，
                // 硬要一致反而是浪費一整欄的寬度。
                if item.kind == .password {
                    TextField("", text: $item.username)
                        .textFieldStyle(.plain)
                        .font(Typo.rowValue)
                        .frame(width: Metric.col, alignment: .leading)
                        .focused($focus, equals: .username)
                        .overlay(alignment: .leading) {
                            ghost(item.username, store.t.phUser, Typo.rowValue,
                                  focused: focus == .username)
                        }

                    divider
                }

                TextField("", text: $item.value)
                    .textFieldStyle(.plain)
                    .font(Typo.rowValue)
                    .focused($focus, equals: .value)
                    .overlay(alignment: .leading) {
                        ghost(item.value,
                              item.kind == .password ? store.t.phSecret : store.t.phFileMeta,
                              Typo.rowValue, focused: focus == .value)
                    }

                Button { store.toggleDetail(item.id) } label: {
                    Pill(fill: expanded ? .sunbeam : .snow,
                         radius: Metric.pill, padH: 14, padV: 5) {
                        Text(store.t.detail).font(Typo.caption)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button { store.delete(item.id) } label: {
                    Text("✕").font(Typo.body)
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
            }
            .padding(.horizontal, 22)
            .frame(height: 54)

            if expanded { Drawer(item: $item) }

            Rectangle().fill(Color.ink).frame(height: 1.5)
                .padding(.horizontal, 16)
        }
    }

    /// 欄與欄之間那條直線。三欄之後要用兩次，抽出來免得兩條長得不一樣。
    private var divider: some View {
        Rectangle().fill(Color.ink)
            .frame(width: 1.5, height: 26)
            .padding(.horizontal, 14)
    }
}

/// 空欄位的淺灰提示。SwiftUI 的 TextField 沒有可上色的 placeholder，
/// 只能自己疊一層——而且要 allowsHitTesting(false)，不然點不進去。
///
/// **`focused` 這個參數不能省。**
/// 中文輸入法在組字階段（打了注音還沒選字）綁定的值仍然是空字串，
/// 光看 `value.isEmpty` 會以為使用者還沒開始打，於是提示文字繼續留在原地，
/// 跟正在組的那個字疊在一起。有焦點就代表人已經在打了，提示該讓開。
@ViewBuilder
private func ghost(_ value: String, _ text: String, _ font: Font, focused: Bool = false) -> some View {
    if value.isEmpty && !focused {
        Text(text)
            .font(font)
            .foregroundStyle(Color.ink.opacity(0.26))
            .allowsHitTesting(false)
    }
}

// ── 空白列＝新增 ──────────────────────────────────────
// 橫線紙本來就有這個好處：往下一行開始寫就是加一筆，不需要「＋」按鈕。
/// **結構必須跟 `Row` 一模一樣**：一樣的 150 寬左欄、一樣的分隔線、一樣的兩個灰字提示。
///
/// 舊版是一整條橫跨的輸入框配一句「在這裡寫下一筆…」。第一次打開 app 的時候
/// 清單是空的，畫面上就只有那一條——**看不出這一列有兩欄，也不知道右邊要填什麼**。
/// 空白列要能當範例看，照著上面那些列的樣子長才行。
private struct NewRow: View {
    @Environment(Store.self) private var store
    let kind: Item.Kind

    @State private var name = ""
    @State private var username = ""
    @State private var value = ""
    @FocusState private var focus: Field?

    private enum Field { case name, username, value }

    var body: some View {
        HStack(spacing: 0) {
            TextField("", text: $name)
                .textFieldStyle(.plain)
                .font(Typo.row)
                .frame(width: Metric.col, alignment: .leading)
                .focused($focus, equals: .name)
                .overlay(alignment: .leading) {
                    ghost(name, store.t.phName, Typo.row, focused: focus == .name)
                }
                // 名稱打完往右跳，不是直接建一筆半空的
                .onSubmit { focus = kind == .password ? .username : .value }

            divider

            if kind == .password {
                TextField("", text: $username)
                    .textFieldStyle(.plain)
                    .font(Typo.rowValue)
                    .frame(width: Metric.col, alignment: .leading)
                    .focused($focus, equals: .username)
                    .overlay(alignment: .leading) {
                        ghost(username, store.t.phUser, Typo.rowValue, focused: focus == .username)
                    }
                    .onSubmit { focus = .value }

                divider
            }

            TextField("", text: $value)
                .textFieldStyle(.plain)
                .font(Typo.rowValue)
                .focused($focus, equals: .value)
                .overlay(alignment: .leading) {
                    ghost(value,
                          kind == .password ? store.t.phSecret : store.t.phFileMeta,
                          Typo.rowValue, focused: focus == .value)
                }
                .onSubmit(commit)

            // 打完之後右邊是空的，沒有任何東西說明下一步——**人就卡在那裡**。
            // 上面每一列的同一個位置都有 detail 和 ✕，這一列不能只有空白。
            //
            // 只在有輸入時出現：空白列已經掛了兩個灰字提示，再加第三個會太吵，
            // 而且沒東西的時候按 Enter 本來就不會發生任何事。
            if !name.isEmpty || !username.isEmpty || !value.isEmpty {
                Text(store.t.enterHint)
                    .font(Typo.caption)
                    .foregroundStyle(Color.ink.opacity(0.3))
                    .allowsHitTesting(false)
                    .padding(.leading, 12)
                    .transition(.opacity)
            }

            // 文件是從硬碟來的，光靠打字建不出一筆，所以這裡要有入口。
            if kind == .document {
                Button { store.pickFiles(.document) } label: {
                    Pill(fill: .mint, radius: Metric.pill, padH: 13, padV: 4) {
                        Text("＋ \(store.t.addFile)").font(Typo.caption)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
            }
        }
        .padding(.horizontal, 22)
        .frame(height: 54)
        .animation(.easeOut(duration: 0.15),
                   value: name.isEmpty && username.isEmpty && value.isEmpty)
    }

    private var divider: some View {
        Rectangle().fill(Color.ink)
            .frame(width: 1.5, height: 26)
            .padding(.horizontal, 14)
    }

    /// 任一欄有東西就成立。只寫名稱之後再回頭補密碼是很正常的用法。
    private func commit() {
        let n = name.trimmingCharacters(in: .whitespaces)
        let u = username.trimmingCharacters(in: .whitespaces)
        let v = value.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty || !u.isEmpty || !v.isEmpty else { return }
        store.append(kind, name: n, username: u, value: v)
        name = ""; username = ""; value = ""
        focus = .name
    }
}

// ── detail 抽屜 ───────────────────────────────────────
private struct Drawer: View {
    @Environment(Store.self) private var store
    @Binding var item: Item

    var body: some View {
        VStack(spacing: 0) {
            field(store.t.fURL, $item.url)
            field(store.t.fNote, $item.note)
            HStack(spacing: 0) {
                Text(store.t.fTags).font(Typo.caption).frame(width: 62, alignment: .leading)
                HStack(spacing: 7) {
                    // 顏色來自設定裡的標籤管理，不是這裡指定的
                    ForEach(item.tags, id: \.self) { name in
                        Pill(fill: store.colour(ofTag: name),
                             radius: Metric.pill, padH: 12, padV: 3) {
                            Text(name).font(Typo.caption)
                        }
                    }
                    Menu {
                        ForEach(store.tagList) { tag in
                            if !item.tags.contains(tag.name) {
                                Button(tag.name) { item.tags.append(tag.name) }
                            }
                        }
                        if !item.tags.isEmpty {
                            Divider()
                            ForEach(item.tags, id: \.self) { name in
                                Button("✕ \(name)") { item.tags.removeAll { $0 == name } }
                            }
                        }
                    } label: {
                        Pill(radius: Metric.pill, padH: 12, padV: 3) {
                            Text("＋").font(Typo.caption)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                Spacer()
            }
            .padding(.vertical, 7)

            // 附件走檔案選擇器，不用拖也不用打字——路徑本來就不是手打的東西。
            HStack(spacing: 0) {
                Text(store.t.fAttach).font(Typo.caption).frame(width: 62, alignment: .leading)
                if item.attachment.isEmpty {
                    Button { pickAttachment() } label: {
                        Pill(fill: .mint, radius: Metric.pill, padH: 13, padV: 4) {
                            Text("＋ \(store.t.addFile)").font(Typo.caption)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    // 附件已經加密複製進保管箱，這裡沒有路徑可以顯示了。
                    // 顯示的是使用者自己給的名字加上原本的副檔名。
                    Text(item.ext.isEmpty ? item.name : "\(item.name).\(item.ext)")
                        .font(Typo.body)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button { detachFile() } label: {
                        Text("✕").font(Typo.caption)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 10)
                }
                Spacer()
            }
            .padding(.vertical, 7)
        }
        .padding(.horizontal, 22)
        .padding(.top, 4)
        .padding(.bottom, 14)
    }

    /// 選檔之後**整份加密複製進保管箱**，存下來的是編號不是路徑。
    private func pickAttachment() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.attach(url, to: item.id)
    }

    /// 拿掉附件時要把密文一起刪掉，否則 blobs 底下會囤一堆再也沒人指向的檔案。
    private func detachFile() {
        Storage.deleteBlob(item.attachment)
        item.attachment = ""
        item.ext = ""
    }

    private func field(_ label: String, _ v: Binding<String>, hint: String = "") -> some View {
        HStack(spacing: 0) {
            Text(label).font(Typo.caption).frame(width: 62, alignment: .leading)
            TextField("", text: v)
                .textFieldStyle(.plain)
                .font(Typo.body)
                .overlay(alignment: .leading) {
                    if v.wrappedValue.isEmpty && !hint.isEmpty {
                        Text(hint).font(Typo.body)
                            .foregroundStyle(Color.ink.opacity(0.28))
                            .allowsHitTesting(false)
                    }
                }
        }
        .padding(.vertical, 7)
    }
}
