import AppKit
import SwiftUI

/// The six fixed profile colours (PRD V8 Change 4). There is no free colour
/// picker on purpose: six deliberate colours stay distinguishable and legible
/// under white text, arbitrary ones do not.
enum ProfileColor: String, CaseIterable, Identifiable, Codable {
    case navy
    case slate
    case bronze
    case wine
    case plum
    case rose

    var id: String { rawValue }

    static let fallback: ProfileColor = .navy

    /// Colour ids saved before V8, mapped to their V8 replacement.
    static let legacyIDs: [String: ProfileColor] = [
        "indigo": .navy,
        "teal": .slate,
        "bronze": .bronze,
        "clay": .wine,
        "violet": .plum,
        "forest": .rose
    ]

    /// Unknown ids resolve rather than crash, so a hand-edited profiles.json with
    /// a typo still opens. Pre-V8 ids resolve to their replacement.
    static func named(_ id: String?) -> ProfileColor {
        guard let id else { return fallback }
        if let match = ProfileColor(rawValue: id) { return match }
        return legacyIDs[id] ?? fallback
    }

    /// The colour assigned to a new profile: the first one nobody is using yet,
    /// in palette order. Sharing a colour is allowed, just never the default.
    static func firstUnused(in profiles: [Profile]) -> ProfileColor {
        let taken = Set(profiles.map { named($0.colorId) })
        return allCases.first { !taken.contains($0) } ?? allCases[0]
    }

    var displayName: String {
        switch self {
        case .navy: return "Navy"
        case .slate: return "Slate"
        case .bronze: return "Bronze"
        case .wine: return "Wine"
        case .plum: return "Plum"
        case .rose: return "Rose"
        }
    }

    /// Solid card colour, also the active-role panel glow.
    var hex: String {
        switch self {
        case .navy: return "26296E"
        case .slate: return "2B4752"
        case .bronze: return "4C412F"
        case .wine: return "69212F"
        case .plum: return "3E1851"
        case .rose: return "953D53"
        }
    }

    var color: Color { Color(hex: hex) }

    var midTone: NSColor {
        NSColor(color)
    }
}

extension Color {
    /// Six-digit RRGGBB only; the palette is the only caller and it is fixed.
    init(hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = UInt32(cleaned, radix: 16) ?? 0
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}
