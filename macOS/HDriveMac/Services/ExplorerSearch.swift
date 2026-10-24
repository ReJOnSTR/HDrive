import Foundation

struct ExplorerSearchFilter {
    var query = ""
    var fileExtension = ""
    var minimumBytes: Int64 = 0
    var modifiedAfter: Date?
    func matches(_ file: RemoteFileItem) -> Bool {
        guard file.name.matchesSearchQuery(query) else { return false }
        let ext = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if !ext.isEmpty && (file.isDirectory || (file.name as NSString).pathExtension.caseInsensitiveCompare(ext) != .orderedSame) { return false }
        if minimumBytes > 0 && (file.isDirectory || file.size < minimumBytes) { return false }
        if let modifiedAfter, file.modificationDate == nil || file.modificationDate! < modifiedAfter { return false }
        return true
    }
}

enum ExplorerSearch {
    struct Result { var files: [RemoteFileItem]; var errors: [String] }
    static func scan(start: String, config: CloudreveServerConfig,
                     list: (String) async throws -> [RemoteFileItem],
                     onPage: ([RemoteFileItem]) async -> Void = { _ in }) async throws -> Result {
        var pending = [start], visited = Set<String>(), files: [RemoteFileItem] = [], errors: [String] = []
        var next = 0
        while next < pending.count {
            try Task.checkCancellation()
            let path = pending[next]; next += 1
            guard visited.insert(path).inserted else { continue }
            do {
                let entries = try await list(path)
                try Task.checkCancellation()
                files.append(contentsOf: entries)
                pending.append(contentsOf: entries.filter(\.isDirectory).map { $0.navigationPath(relativeTo: config) })
                await onPage(files)
            } catch {
                try Task.checkCancellation()
                errors.append(path + ": " + error.localizedDescription)
            }
        }
        return Result(files: files, errors: errors)
    }
}

// MARK: - Türkçe Karakter Uyumlu Arama Genişletmesi
extension String {
    /// Türkçe karakter uyumlu (büyük/küçük harf, İ-i, I-ı, ç-c, ğ-g, ö-o, ş-s, ü-u toleranslı) arama karşılaştırması
    func matchesSearchQuery(_ query: String) -> Bool {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return true }

        // 1. Standart hızlı arama
        if self.localizedCaseInsensitiveContains(cleanQuery) { return true }

        // 2. Türkçe normalize vaka (İ -> i, I -> ı, kombine işaretlerin temizlenmesi)
        let normSelf = self.turkishNormalized()
        let normQuery = cleanQuery.turkishNormalized()
        if normSelf.contains(normQuery) { return true }

        // 3. Toleranslı vaka (kullanıcı klavyeden "c" yazsa da "ç", "s" yazsa da "ş", "g" yazsa da "ğ" eşleşir)
        let fuzzySelf = normSelf.turkishFuzzyNormalized()
        let fuzzyQuery = normQuery.turkishFuzzyNormalized()
        if fuzzySelf.contains(fuzzyQuery) { return true }

        return false
    }

    private func turkishNormalized() -> String {
        var s = self.replacingOccurrences(of: "İ", with: "i")
        s = s.replacingOccurrences(of: "I", with: "ı")
        s = s.lowercased(with: Locale(identifier: "tr_TR"))
        s = s.precomposedStringWithCanonicalMapping
        s = s.replacingOccurrences(of: "\u{0307}", with: "") // Combining dot above
        return s
    }

    private func turkishFuzzyNormalized() -> String {
        let map: [Character: Character] = [
            "ç": "c", "ğ": "g", "ı": "i", "ö": "o", "ş": "s", "ü": "u"
        ]
        return String(self.map { map[$0] ?? $0 })
    }
}
