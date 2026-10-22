import Foundation
import CryptoKit

struct AppReleaseVersion: Comparable {
    let parts: [Int]
    init?(_ text: String) {
        let version = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let pieces = version.components(separatedBy: "+")[0].split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3, pieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else { return nil }
        let numbers = pieces.compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        parts = numbers
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

struct AppRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let size: Int64
        let browser_download_url: URL
        let digest: String?
        var sha256: String? {
            guard let digest, digest.hasPrefix("sha256:") else { return nil }
            let hex = String(digest.dropFirst(7)).lowercased()
            return hex.count == 64 && hex.allSatisfy({ "0123456789abcdef".contains($0) }) ? hex : nil
        }
    }
    let tag_name: String
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
    var pageURL: URL { URL(string: "https://github.com/ReJOnSTR/HDrive/releases/tag/" + tag_name)! }
    var macAsset: Asset? {
        assets.first {
            $0.name == "HDrive-macOS.dmg" && $0.size > 0 && $0.size <= 1_073_741_824 &&
            $0.browser_download_url.absoluteString == "https://github.com/ReJOnSTR/HDrive/releases/download/\(tag_name)/HDrive-macOS.dmg"
        }
    }
    func isNewer(than current: String) -> Bool {
        guard let installed = AppReleaseVersion(current), let available = AppReleaseVersion(tag_name) else { return false }
        return available > installed
    }
}

enum AppUpdateService {
    static let releasesURL = URL(string: "https://github.com/ReJOnSTR/HDrive/releases")!
    static var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0" }
    static func failure(_ message: String) -> NSError {
        NSError(domain: "HDrive.Update", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    static func parse(_ data: Data) throws -> AppRelease {
        let release = try JSONDecoder().decode(AppRelease.self, from: data)
        guard !release.draft, !release.prerelease, AppReleaseVersion(release.tag_name) != nil,
              !release.tag_name.contains("+") else { throw failure("Geçerli bir kararlı sürüm bulunamadı.") }
        return release
    }
    static func check(session: URLSession = .shared) async throws -> AppRelease? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/ReJOnSTR/HDrive/releases/latest")!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("HDrive-Update-Check", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw failure("Güncelleme sunucusu geçerli yanıt vermedi.") }
        if http.statusCode == 404 { return nil }
        if http.statusCode == 403 || http.statusCode == 429 { throw failure("Güncelleme kontrolü geçici olarak sınırlandı. Biraz sonra tekrar deneyin.") }
        guard http.statusCode == 200 else { throw failure("Güncelleme kontrolü başarısız (HTTP \(http.statusCode)).") }
        return try parse(data)
    }
    static func verify(_ url: URL, asset: AppRelease.Asset) throws {
        guard let expected = asset.sha256 else { throw failure("Bu yayın için paket doğrulama bilgisi bulunmuyor. Yayın sayfasını kullanın.") }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256(), total: Int64 = 0
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hash.update(data: data); total += Int64(data.count)
        }
        let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard total == asset.size, actual == expected else { throw failure("İndirilen paket doğrulanamadı. Lütfen tekrar indirin.") }
    }
    static func download(_ release: AppRelease, current: String = currentVersion,
                         progress: @escaping (Double) -> Void) async throws -> URL {
        guard release.isNewer(than: current), let asset = release.macAsset, asset.sha256 != nil else {
            throw failure("Bu sürüm için uygun bir güncelleme paketi yok.")
        }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 1800
        let delegate = UpdateDownloadDelegate(progress: progress)
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (temporary, response) = try await session.download(from: asset.browser_download_url)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw failure("Güncelleme paketi indirilemedi.") }
        try Task.checkCancellation()
        try verify(temporary, asset: asset)
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HDrive Updates").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(asset.name)
        do {
            try FileManager.default.moveItem(at: temporary, to: target)
            // Preserve normal macOS Internet-download/Gatekeeper handling.
            let quarantine = "0081;\(String(Int(Date().timeIntervalSince1970), radix: 16));HDrive;\(UUID().uuidString)"
            let result = quarantine.withCString { setxattr(target.path, "com.apple.quarantine", $0, strlen($0), 0, 0) }
            guard result == 0 else { throw failure("İndirilen paketin güvenlik bilgisi kaydedilemedi.") }
            return target
        } catch { try? FileManager.default.removeItem(at: folder); throw error }
    }
}

private final class UpdateDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let progress: (Double) -> Void
    init(progress: @escaping (Double) -> Void) { self.progress = progress }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 { progress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let url = request.url
        let allowed = url?.scheme == "https" && ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"].contains(url?.host ?? "") && url?.user == nil && url?.password == nil && (url?.port == nil || url?.port == 443)
        completionHandler(allowed ? request : nil)
    }
}
