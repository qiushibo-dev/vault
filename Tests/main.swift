// 加密層的驗證。用 `./verify.sh` 跑。
//
// **檔名必須是 main.swift。** swiftc 只允許 top-level code 出現在這個名字的檔案裡，
// 叫 verify.swift 會得到「expressions are not allowed at the top level」。
import Foundation
import AppKit

// 整個保管箱改指到暫存目錄。**這一行決定了測試不會碰到真實資料。**
VaultPaths.overrideRoot = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("vault-verify-\(UUID().uuidString)")

var pass = 0, fail = 0

@MainActor func check(_ label: String, _ ok: Bool) {
    if ok { pass += 1; print("  ok   \(label)") }
    else  { fail += 1; print("  FAIL \(label)") }
}

@MainActor func throwsError(_ label: String, _ body: () throws -> Void) {
    do { try body(); fail += 1; print("  FAIL \(label) — 應該要丟錯卻通過了") }
    catch { pass += 1; print("  ok   \(label)") }
}

@MainActor func throwsErrorAsync(_ label: String, _ body: () async throws -> Void) async {
    do { try await body(); fail += 1; print("  FAIL \(label) — 應該要丟錯卻通過了") }
    catch { pass += 1; print("  ok   \(label)") }
}

// ── Crypto ────────────────────────────────────────────
print("\nCrypto")

let salt = Crypto.randomBytes(16)
// 測試用低迭代，跑 600,000 次會讓這支程式跑好幾分鐘。
// 迭代次數不影響正確性，只影響破解成本。
let cheap: UInt32 = 1_000

let k1 = try Crypto.derive(password: "correct horse", salt: salt, iterations: cheap)
let k2 = try Crypto.derive(password: "correct horse", salt: salt, iterations: cheap)
let k3 = try Crypto.derive(password: "correct horse", salt: Crypto.randomBytes(16), iterations: cheap)
let k4 = try Crypto.derive(password: "correct horsf", salt: salt, iterations: cheap)

check("同密碼同 salt → 同金鑰（不然重開就解不開自己的資料）", k1 == k2)
check("同密碼不同 salt → 不同金鑰", k1 != k3)
check("差一個字元 → 完全不同的金鑰", k1 != k4)
check("金鑰長度 32 bytes（AES-256）", k1.count == 32)
check("亂數不會重複", Crypto.randomBytes(32) != Crypto.randomBytes(32))

let secret = "銀行密碼：Tr0ub4dor&3".data(using: .utf8)!
let sealed = try Crypto.seal(secret, key: k1)

check("密文跟明文不一樣", !sealed.contains(secret))
check("拆封拿回原文", try Crypto.open(sealed, key: k1) == secret)
check("同樣的明文加密兩次會得到不同密文（nonce 每次都換）",
      try Crypto.seal(secret, key: k1) != Crypto.seal(secret, key: k1))

throwsError("錯的金鑰拆不開") { _ = try Crypto.open(sealed, key: k4) }

var tampered = sealed
tampered[tampered.count - 1] ^= 0x01
throwsError("密文被改一個位元就拆不開") { _ = try Crypto.open(tampered, key: k1) }

var truncated = sealed
truncated.removeLast(4)
throwsError("密文被截斷就拆不開") { _ = try Crypto.open(truncated, key: k1) }

// ── KeyStore ──────────────────────────────────────────
print("\nKeyStore")

let master: Data
let recovery: String
do {
    let r = try await KeyStore.create(password: "my-real-password", hint: "母親的舊姓是什麼？")
    master = r.master
    recovery = r.recovery
}

check("金鑰檔產生了", KeyStore.exists)
check("主金鑰 32 bytes", master.count == 32)
check("復原金鑰是 6 組 4 碼", recovery.split(separator: "-").allSatisfy { $0.count == 4 }
                          && recovery.split(separator: "-").count == 6)

let raw = try Data(contentsOf: KeyStore.url)
let text = String(data: raw, encoding: .utf8) ?? ""
check("金鑰檔裡找不到密碼明文", !text.contains("my-real-password"))
check("金鑰檔裡找不到復原金鑰明文", !text.contains(recovery.replacingOccurrences(of: "-", with: "")))
check("金鑰檔裡找不到主金鑰", !raw.contains(master))
check("提示問題是明文（鎖定畫面要顯示）", text.contains("母親の舊姓") || text.contains("母親"))

check("密碼解得回同一把主金鑰", try await KeyStore.unlock(password: "my-real-password") == master)
await throwsErrorAsync("錯的密碼解不開") { _ = try await KeyStore.unlock(password: "my-real-passwore") }
await throwsErrorAsync("空密碼解不開") { _ = try await KeyStore.unlock(password: "") }

check("復原金鑰解得回同一把主金鑰", try await KeyStore.unlock(recovery: recovery) == master)
check("復原金鑰小寫也能用", try await KeyStore.unlock(recovery: recovery.lowercased()) == master)
check("復原金鑰去掉連字號也能用",
      try await KeyStore.unlock(recovery: recovery.replacingOccurrences(of: "-", with: " ")) == master)
await throwsErrorAsync("亂打的復原金鑰解不開") { _ = try await KeyStore.unlock(recovery: "AAAA-BBBB-CCCC-DDDD-EEEE-FFFF") }

// ── 換密碼 ────────────────────────────────────────────
print("\n換密碼")

try await KeyStore.changePassword(current: "my-real-password", new: "a-brand-new-one")

check("新密碼解得開，而且拿到的是同一把主金鑰（資料不用重新加密）",
      try await KeyStore.unlock(password: "a-brand-new-one") == master)
await throwsErrorAsync("舊密碼失效") { _ = try await KeyStore.unlock(password: "my-real-password") }
check("復原金鑰不受換密碼影響", try await KeyStore.unlock(recovery: recovery) == master)
await throwsErrorAsync("舊密碼不能用來換密碼") {
    try await KeyStore.changePassword(current: "my-real-password", new: "whatever")
}

// ── 重產復原金鑰 ──────────────────────────────────────
print("\n重產復原金鑰")

let newRecovery = try await KeyStore.regenerateRecovery(master: master)
check("新的復原金鑰跟舊的不一樣", newRecovery != recovery)
check("新的解得開", try await KeyStore.unlock(recovery: newRecovery) == master)
await throwsErrorAsync("舊的當場失效") { _ = try await KeyStore.unlock(recovery: recovery) }
check("密碼不受影響", try await KeyStore.unlock(password: "a-brand-new-one") == master)

// ── 提示問題 ──────────────────────────────────────────
print("\n提示問題")
KeyStore.updateHint("第一隻貓叫什麼？")
check("提示問題改得掉", KeyStore.hint == "第一隻貓叫什麼？")
check("改提示不影響解鎖", try await KeyStore.unlock(password: "a-brand-new-one") == master)

// ── 存檔的 round-trip ─────────────────────────────────
// 這一段對應的是他最在意的那句話：關掉再開，東西還在不在。
print("\n存檔")

var bank = Item(kind: .password)
bank.name = "銀行"
bank.value = "Tr0ub4dor&3"
bank.note = "分行：新宿"
bank.tags = ["錢"]

var mail = Item(kind: .password)
mail.name = "メール"
mail.value = "パスワード１２３🔐"

var doc = Item(kind: .document)
doc.name = "租約"

let payload = VaultPayload(
    items: [bank, mail, doc],
    tags: [TagDef(name: "錢", colour: 0)],
    prefs: Prefs(touchIDOn: false, autoLockSeconds: 300, lang: .ja))

try Storage.save(payload, key: master)
check("vault.dat 產生了", Storage.exists)

let onDisk = try Data(contentsOf: VaultPaths.data)
check("硬碟上翻不到「Tr0ub4dor」這串字",
      !onDisk.contains("Tr0ub4dor&3".data(using: .utf8)!))
check("硬碟上翻不到項目名稱", !onDisk.contains("銀行".data(using: .utf8)!))

let reloaded = try Storage.load(key: master)
check("三筆項目都回來了", reloaded.items.count == 3)
check("密碼一字不差", reloaded.items[0].value == "Tr0ub4dor&3")
check("日文和 emoji 沒壞", reloaded.items[1].value == "パスワード１２３🔐")
check("備註和標籤都在", reloaded.items[0].note == "分行：新宿" && reloaded.items[0].tags == ["錢"])
check("標籤定義存得回來", reloaded.tags.first?.name == "錢")
check("設定跟著存（不放明文 plist）",
      reloaded.prefs.autoLockSeconds == 300 && reloaded.prefs.lang == .ja
      && reloaded.prefs.touchIDOn == false)

throwsError("拿別的金鑰讀 vault.dat 會失敗") {
    _ = try Storage.load(key: Crypto.randomBytes(32))
}

// 加欄位不能讓既有資料變成解不開——這個坑會偽裝成「密碼錯誤」，非常難查
let sparse = #"{"items":[{"kind":"password","name":"只有名字"}]}"#.data(using: .utf8)!
try Crypto.seal(sparse, key: master).write(to: VaultPaths.data)
let old = try Storage.load(key: master)
check("欄位不齊的舊存檔照樣讀得進來", old.items.first?.name == "只有名字")
try Storage.save(payload, key: master)

// ── 附件 ──────────────────────────────────────────────
print("\n附件")

// 造一張真的 PNG，才驗得到縮圖那條路
let img = NSImage(size: NSSize(width: 900, height: 600))
img.lockFocus()
NSColor.systemPink.setFill()
NSRect(x: 0, y: 0, width: 900, height: 600).fill()
img.unlockFocus()
let png = NSBitmapImageRep(data: img.tiffRepresentation!)!
    .representation(using: .png, properties: [:])!

let source = VaultPaths.dir.appendingPathComponent("原始照片.png")
try png.write(to: source)

let blobID = try Storage.importFile(source, key: master)
check("附件收進來了", Storage.blobExists(blobID))
check("附件的密文跟原檔不一樣",
      try Data(contentsOf: VaultPaths.blobs.appendingPathComponent(blobID)) != png)
check("解回來的位元組跟原檔一模一樣", try Storage.readBlob(blobID, key: master) == png)
check("縮圖產生了而且比原檔小",
      (Storage.readThumbnail(blobID, key: master)?.count ?? .max) < png.count)

// 保管箱裡放的是副本不是捷徑——原檔刪掉不該有任何影響
try FileManager.default.removeItem(at: source)
check("原檔刪掉之後附件還讀得出來", try Storage.readBlob(blobID, key: master) == png)
check("縮圖也還在", Storage.readThumbnail(blobID, key: master) != nil)

throwsError("拿別的金鑰讀附件會失敗") { _ = try Storage.readBlob(blobID, key: Crypto.randomBytes(32)) }

let scratch = try Storage.materialise(blobID, name: "影片", ext: "png", key: master)
check("解密成暫存檔（影片播放用的那條路）", FileManager.default.fileExists(atPath: scratch.path))
Storage.clearScratch()
check("上鎖時暫存檔被清掉", !FileManager.default.fileExists(atPath: scratch.path))

Storage.deleteBlob(blobID)
check("刪項目時附件跟著刪", !Storage.blobExists(blobID))
check("縮圖也一起刪（不然 blobs 會囤垃圾）", Storage.readThumbnail(blobID, key: master) == nil)

// ── 金鑰檔的格式相容 ──────────────────────────────────
// 改過 KeyFile 的結構之後，**已經建好的保管箱必須照樣打得開**。
// 讀不到金鑰檔的症狀會長得像「密碼錯誤」，使用者只會以為自己記錯密碼。
print("\n金鑰檔格式")

do {
    // 兩條路徑各自用不同的迭代次數——這正是舊版共用一個欄位時會爆掉的情況
    let m = Crypto.randomBytes(32)
    let ps = Crypto.randomBytes(16), rs = Crypto.randomBytes(16)
    let pIter: UInt32 = 1_000, rIter: UInt32 = 3_000

    var f = KeyFile(
        passwordSalt: ps,
        passwordWrapped: try Crypto.seal(m, key: try Crypto.derive(password: "pw", salt: ps, iterations: pIter)),
        recoverySalt: rs,
        recoveryWrapped: try Crypto.seal(m, key: try Crypto.derive(password: "RECOVERY", salt: rs, iterations: rIter)),
        hint: "")
    f.passwordIterations = pIter
    f.recoveryIterations = rIter
    try KeyStore.write(f)

    check("密碼用自己的迭代次數解", try await KeyStore.unlock(password: "pw") == m)
    check("復原金鑰用自己的迭代次數解（兩條路互不干擾）",
          try await KeyStore.unlock(recovery: "RECOVERY") == m)

    // 換密碼只能動密碼那條。碰到 recoveryIterations 的話復原金鑰會無聲失效。
    try await KeyStore.changePassword(current: "pw", new: "pw2")
    check("換密碼後，復原金鑰仍然解得開", try await KeyStore.unlock(recovery: "RECOVERY") == m)
    check("換密碼後，新密碼解得開", try await KeyStore.unlock(password: "pw2") == m)
}

do {
    // 舊格式：只有一個共用的 iterations 欄位，沒有分開的那兩個
    let m = Crypto.randomBytes(32)
    let ps = Crypto.randomBytes(16), rs = Crypto.randomBytes(16)
    let iter: UInt32 = 1_000
    let legacy: [String: Any] = [
        "version": 1,
        "iterations": iter,
        "passwordSalt": ps.base64EncodedString(),
        "passwordWrapped": try Crypto.seal(m, key: try Crypto.derive(password: "old", salt: ps, iterations: iter)).base64EncodedString(),
        "recoverySalt": rs.base64EncodedString(),
        "recoveryWrapped": try Crypto.seal(m, key: try Crypto.derive(password: "OLDKEY", salt: rs, iterations: iter)).base64EncodedString(),
        "hint": "舊格式",
        "createdAt": 0
    ]
    try JSONSerialization.data(withJSONObject: legacy).write(to: KeyStore.url)

    check("舊格式的金鑰檔讀得進來", KeyStore.load() != nil)
    check("舊格式：密碼開得了", try await KeyStore.unlock(password: "old") == m)
    check("舊格式：復原金鑰開得了", try await KeyStore.unlock(recovery: "OLDKEY") == m)
    check("舊格式的提示問題還在", KeyStore.hint == "舊格式")
}

// ── 同時改同一個金鑰檔 ────────────────────────────────
// app 裡真實會發生的順序：按下「重新產生」→ 設定視窗開始關閉 →
// 關閉時 onDisappear 把提示問題寫回金鑰檔。**兩件事在改同一個檔案**，
// 而重產中間有 135ms 的派生要等，正好是另一邊插進來的空檔。
print("\n並行寫入金鑰檔")

do {
    // 前面的測試已經把 keys.json 換掉了，這裡自己開一個乾淨的
    let (m, _) = try await KeyStore.create(password: "concurrent-test", hint: "起始提示")

    // 重產進行到一半時，另一邊寫入提示問題
    async let regen = KeyStore.regenerateRecovery(master: m)
    try await Task.sleep(for: .milliseconds(20))
    KeyStore.updateHint("關窗時寫進去的提示")
    let fresh = try await regen

    check("重產期間有人改提示，新金鑰仍然有效",
          (try? await KeyStore.unlock(recovery: fresh)) == m)
    check("重產期間寫的提示沒有被吃掉", KeyStore.hint == "關窗時寫進去的提示")

    // 反過來：提示先寫，重產後到
    KeyStore.updateHint("先寫的提示")
    let fresh2 = try await KeyStore.regenerateRecovery(master: m)
    KeyStore.updateHint("後寫的提示")
    check("重產完成後才改提示，金鑰仍然有效",
          (try? await KeyStore.unlock(recovery: fresh2)) == m)
    check("密碼始終不受影響",
          (try? await KeyStore.unlock(password: "concurrent-test")) == m)
}

// ── 提示問題的答案（第三把鑰匙）────────────────────────
print("\n提示問題的答案")

do {
    let (m, rec) = try await KeyStore.create(password: "answer-test", hint: "我媽姓啥？")
    check("新的保管箱預設沒有答案", !KeyStore.hasAnswer)

    try await KeyStore.setAnswer(master: m, answer: "  Chen  ")
    check("設定完就有答案了", KeyStore.hasAnswer)
    check("答案開得了，拿到的是同一把主金鑰", try await KeyStore.unlock(answer: "Chen") == m)
    check("前後空白不算數", try await KeyStore.unlock(answer: "chen  ") == m)
    check("大小寫不算數", try await KeyStore.unlock(answer: "CHEN") == m)
    await throwsErrorAsync("答錯就是打不開") { _ = try await KeyStore.unlock(answer: "Lin") }
    await throwsErrorAsync("空答案不能開") { _ = try await KeyStore.unlock(answer: "   ") }

    let raw = String(data: try Data(contentsOf: KeyStore.url), encoding: .utf8) ?? ""
    check("金鑰檔裡找不到答案明文", !raw.lowercased().contains("chen"))
    check("問題本身是明文（鎖定畫面要顯示）", raw.contains("我媽姓啥"))

    let viaPassword = try await KeyStore.unlock(password: "answer-test")
    let viaRecovery = try await KeyStore.unlock(recovery: rec)
    check("另外兩條路不受影響", viaPassword == m && viaRecovery == m)

    // 換答案：舊的當場失效
    try await KeyStore.setAnswer(master: m, answer: "第二個答案")
    check("新答案開得了", try await KeyStore.unlock(answer: "第二個答案") == m)
    await throwsErrorAsync("舊答案失效") { _ = try await KeyStore.unlock(answer: "Chen") }

    // 換密碼不該動到答案這條路
    try await KeyStore.changePassword(current: "answer-test", new: "answer-test-2")
    check("換密碼後答案仍然有效", try await KeyStore.unlock(answer: "第二個答案") == m)

    KeyStore.clearAnswer()
    check("清掉之後就沒有答案了", !KeyStore.hasAnswer)
    await throwsErrorAsync("清掉之後答案開不了") { _ = try await KeyStore.unlock(answer: "第二個答案") }
    check("清掉答案不影響密碼", try await KeyStore.unlock(password: "answer-test-2") == m)
    check("清掉答案不影響提示問題", KeyStore.hint == "我媽姓啥？")
}

// ── 真實迭代次數的成本 ────────────────────────────────
print("\n實際迭代次數（\(Crypto.iterations) 次）")
let t0 = Date()
_ = try Crypto.derive(password: "timing check", salt: salt)
let ms = Int(Date().timeIntervalSince(t0) * 1000)
print("  一次派生 \(ms) ms")
check("解鎖延遲在可接受範圍（100–3000 ms）", ms > 100 && ms < 3000)

// ── 收尾 ──────────────────────────────────────────────
try? FileManager.default.removeItem(at: VaultPaths.dir)

print("\n通過 \(pass)　失敗 \(fail)\n")
exit(fail == 0 ? 0 : 1)
