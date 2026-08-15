import SwiftUI
import Combine

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
        // 兩個 onDismiss 都要有。復原金鑰可能是在設定裡重產的，
        // 也可能是建立保管箱時產生的——哪一張先關就由哪一張放行。
        .sheet(isPresented: $s.showSettings, onDismiss: { store.flushPendingRecovery() }) {
            SettingsSheet().environment(store)
        }
        .sheet(item: $s.pwSheet, onDismiss: { store.flushPendingRecovery() }) { mode in
            PasswordSheet(mode: mode).environment(store)
        }
        .sheet(item: $s.photoViewer) { item in
            PhotoViewer(item: item).environment(store)
        }
        // 復原金鑰只在剛產生的那一刻存在於記憶體裡，關掉這張紙就再也叫不回來
        .sheet(item: $s.freshRecoveryKey) { key in
            RecoveryKeySheet(key: key).environment(store)
        }
        .onAppear {
            Biometrics.diagnose("啟動")
            idle.limit = store.autoLockSeconds
            idle.start {
                guard !store.locked else { return }
                store.lock()
            }
        }
        .onChange(of: store.autoLockSeconds) { _, v in
            idle.limit = v
            store.scheduleSave()
        }
        .onChange(of: store.locked) { _, _ in idle.suspend() }
        // 設定是直接綁在 store 上改的，沒有經過任何方法可以插存檔。
        // 少一行就是那個設定重開之後會跳回預設值。
        .onChange(of: store.touchIDOn) { _, on in
            if !on { Biometrics.forget() }          // 關掉就把 Keychain 那份收回來
            else if let m = store.masterKey, Biometrics.available { Biometrics.enrol(master: m) }
            store.scheduleSave()
        }
        .onChange(of: store.clipboardSeconds) { _, _ in store.scheduleSave() }
        .onChange(of: store.lang) { _, _ in store.scheduleSave() }
        // 延遲存檔還沒寫完就被關掉的話資料就掉了，結束前一定要落地一次
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.willTerminateNotification)) { _ in
            store.saveNow()
            Storage.clearScratch()
        }
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
