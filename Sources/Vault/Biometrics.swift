import Foundation
import LocalAuthentication
import Security

/// Touch ID。
///
/// ## 跟舊版的差別
///
/// 舊版是問系統「這個人通過了沒」，拿到一個布林值就自己決定放不放行。
/// 那種寫法的問題是：**指紋跟資料之間沒有任何關係**。把那個 `if` 改成 `true` 就開了，
/// 或者根本不理會 app、直接拿 `vault.dat` 去別的地方解——反正金鑰又不在指紋手上。
///
/// 現在是主金鑰整把交給 Keychain 保管，標記成「要通過生體認証才交出來」。
/// 認証沒過的話金鑰**根本不會出現**，沒有任何一段程式碼能繞過去，因為要繞的對象
/// 不是這個 app 的判斷式，是 Secure Enclave。
///
/// ## ⚠️ 但這在自簽版本上啟用不了
///
/// `.biometryCurrentSet` 的 Keychain 項目要求 Apple 簽發的憑證，ad-hoc 自簽會拿到
/// `errSecMissingEntitlement`。補 `keychain-access-groups` entitlement 反而讓 app
/// 完全無法啟動（沒有 provisioning profile 背書）。
/// 要啟用只能走 Apple Developer Program → Developer ID 憑證。細節見 README。
///
/// **這一整套邏輯是對的，先留著。** 等正式簽名之後不用改任何一行就會生效。
enum Biometrics {

    private static let service = "com.chiushihbo.vault"
    private static let account = "master-key"

    // ── 這台機器有沒有 ────────────────────────────────
    static var available: Bool {
        let ctx = LAContext()
        var err: NSError?
        return ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
    }

    /// 用不了的時候，**為什麼**用不了。
    ///
    /// 沒有這個的話，Touch ID 那顆按鈕就只是「有時候不見」。實際遇過的情況是
    /// MacBook 闔蓋接外接螢幕——感應器在筆電鍵盤上，蓋著就摸不到，
    /// 系統回 `systemCancel`，而使用者只會覺得是這個 app 壞了。
    static func unavailableReason(_ t: L) -> String? {
        let ctx = LAContext()
        var err: NSError?
        if ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) {
            return nil
        }
        switch err?.code {
        case LAError.biometryNotAvailable.rawValue: return t.bioNoHardware
        case LAError.biometryNotEnrolled.rawValue:  return t.bioNotEnrolled
        case LAError.biometryLockout.rawValue:      return t.bioLockout
        default:                                    return t.bioUnreachable
        }
    }

    static var label: String {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
        else { return "Touch ID" }
        return ctx.biometryType == .touchID ? "Touch ID" : "生体認証"
    }

    /// Keychain 裡到底有沒有存過。**沒存過就不該顯示那顆按鈕**，
    /// 不然使用者按下去驗完指紋卻開不了，會以為是指紋壞了。
    static var enrolled: Bool {
        // 只問「在不在」，不要真的把金鑰拿出來——否則光是畫鎖定畫面就會跳 Touch ID 視窗。
        let ctx = LAContext()
        ctx.interactionNotAllowed = true

        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false,
            kSecUseAuthenticationContext as String: ctx
        ]
        let status = SecItemCopyMatching(q as CFDictionary, nil)
        // 東西在、但需要認証才給 → 就是「存過了」
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    // ── 存 ────────────────────────────────────────────
    /// 把主金鑰交給 Keychain。
    ///
    /// `.biometryCurrentSet` 是關鍵：**只要這台機器的指紋名單有任何變動，這筆就自動作廢。**
    /// 別人拿到你解鎖狀態的電腦、把自己的指紋加進系統設定，也開不了這個保管箱——
    /// 那時候只剩密碼那條路。
    ///
    /// `ThisDeviceOnly` 則是不讓它跟著 iCloud 鑰匙圈跑到別台機器去。
    /// 回傳 OSStatus 而不是 Bool。**失敗的原因必須看得見**——
    /// 只回一個 false 的話，Touch ID 那顆按鈕就只是「有時候不見」，查不出為什麼。
    @discardableResult
    static func enrol(master: Data) -> OSStatus {
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            nil
        ) else { return errSecParam }

        forget()   // 舊的先清掉，SecItemAdd 遇到重複會直接失敗

        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessControl as String: access,
            kSecValueData as String: master
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        lastEnrolStatus = status
        return status
    }

    /// 最後一次註冊的結果，給設定頁顯示用
    nonisolated(unsafe) private(set) static var lastEnrolStatus: OSStatus? = nil

    /// 診斷。Keychain 和 LocalAuthentication 的失敗全是數字代碼，沒有這個只能猜。
    ///
    /// **寫檔案不寫 stderr。** 從終端機直接跑 binary 的話 LocalAuthentication 會回
    /// systemCancel（-4），量到的根本不是正常啟動時的狀態；而用 `open` 啟動就看不到
    /// stderr。所以只能落地成檔案。
    ///
    /// 開關是 `~/.cache/vault-build/VAULT_DEBUG` 這個檔案在不在，正式版不會有。
    static func diagnose(_ stage: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/vault-build")
        guard FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("VAULT_DEBUG").path) else { return }

        let ctx = LAContext()
        var bioErr: NSError?
        let bio = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &bioErr)

        // 含密碼 fallback 的政策。這個也失敗的話代表 LocalAuthentication 整個不通，
        // 而不只是「這台機器的生物辨識用不了」。
        let ctx2 = LAContext()
        var anyErr: NSError?
        let any = ctx2.canEvaluatePolicy(.deviceOwnerAuthentication, error: &anyErr)

        let line = """
            [\(stage)]
              biometrics=\(bio)\(bioErr.map { " err=\($0.code) \($0.localizedDescription)" } ?? "")
              anyAuth=\(any)\(anyErr.map { " err=\($0.code) \($0.localizedDescription)" } ?? "")
              biometryType=\(ctx.biometryType.rawValue)
              enrolled=\(enrolled)
              lastEnrolStatus=\(lastEnrolStatus.map { String($0) } ?? "尚未嘗試")
              bundleID=\(Bundle.main.bundleIdentifier ?? "nil")

            """
        let log = dir.appendingPathComponent("diag.log")
        if let h = try? FileHandle(forWritingTo: log) {
            h.seekToEndOfFile()
            h.write(Data(line.utf8))
            try? h.close()
        } else {
            try? Data(line.utf8).write(to: log)
        }
    }

    // ── 取 ────────────────────────────────────────────
    /// 驗指紋並取回主金鑰。使用者取消或驗不過就回 nil。
    ///
    /// `SecItemCopyMatching` 會**卡住呼叫它的那條執行緒**直到使用者按完，
    /// 所以整段丟到背景去，不然主執行緒被鎖住連 Touch ID 的視窗都畫不出來。
    static func fetchMaster(reason: String) async -> Data? {
        await Task.detached(priority: .userInitiated) { () -> Data? in
            let ctx = LAContext()
            ctx.localizedReason = reason
            ctx.localizedCancelTitle = "取消"

            let q: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecUseAuthenticationContext as String: ctx
            ]
            var out: CFTypeRef?
            guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
                  let data = out as? Data else { return nil }
            return data
        }.value
    }

    static func forget() {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(q as CFDictionary)
    }

    /// 舊版只回答是非題的那個函式。現在只剩「確認本人」的用途
    /// （例如匯出明文前再問一次），**不能拿它當解鎖手段**。
    static func confirm(reason: String) async -> Bool {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "取消"
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
        else { return false }
        return (try? await ctx.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)) ?? false
    }
}
