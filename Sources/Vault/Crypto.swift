import Foundation
import CryptoKit
import CommonCrypto

/// 加密的最底層。這裡只做三件事：產生亂數、把密碼變成金鑰、用金鑰封裝／拆封資料。
///
/// **這一層不認識「密碼對不對」這個概念。**
/// 密碼錯的表現是拆封失敗（AES-GCM 的驗證標籤對不上），不是某個比對回傳 false。
/// 所以整個 app 裡不存在「儲存起來的密碼」這種東西可以被偷。
enum Crypto {

    /// PBKDF2 的迭代次數。
    ///
    /// 這個數字唯一的用途就是讓「猜密碼」變慢——合法使用者一次解鎖多等 0.3 秒無感，
    /// 想暴力破解的人每猜一次都要付同樣的代價。
    /// **寫死不能改**：改了之後既有的 vault 就派生不出同一把金鑰，等於資料全鎖死。
    /// 真要調整必須連帶做版本遷移（讀舊參數解開 → 用新參數重包）。
    static let iterations: UInt32 = 600_000

    /// 金鑰長度，AES-256
    static let keyBytes = 32

    // ── 亂數 ──────────────────────────────────────────
    /// 走系統的密碼學亂數源。**不要用 `Int.random(in:)` 之類的東西產金鑰**，
    /// 那些是給遊戲用的，可預測。
    static func randomBytes(_ count: Int) -> Data {
        var d = Data(count: count)
        let status = d.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!)
        }
        precondition(status == errSecSuccess, "系統亂數源失效")
        return d
    }

    // ── 密碼 → 金鑰 ───────────────────────────────────
    /// PBKDF2-HMAC-SHA256。
    ///
    /// 同樣的密碼配同樣的 salt 一定得到同樣的金鑰，這是它能用來解鎖的原因。
    /// salt 的作用是讓兩個人用同一組密碼也派生出不同金鑰，所以每個 vault 一組、隨機、明文存無妨。
    ///
    /// 這個函式會跑滿 600,000 次雜湊，**絕對不要在主執行緒呼叫**，畫面會整個凍住。
    static func derive(password: String, salt: Data, iterations: UInt32 = Crypto.iterations) throws -> Data {
        var out = [UInt8](repeating: 0, count: keyBytes)

        let status: Int32 = password.withCString { pw in
            salt.withUnsafeBytes { saltBuf -> Int32 in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pw, strlen(pw),
                    saltBuf.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    iterations,
                    &out, out.count
                )
            }
        }

        guard status == kCCSuccess else { throw VaultError.kdfFailed }
        return Data(out)
    }

    // ── 封裝／拆封 ────────────────────────────────────
    /// AES-256-GCM。GCM 除了加密還會產生驗證標籤，所以密文被人動過一個位元也解不開，
    /// 不會默默吐出一段垃圾給你。
    ///
    /// 回傳的是 combined 格式：nonce ‖ 密文 ‖ 標籤，直接當一整塊寫進檔案就好。
    /// nonce 由 CryptoKit 每次隨機產生，**不要自己指定**——同一把金鑰重複用同一個 nonce 會直接洩漏明文。
    static func seal(_ plain: Data, key: Data) throws -> Data {
        let box = try AES.GCM.seal(plain, using: SymmetricKey(data: key))
        guard let combined = box.combined else { throw VaultError.corrupted }
        return combined
    }

    /// 拆封。**金鑰不對就是丟 error，這就是「密碼錯誤」的唯一判斷依據。**
    static func open(_ blob: Data, key: Data) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: blob)
            return try AES.GCM.open(box, using: SymmetricKey(data: key))
        } catch {
            throw VaultError.wrongKey
        }
    }
}

// ── 錯誤 ──────────────────────────────────────────────
enum VaultError: Error {
    /// 金鑰解不開這塊密文。多數時候意思就是「密碼打錯了」。
    case wrongKey
    /// 檔案存在但結構壞了（被截斷、被改過、版本不認得）
    case corrupted
    case kdfFailed
    /// 還沒建立過 vault
    case notInitialised
    case ioFailed(String)

    var message: String {
        switch self {
        case .wrongKey:        "密碼不正確"
        case .corrupted:       "資料檔已損毀"
        case .kdfFailed:       "金鑰產生失敗"
        case .notInitialised:  "尚未建立保管箱"
        case .ioFailed(let s): s
        }
    }
}
