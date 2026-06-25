import Foundation

enum PolishOutputSanitizer {
    private static let wrappingQuotePairs: [(String, String)] = [
        ("\"", "\""),
        ("'", "'"),
        ("`", "`"),
        ("«", "»"),
        ("\u{201C}", "\u{201D}"),
        ("\u{2018}", "\u{2019}"),
    ]

    static func sanitize(_ text: String) -> String {
        stripWrappingQuotes(stripThinkingChannels(text))
    }

    static func stripThinkingChannels(_ text: String) -> String {
        let contentBlockPattern = #/(?s)<\|channel>content\s*(.*?)(?:<channel\|>|$)/#
        let thinkingBlockPattern = #/(?s)<\|channel>thought\s*.*?<channel\|>/#

        if let match = text.firstMatch(of: contentBlockPattern) {
            return String(match.output.1).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var cleaned = text.replacing(thinkingBlockPattern, with: "")
        cleaned = cleaned
            .replacingOccurrences(of: "<|channel>content\n", with: "")
            .replacingOccurrences(of: "<|channel>content", with: "")
            .replacingOccurrences(of: "<channel|>", with: "")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func stripWrappingQuotes(_ text: String) -> String {
        var stripped = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var changed = true

        while changed, stripped.count >= 2 {
            changed = false
            for (openQuote, closeQuote) in wrappingQuotePairs {
                guard stripped.hasPrefix(openQuote), stripped.hasSuffix(closeQuote) else { continue }
                stripped = String(stripped.dropFirst(openQuote.count).dropLast(closeQuote.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                changed = true
                break
            }
        }

        return stripped
    }
}
