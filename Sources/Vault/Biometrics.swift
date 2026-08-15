import Foundation
import LocalAuthentication

/// Touch ID。
///
/// 現在只做到「問系統這個人通過了沒」，拿到的是一個是非題。
/// **正式版不能只信這個布林值**——正確的做法是把主金鑰存進 Keychain 並標記
/// `.biometryCurrentSet`，由 Secure Enclave 決定要不要把金鑰交出來。
/// 驗證失敗時金鑰根本不會出現，而不是 app 自己判斷要不要放行。
enum Biometrics {
    /// 這台機器有沒有 Touch ID，而且已經註冊過指紋
    static var available: Bool {
        let ctx = LAContext()
        var err: NSError?
        return ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
    }

    /// 系統對這台機器的說法（Touch ID／Optic ID／沒有）
    static var label: String {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
        else { return "Touch ID" }
        return ctx.biometryType == .touchID ? "Touch ID" : "生體認証"
    }

    static func authenticate(reason: String) async -> Bool {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "取消"
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
        else { return false }
        return (try? await ctx.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)) ?? false
    }
}
