import Foundation

/// 檢查更新。從 Babos 移植過來的。
///
/// repo 是公開的，所以 GitHub 的 releases API 不用認證就能打。
/// 比對最新的 tag 和自己的版本，就這樣而已。
///
/// **不在 app 內下載安裝。** 那需要一整套簽章驗證的機制，
/// 這個規模不值得。這裡只回答「有沒有新的」。
enum UpdateState: Equatable {
    case idle
    case checking
    case latest
    case available(String)
    case failed(String)
}

private struct GitHubRelease: Decodable {
    let tag_name: String
}

enum Version {
    /// "v0.1.10" → [0, 1, 10]
    static func parts(_ s: String) -> [Int] {
        let t = s.hasPrefix("v") ? String(s.dropFirst()) : s
        return t.split(separator: ".").map { Int($0) ?? 0 }
    }

    /// **用數值比，不能用字串。**
    /// 字串比較會得到 "0.1.10" < "0.1.9"，版號跨過個位數的那一刻
    /// 就會謊報「已是最新」。
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let d = (i < x.count ? x[i] : 0) - (i < y.count ? y[i] : 0)
            if d != 0 { return d > 0 }
        }
        return false
    }
}

extension Store {
    static let releasesURL = "https://github.com/qiushibo-dev/vault/releases"
    private static let latestAPI =
        "https://api.github.com/repos/qiushibo-dev/vault/releases/latest"

    func checkUpdate() async {
        updateState = .checking
        do {
            var req = URLRequest(url: URL(string: Self.latestAPI)!)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 10

            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            guard http.statusCode == 200 else {
                throw NSError(domain: "GitHub", code: http.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
            }

            let tag = try JSONDecoder().decode(GitHubRelease.self, from: data).tag_name
            // **失敗不要默默吞掉。** 要分得出是離線還是 API 那邊的問題
            updateState = Version.isNewer(tag, than: version) ? .available(tag) : .latest
        } catch {
            updateState = .failed(error.localizedDescription)
        }
    }
}
