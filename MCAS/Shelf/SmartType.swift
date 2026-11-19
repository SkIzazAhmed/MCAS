// SmartType.swift
//
// What: recognises what a copied piece of text IS, so the shelf can show it
//       better and offer the right quick actions:
//   • link   → shows the website name; "Open Link"
//   • color  → shows a swatch; "Copy as HEX" / "Copy as RGB"
//   • email  → "New Email"
//   • code   → shown in a code font
// Why:  PRD "smart types". Everything is worked out on your Mac from the text
//       alone: no internet requests (no fetching page titles or icons).

import Foundation

enum SmartType: Equatable {
    case link(URL)
    case color(red: Int, green: Int, blue: Int)
    case email(String)
    case code
    case none

    static func detect(kind: ClipKind, text: String) -> SmartType {
        guard kind == .text || kind == .richText || kind == .url else { return .none }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }

        if ClipReader.isWebURL(trimmed), let url = URL(string: trimmed) {
            return .link(url)
        }
        if let color = parseColor(trimmed) {
            return color
        }
        if matches(emailPattern, trimmed) {
            return .email(trimmed)
        }
        if looksLikeCode(trimmed) {
            return .code
        }
        return .none
    }

    // MARK: - Colors

    private static let hexPattern = try! NSRegularExpression(pattern: #"^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$"#)
    private static let rgbPattern = try! NSRegularExpression(
        pattern: #"^rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*(,\s*[\d.]+\s*)?\)$"#,
        options: .caseInsensitive
    )

    /// "#FF6B00", "#f60" or "rgb(255, 107, 0)". A "#" is required for hex, so
    /// ordinary words that happen to be hex ("facade", "decade") aren't colors.
    static func parseColor(_ text: String) -> SmartType? {
        let range = NSRange(text.startIndex..., in: text)
        if let match = hexPattern.firstMatch(in: text, range: range),
           let hexRange = Range(match.range(at: 1), in: text) {
            var hex = String(text[hexRange])
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard let value = Int(hex, radix: 16) else { return nil }
            return .color(red: (value >> 16) & 0xFF, green: (value >> 8) & 0xFF, blue: value & 0xFF)
        }
        if let match = rgbPattern.firstMatch(in: text, range: range) {
            let parts = (1...3).compactMap { index -> Int? in
                guard let r = Range(match.range(at: index), in: text) else { return nil }
                return Int(text[r])
            }
            guard parts.count == 3, parts.allSatisfy({ (0...255).contains($0) }) else { return nil }
            return .color(red: parts[0], green: parts[1], blue: parts[2])
        }
        return nil
    }

    var hexString: String? {
        guard case let .color(r, g, b) = self else { return nil }
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    var rgbString: String? {
        guard case let .color(r, g, b) = self else { return nil }
        return "rgb(\(r), \(g), \(b))"
    }

    // MARK: - Email and code

    private static let emailPattern = try! NSRegularExpression(
        pattern: #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$"#,
        options: .caseInsensitive
    )

    /// Several lines with at least two code-ish signs (braces, semicolons,
    /// arrows, keywords). Good enough to pick a code font; never blocks anything.
    static func looksLikeCode(_ text: String) -> Bool {
        guard text.contains("\n") else { return false }
        let signs = ["{", ";", "=>", "->", "func ", "def ", "return ", "import ", "const ", "let ", "var ", "class ", "#include", "</"]
        return signs.filter { text.contains($0) }.count >= 2
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}

extension ClipItem {
    var smartType: SmartType {
        SmartType.detect(kind: kind, text: previewText)
    }
}
