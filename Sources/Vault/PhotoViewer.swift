import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 雙擊照片打開的檢視窗。看大圖，順便從這裡匯出。
struct PhotoViewer: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let item: Item

    private var t: L { store.t }

    /// 解密後的原始位元組。
    ///
    /// **一定要快取。** 寫成 computed property 的話 SwiftUI 每次重繪都會重跑一次
    /// AES 解密整張圖，捲個畫面就卡死。載一次放著，視窗關掉就跟著消失。
    @State private var plain: Data? = nil
    private var image: NSImage? { plain.flatMap { NSImage(data: $0) } }

    /// 標題的編輯內容。跟設定裡的提示問題同樣的理由：不直接綁 store，
    /// 免得每打一個字就跑一次存檔排程。
    @State private var name = ""

    var body: some View {
        ZStack {
            Color.peach

            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    // 匯入時帶進來的是原檔名，常常是一串 UUID。
                    // 格狀分頁沒有 detail 抽屜，**這裡是唯一能改名字的地方**。
                    //
                    // 底下那條線是在說「這是可以寫的」——這套設計不用灰色也不用陰影，
                    // 沒有線的話它看起來就只是一個標題。
                    TextField("", text: $name)
                        .textFieldStyle(.plain)
                        .font(Typo.headingSm)
                        .lineLimit(1)
                        .onSubmit(rename)
                        .padding(.bottom, 5)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.ink).frame(height: 1.5)
                        }
                        .overlay(alignment: .leading) {
                            if name.isEmpty {
                                Text(t.phName)
                                    .font(Typo.headingSm)
                                    .foregroundStyle(Color.ink.opacity(0.26))
                                    .allowsHitTesting(false)
                            }
                        }

                    Spacer(minLength: 16)
                    Button { dismiss() } label: {
                        Pill(radius: Metric.pill, padH: 16, padV: 6) {
                            Text(t.close).font(Typo.caption)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 14)

                OutlineCard(fill: item.kind == .video ? .powder : .snow) {
                    Group {
                        if item.kind == .video {
                            // 影片不在 app 裡播。內建播放器要處理一堆編碼，
                            // 而系統播放器本來就在那裡。
                            VStack(spacing: 14) {
                                DoodleView(kind: .film, size: 88, stroke: 2.5)
                                Text(item.value).font(Typo.caption)
                            }
                        } else if let img = image {
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .padding(14)
                        } else {
                            // 附件是加密後複製進來的，原檔搬走不影響。
                            // 走到這裡代表 blobs 底下那個檔真的不見了，或是金鑰對不上。
                            Text("這個附件讀不出來")
                                .font(Typo.caption)
                                .multilineTextAlignment(.center)
                                .padding(30)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 24)

                HStack(spacing: 8) {
                    Button { export(thumbnail: false) } label: {
                        Pill(fill: .snow, radius: Metric.pill, padH: 18, padV: 8) {
                            // 「原圖」對一支影片講不通
                            Text(item.kind == .video ? t.exportFile : t.exportOriginal)
                                .font(Typo.nav)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        if item.kind == .video {
                            // 解密成暫存檔再交給系統播放器。上鎖時 `clearScratch()` 會掃掉。
                            if let url = store.materialise(item) {
                                NSWorkspace.shared.open(url)
                            }
                        } else {
                            export(thumbnail: true)
                        }
                    } label: {
                        Pill(fill: .mint, radius: Metric.pill, padH: 18, padV: 8) {
                            Text(item.kind == .video ? t.preview : t.exportThumb).font(Typo.nav)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)

                Text(item.kind == .video ? t.previewNote : t.thumbNote)
                    .font(Typo.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
            }
        }
        .frame(width: 620, height: 640)
        // 影片不預先解密——那可能是好幾 GB，而且使用者不一定會按預覽。
        .onAppear {
            name = item.name
            if item.kind != .video { plain = store.imageData(item) }
        }
        // 關窗時一併寫回，不留一顆要記得按的儲存鈕
        .onDisappear {
            rename()
            plain = nil
        }
    }

    private func rename() {
        store.rename(item.id, to: name.trimmingCharacters(in: .whitespaces))
    }

    // ── 匯出 ──────────────────────────────────────────
    /// **匯出等於把明文放到保管箱外面。** 這是使用者主動要的，但要走存檔面板，
    /// 讓他自己選位置、自己知道那份沒有加密。
    private func export(thumbnail: Bool) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true

        // 用編輯中的 name 不是 item.name——剛改完名字還沒關窗就匯出的話，
        // 檔名應該跟著新的走
        let base = name.trimmingCharacters(in: .whitespaces).isEmpty ? "未命名" : name

        if thumbnail {
            panel.nameFieldStringValue = "\(base)_1024.jpg"
            panel.allowedContentTypes = [.jpeg]
        } else {
            let ext = item.ext.isEmpty ? "dat" : item.ext
            panel.nameFieldStringValue = "\(base).\(ext)"
            if let ct = UTType(filenameExtension: ext) {
                panel.allowedContentTypes = [ct]
            }
        }

        guard panel.runModal() == .OK, let dst = panel.url else { return }

        if thumbnail {
            guard let data = thumbnailJPEG(maxSide: 1024) else { return }
            try? data.write(to: dst)
        } else {
            // 原圖就是解密出來的原始位元組，重新編碼只會掉品質。
            // 影片走這條時才需要現解，前面沒有預先載進記憶體。
            guard let data = plain ?? store.imageData(item) else { return }
            try? data.write(to: dst, options: [.atomic])
        }
    }

    private func thumbnailJPEG(maxSide: CGFloat) -> Data? {
        guard let img = image,
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }

        // 用 pixelsWide/High，不是 img.size——後者是點不是像素，
        // Retina 來源會少一半。
        let w = CGFloat(rep.pixelsWide), h = CGFloat(rep.pixelsHigh)
        let scale = min(1, maxSide / max(w, h))
        let size = NSSize(width: (w * scale).rounded(), height: (h * scale).rounded())

        guard let out = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        out.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        NSGraphicsContext.current?.imageInterpolation = .high
        rep.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()

        return out.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}
