import Foundation

/// Turns application names from a vision model into bundle identifiers from
/// the installed-apps whitelist. A name that matches nothing is dropped, never
/// invented, so a hallucination cannot enter a profile.
enum AppMatcher {
    struct NamedApp: Equatable {
        var name: String
        var confidence: Confidence
    }

    enum Confidence: String, Equatable {
        case high
        case low
    }

    struct Match: Equatable {
        var bundleId: String
        var name: String
        var confidence: Confidence
    }

    struct Result: Equatable {
        var matches: [Match]
        var unmatched: [String]
    }

    static func match(names: [NamedApp], installed: [InstalledApp]) -> Result {
        var matches: [Match] = []
        var unmatched: [String] = []
        var used = Set<String>()

        for named in names {
            let trimmed = named.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let hit = firstHit(trimmed, in: installed) else {
                unmatched.append(trimmed)
                continue
            }
            if used.contains(hit.bundleId) { continue }
            used.insert(hit.bundleId)
            matches.append(Match(bundleId: hit.bundleId, name: hit.name, confidence: named.confidence))
        }

        return Result(matches: matches, unmatched: unmatched)
    }

    /// Four steps, stop at the first hit.
    static func firstHit(_ name: String, in installed: [InstalledApp]) -> InstalledApp? {
        if let exact = installed.first(where: { $0.name.compare(name, options: [.caseInsensitive]) == .orderedSame }) {
            return exact
        }

        let needle = normalize(name)
        guard !needle.isEmpty else { return nil }
        if let normalised = installed.first(where: { normalize($0.name) == needle }) {
            return normalised
        }

        let prefixes = installed.filter { name in
            let installedNorm = normalize(name.name)
            return installedNorm.hasPrefix(needle) && installedNorm != needle
        }
        if prefixes.count == 1 { return prefixes.first }

        let close = installed.filter { levenshtein(normalize($0.name), needle) <= 2 && !normalize($0.name).isEmpty }
        if close.count == 1 { return close.first }
        return nil
    }

    static func normalize(_ raw: String) -> String {
        var text = raw.lowercased()
        for word in ["desktop", "app"] {
            text = text.replacingOccurrences(of: word, with: "")
        }
        return text.filter { $0.isLetter || $0.isNumber }
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        if aChars.isEmpty { return bChars.count }
        if bChars.isEmpty { return aChars.count }
        var prev = Array(0...bChars.count)
        var current = Array(repeating: 0, count: bChars.count + 1)
        for i in 1...aChars.count {
            current[0] = i
            for j in 1...bChars.count {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                current[j] = min(
                    prev[j] + 1,
                    current[j - 1] + 1,
                    prev[j - 1] + cost
                )
            }
            swap(&prev, &current)
        }
        return prev[bChars.count]
    }
}
