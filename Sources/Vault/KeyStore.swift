import Foundation

/// 金鑰檔的內容。這個檔案本身是明文 JSON，**但裡面沒有一樣東西是機密**：
/// salt 是公開的、被包裝的主金鑰沒有對應的鑰匙就是一堆亂碼、提示問題本來就要給人看。
struct KeyFile: Codable {
    var version = 1

    /// 密碼那條路徑。**迭代次數要跟著這條路徑各自記。**
    ///
    /// 原本兩條路共用一個 `iterations`，那是個定時炸彈：換密碼時會把它升級成當下的
    /// `Crypto.iterations`，但 `recoveryWrapped` 還是用舊次數包的——下次拿復原金鑰
    /// 進來就用新次數去派生，**解不開，復原金鑰無聲失效**。
    /// 現在兩者相等所以看不出來，改過迭代次數的那天才會炸，而且炸得毫無線索。
    var passwordSalt: Data
    var passwordWrapped: Data
    var passwordIterations: UInt32 = Crypto.iterations

    /// 復原金鑰那條路徑。跟密碼是平行的兩把鑰匙，開的是同一把主金鑰。
    var recoverySalt: Data
    var recoveryWrapped: Data
    var recoveryIterations: UInt32 = Crypto.iterations

    /// 忘記密碼時顯示的**提示問題**。鎖定畫面在還沒解開任何東西之前就要顯示它，
    /// 所以只能明文。**這也是為什麼它叫「提示問題」不叫「提示」**——
    /// 使用者一旦以為是在填提示，就會把密碼本身寫進去，那等於印在門上。
    var hint: String = ""

    /// 提示問題的答案，第三把鑰匙。**可以沒有**——舊的保管箱沒有這一份，
    /// 而且使用者也可能只想把問題當提醒用。
    ///
    /// ⚠️ 這是整個保管箱最容易變成弱點的地方。答案的強度就是這條路的強度，
    /// 「我媽姓什麼」這種常識題等於把門開給任何認識你的人。UI 上要講清楚。
    var answerSalt: Data? = nil
    var answerWrapped: Data? = nil
    var answerIterations: UInt32 = Crypto.iterations

    var createdAt = Date()

    init(passwordSalt: Data, passwordWrapped: Data,
         recoverySalt: Data, recoveryWrapped: Data, hint: String) {
        self.passwordSalt = passwordSalt
        self.passwordWrapped = passwordWrapped
        self.recoverySalt = recoverySalt
        self.recoveryWrapped = recoveryWrapped
        self.hint = hint
    }

    /// **舊格式必須讀得進來。** 已經建好的 vault 用的是單一 `iterations` 欄位，
    /// 讀不到它就等於使用者的保管箱再也打不開——而且症狀會長得像「密碼錯誤」。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version         = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        passwordSalt    = try c.decode(Data.self, forKey: .passwordSalt)
        passwordWrapped = try c.decode(Data.self, forKey: .passwordWrapped)
        recoverySalt    = try c.decode(Data.self, forKey: .recoverySalt)
        recoveryWrapped = try c.decode(Data.self, forKey: .recoveryWrapped)
        hint            = try c.decodeIfPresent(String.self, forKey: .hint) ?? ""
        createdAt       = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        answerSalt      = try c.decodeIfPresent(Data.self, forKey: .answerSalt)
        answerWrapped   = try c.decodeIfPresent(Data.self, forKey: .answerWrapped)
        answerIterations = try c.decodeIfPresent(UInt32.self, forKey: .answerIterations)
            ?? Crypto.iterations

        // 舊版共用的那個欄位當退路
        let legacy = try c.decodeIfPresent(UInt32.self, forKey: .iterations)
        passwordIterations = try c.decodeIfPresent(UInt32.self, forKey: .passwordIterations)
            ?? legacy ?? Crypto.iterations
        recoveryIterations = try c.decodeIfPresent(UInt32.self, forKey: .recoveryIterations)
            ?? legacy ?? Crypto.iterations
    }

    /// 手寫是因為 `iterations` 只讀不寫——它是舊格式的退路，
    /// 留在 CodingKeys 裡讓解碼看得到，但寫出去的一律是新格式的兩個欄位。
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(passwordSalt, forKey: .passwordSalt)
        try c.encode(passwordWrapped, forKey: .passwordWrapped)
        try c.encode(passwordIterations, forKey: .passwordIterations)
        try c.encode(recoverySalt, forKey: .recoverySalt)
        try c.encode(recoveryWrapped, forKey: .recoveryWrapped)
        try c.encode(recoveryIterations, forKey: .recoveryIterations)
        try c.encode(hint, forKey: .hint)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(answerSalt, forKey: .answerSalt)
        try c.encodeIfPresent(answerWrapped, forKey: .answerWrapped)
        if answerWrapped != nil { try c.encode(answerIterations, forKey: .answerIterations) }
    }

    enum CodingKeys: String, CodingKey {
        case version, passwordSalt, passwordWrapped, passwordIterations
        case recoverySalt, recoveryWrapped, recoveryIterations, hint, createdAt
        case answerSalt, answerWrapped, answerIterations
        case iterations   // 只讀不寫，舊格式的退路
    }
}

/// 主金鑰的保管與交付。
///
/// ## 為什麼要有「主金鑰」這一層
///
/// 直覺的做法是拿密碼派生的金鑰直接加密資料。那樣的話**改密碼就得把所有資料重新加密一遍**，
/// 而且沒辦法同時支援「密碼」和「復原金鑰」兩種入口——一份密文只能有一把鑰匙。
///
/// 所以中間隔一層：資料永遠用主金鑰加密，主金鑰本身被密碼、復原金鑰、Touch ID
/// 各包一份。要多一條入口就多包一份，改密碼只是把其中一份重包，資料一個位元都不用動。
/// ## ⚠️ 這個檔案的每個修改都是「讀 → 改 → 寫回」
///
/// 所以**中間絕對不能有 `await`**，而且全部要在同一條執行緒上跑。
///
/// 踩過的坑：`regenerateRecovery` 原本先 `load()` 再 `await` 派生金鑰（135 ms）
/// 最後才 `write()`。這段等待期間，設定視窗關閉時的「寫回提示問題」插了進來——
/// 它讀到同一份舊資料、改完寫回，然後被重產那邊用**更舊的版本**蓋掉。
/// 被蓋掉的是提示問題還是新金鑰，純粹看誰的 write 最後執行。
/// 使用者看到的症狀是「剛產生的復原金鑰打不開」，而且時好時壞。
///
/// 現在的規則：**先在背景把慢的算完，回到主執行緒才碰檔案**，
/// 而 `load` 到 `write` 之間一個 suspension point 都不留。
@MainActor
enum KeyStore {

    // ── 檔案 ──────────────────────────────────────────
    static var url: URL { VaultPaths.dir.appendingPathComponent("keys.json") }
    static var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    static func load() -> KeyFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(KeyFile.self, from: data)
    }

    static func write(_ file: KeyFile) throws {
        try VaultPaths.ensureDir()
        let data = try JSONEncoder().encode(file)
        try data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    // ── 建立 ──────────────────────────────────────────
    /// 第一次建立保管箱。回傳主金鑰（拿去解／存資料）跟復原金鑰（顯示給使用者抄下來）。
    ///
    /// 主金鑰在這裡誕生，是純亂數，**跟密碼沒有數學關係**。
    /// 密碼只是包住它的其中一層紙。
    static func create(password: String, hint: String) async throws -> (master: Data, recovery: String) {
        let master = Crypto.randomBytes(Crypto.keyBytes)
        let recovery = makeRecoveryKey()

        let pwSalt = Crypto.randomBytes(16)
        let rkSalt = Crypto.randomBytes(16)

        let pwKey = try await deriveOffMain(password: password, salt: pwSalt)
        let rkKey = try await deriveOffMain(password: normalise(recovery), salt: rkSalt)

        try write(KeyFile(
            passwordSalt: pwSalt,
            passwordWrapped: try Crypto.seal(master, key: pwKey),
            recoverySalt: rkSalt,
            recoveryWrapped: try Crypto.seal(master, key: rkKey),
            hint: hint
        ))
        return (master, recovery)
    }

    // ── 解鎖 ──────────────────────────────────────────
    /// 用密碼取回主金鑰。
    ///
    /// 注意這裡沒有任何 `if 輸入 == 儲存的密碼`。密碼錯的話 `Crypto.open` 拆不開，
    /// 直接丟 `.wrongKey`。**「儲存的密碼」這個東西根本不存在，所以也偷不走。**
    static func unlock(password: String) async throws -> Data {
        guard let f = load() else { throw VaultError.notInitialised }
        let key = try await deriveOffMain(password: password, salt: f.passwordSalt,
                                          iterations: f.passwordIterations)
        return try Crypto.open(f.passwordWrapped, key: key)
    }

    /// 用復原金鑰取回主金鑰。使用者抄在紙上的大小寫、有沒有連字號都不重要，正規化之後再派生。
    static func unlock(recovery: String) async throws -> Data {
        guard let f = load() else { throw VaultError.notInitialised }
        let key = try await deriveOffMain(password: normalise(recovery), salt: f.recoverySalt,
                                          iterations: f.recoveryIterations)
        return try Crypto.open(f.recoveryWrapped, key: key)
    }

    // ── 變更 ──────────────────────────────────────────
    /// 換密碼＝把主金鑰用新密碼重新包一份。**資料完全不用動。**
    /// 舊密碼要先驗過，而驗的方式一樣是「解得開才算數」。
    static func changePassword(current: String, new: String) async throws {
        let master = try await unlock(password: current)

        let salt = Crypto.randomBytes(16)
        let key = try await deriveOffMain(password: new, salt: salt)

        // ↓ 這裡開始不能再有 await
        guard var f = load() else { throw VaultError.notInitialised }
        f.passwordSalt = salt
        f.passwordWrapped = try Crypto.seal(master, key: key)
        // 只升級密碼這條路徑的迭代次數。**不能碰 recoveryIterations**——
        // 復原金鑰那份還是用舊次數包的，改了它就再也解不開。
        f.passwordIterations = Crypto.iterations
        try write(f)
    }

    /// 重新產生復原金鑰。**舊的立刻作廢**——因為包裝主金鑰的那份被覆蓋掉了，
    /// 舊金鑰派生出來的鑰匙再也解不開任何東西。
    static func regenerateRecovery(master: Data) async throws -> String {
        let recovery = makeRecoveryKey()
        let salt = Crypto.randomBytes(16)
        let key = try await deriveOffMain(password: normalise(recovery), salt: salt)

        // ↓ 這裡開始不能再有 await。
        // 原本 `load()` 在上面那行 await 之前，那 135 毫秒就是別人插進來的空檔。
        guard var f = load() else { throw VaultError.notInitialised }
        f.recoverySalt = salt
        f.recoveryWrapped = try Crypto.seal(master, key: key)
        f.recoveryIterations = Crypto.iterations   // 這份是現在包的，記下現在的次數
        try write(f)
        return recovery
    }

    static var hint: String { load()?.hint ?? "" }

    static func updateHint(_ h: String) {
        guard var f = load(), f.hint != h else { return }   // 沒變就不要多寫一次檔
        f.hint = h
        try? write(f)
    }

    // ── 提示問題的答案 ────────────────────────────────
    /// 有沒有設過答案。沒設的話鎖定畫面就不該出現答案欄，
    /// 不然使用者會對著一個永遠不會通過的框一直試。
    static var hasAnswer: Bool { load()?.answerWrapped != nil }

    /// 把答案設成第三把鑰匙。跟密碼、復原金鑰完全平行——
    /// 一樣是包裝同一把主金鑰，一樣「解得開才算對」。
    static func setAnswer(master: Data, answer: String) async throws {
        let a = normaliseAnswer(answer)
        guard !a.isEmpty else { throw VaultError.corrupted }
        let salt = Crypto.randomBytes(16)
        let key = try await deriveOffMain(password: a, salt: salt)

        // ↓ 這裡開始不能有 await
        guard var f = load() else { throw VaultError.notInitialised }
        f.answerSalt = salt
        f.answerWrapped = try Crypto.seal(master, key: key)
        f.answerIterations = Crypto.iterations
        try write(f)
    }

    static func unlock(answer: String) async throws -> Data {
        guard let f = load(), let salt = f.answerSalt, let wrapped = f.answerWrapped else {
            throw VaultError.notInitialised
        }
        let key = try await deriveOffMain(password: normaliseAnswer(answer), salt: salt,
                                          iterations: f.answerIterations)
        return try Crypto.open(wrapped, key: key)
    }

    /// 拿掉答案這條路。問題本身留著當提醒用。
    static func clearAnswer() {
        guard var f = load(), f.answerWrapped != nil else { return }
        f.answerSalt = nil
        f.answerWrapped = nil
        try? write(f)
    }

    /// 前後空白吃掉、英文一律轉小寫。
    /// **不要再多做正規化了**——每多洗掉一種差異就少一分熵，而這條路的答案本來就短。
    /// 中日文不受大小寫影響，這裡主要是讓「Chen」和「chen」不要變成兩個答案。
    static func normaliseAnswer(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // ── 復原金鑰的格式 ────────────────────────────────
    /// 24 個字元切成 6 組。字母表拿掉了 I O 0 1，因為這串東西是要用手抄在紙上的，
    /// 抄錯一個字元就永遠開不了。
    static func makeRecoveryKey() -> String {
        let set = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        // 字母表剛好 32 個，256 除得盡，所以直接取餘數不會讓某些字元偏多
        let bytes = Crypto.randomBytes(24).map { Int($0) }
        return (0..<6).map { g in
            String((0..<4).map { i in set[bytes[g * 4 + i] % set.count] })
        }.joined(separator: "-")
    }

    /// 抄下來的東西大小寫、連字號、空白都可能跑掉，統一洗成純大寫英數再拿去派生。
    static func normalise(_ s: String) -> String {
        s.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    // ── 內部 ──────────────────────────────────────────
    /// PBKDF2 跑 60 萬次要好幾百毫秒。**留在主執行緒的話畫面會整個凍住**，
    /// 連輸入框的游標都不會閃。丟到背景去。
    private static func deriveOffMain(password: String, salt: Data,
                                      iterations: UInt32 = Crypto.iterations) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try Crypto.derive(password: password, salt: salt, iterations: iterations)
        }.value
    }
}
