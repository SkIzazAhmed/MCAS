// SecretGuard.swift
//
// What: looks at copied TEXT and spots secrets by their shape.
//   • API keys / tokens / private keys  → never saved
//   • card numbers (checked with the Luhn checksum) → never saved
//   • one-time codes like 482913         → saved, but deleted after 60 seconds
// Why:  password managers mark their copies (SecretFilter handles that), but an
//       API key copied from a website or a code from an SMS has no mark.
//
// It can be turned off in Settings. Nothing here is logged except the category.

import Foundation

enum SecretGuard {
    enum Verdict: Equatable {
        case allow
        case skip(reason: String)
        /// Save it, but delete it after `seconds`.
        case keepBriefly(seconds: TimeInterval)
    }

    static let oneTimeCodeLifetime: TimeInterval = 60

    /// Well-known token formats. Each must match a whole "word" of the text.
    private static let keyPatterns: [(name: String, regex: NSRegularExpression)] = [
        ("OpenAI/Anthropic-style key", #"\bsk-[A-Za-z0-9_\-]{20,}"#),
        ("GitHub token", #"\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}"#),
        ("GitHub token", #"\bgithub_pat_[A-Za-z0-9_]{22,}"#),
        ("GitLab token", #"\bglpat-[A-Za-z0-9_\-]{20,}"#),
        ("AWS access key", #"\b(AKIA|ASIA)[0-9A-Z]{16}\b"#),
        ("Google API key", #"\bAIza[0-9A-Za-z_\-]{35}"#),
        ("Slack token", #"\bxox[abprs]-[A-Za-z0-9\-]{10,}"#),
        ("Stripe key", #"\b(sk|rk)_(live|test)_[A-Za-z0-9]{16,}"#),
        ("private key", #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#),
    ].map { (name: $0.0, regex: try! NSRegularExpression(pattern: $0.1)) }

    private static let cardShape = try! NSRegularExpression(pattern: #"^[0-9][0-9 \-]{11,22}[0-9]$"#)
    /// 6–8 digits, or 3+3 with a space or dash ("482 913"). Shorter numbers are
    /// too often years or quantities to treat as codes.
    private static let otpShape = try! NSRegularExpression(pattern: #"^([0-9]{6,8}|[0-9]{3}[ \-][0-9]{3})$"#)

    static func classify(_ text: String) -> Verdict {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .allow }
        let fullRange = NSRange(trimmed.startIndex..., in: trimmed)

        for (name, regex) in keyPatterns where regex.firstMatch(in: trimmed, range: fullRange) != nil {
            return .skip(reason: name)
        }

        if cardShape.firstMatch(in: trimmed, range: fullRange) != nil {
            let digits = trimmed.filter(\.isNumber)
            if (13...19).contains(digits.count), passesLuhn(digits) {
                return .skip(reason: "card number")
            }
        }

        if otpShape.firstMatch(in: trimmed, range: fullRange) != nil {
            return .keepBriefly(seconds: oneTimeCodeLifetime)
        }

        return .allow
    }

    /// The checksum every payment card number satisfies. Random 16-digit numbers
    /// (order IDs, phone numbers…) fail it 90% of the time, so they're kept.
    static func passesLuhn(_ digits: String) -> Bool {
        var sum = 0
        for (index, char) in digits.reversed().enumerated() {
            guard var value = char.wholeNumberValue else { return false }
            if index % 2 == 1 {
                value *= 2
                if value > 9 { value -= 9 }
            }
            sum += value
        }
        return sum % 10 == 0
    }
}
