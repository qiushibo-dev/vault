import SwiftUI

@main
struct VaultApp: App {
    @State private var store = Store()

    var body: some Scene {
        Window("Vault", id: "main") {
            ContentView()
                .environment(store)
                .frame(width: Metric.win.width, height: Metric.win.height)
                // DESIGN.md 是 light-only。不鎖住的話系統在深色模式時
                // SwiftUI 的預設文字色會變白，白卡上整片消失。
                .preferredColorScheme(.light)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("立即上鎖") { store.lock() }
                    .keyboardShortcut("l", modifiers: [.command, .control])
            }
        }
    }
}

struct ContentView: View {
    @Environment(Store.self) private var store
    @State private var idle = IdleLock()

    var body: some View {
        @Bindable var s = store
        ZStack {
            if store.locked {
                LockView().transition(.opacity)
            } else {
                MainView().transition(.opacity)
            }
        }
        .frame(width: Metric.win.width, height: Metric.win.height)
        .background(Color.peach)
        .sheet(isPresented: $s.showSettings) {
            SettingsSheet().environment(store)
        }
        .sheet(item: $s.pwSheet) { mode in
            PasswordSheet(mode: mode).environment(store)
        }
        .sheet(item: $s.photoViewer) { item in
            PhotoViewer(item: item).environment(store)
        }
        .onAppear {
            idle.limit = store.autoLockSeconds
            idle.start {
                guard !store.locked else { return }
                store.lock()
            }
        }
        .onChange(of: store.autoLockSeconds) { _, v in idle.limit = v }
        .onChange(of: store.locked) { _, _ in idle.suspend() }
        // 視窗沒有標題列，所以整片背景都要能拖動視窗
        .background(WindowDragArea())
    }
}

/// 隱藏標題列之後，用一層透明的 NSView 讓整個視窗可以拖。
private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ v: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with e: NSEvent) {
            window?.performDrag(with: e)
        }
        // 讓上層的輸入框先吃到點擊
        override func hitTest(_ p: NSPoint) -> NSView? { nil }
    }
}
