import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 雙擊照片打開的檢視窗。看大圖，順便從這裡匯出。
struct PhotoViewer: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let item: Item

    private var t: L { store.t }
    private var image: NSImage? { NSImage(contentsOfFile: item.attachment) }

    var body: some View {
        ZStack {
            Color.peach

            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.name).font(Typo.headingSm).lineLimit(1)
                    Spacer()
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
                            // 只記路徑的後果：原檔被移走或刪掉就開不了
                            Text("找不到原始檔案\n\(item.attachment)")
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
                            Text(t.exportOriginal).font(Typo.nav)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        if item.kind == .video {
                            NSWorkspace.shared.open(URL(fileURLWithPath: item.attachment))
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
    }

    // ── 匯出 ──────────────────────────────────────────
    private func export(thumbnail: Bool) {
        let src = URL(fileURLWithPath: item.attachment)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true

        if thumbnail {
            panel.nameFieldStringValue = "\(item.name)_1024.jpg"
            panel.allowedContentTypes = [.jpeg]
        } else {
            panel.nameFieldStringValue = src.lastPathComponent
            if let ct = UTType(filenameExtension: src.pathExtension) {
                panel.allowedContentTypes = [ct]
            }
        }

        guard panel.runModal() == .OK, let dst = panel.url else { return }

        if thumbnail {
            guard let data = thumbnailJPEG(maxSide: 1024) else { return }
            try? data.write(to: dst)
        } else {
            // 原圖就是原檔，重新編碼只會掉品質
            try? FileManager.default.removeItem(at: dst)
            try? FileManager.default.copyItem(at: src, to: dst)
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
