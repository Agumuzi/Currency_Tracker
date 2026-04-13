//
//  CurrencyInputNormalization.swift
//  Currency Tracker
//
//  Created by Codex on 4/12/26.
//

import Foundation

nonisolated enum CurrencyInputNormalization {
    static let commonShortcutCodes = ["USD", "CNY", "EUR", "RUB", "JPY"]

    static func normalize(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let uppercasedCode = trimmed.uppercased()
        if CurrencyCatalog.info(for: uppercasedCode) != nil {
            return uppercasedCode
        }

        let normalizedInput = normalizedSearchText(trimmed)
        if let exactMatch = aliasEntries.first(where: { $0.normalized == normalizedInput }) {
            return exactMatch.code
        }

        return detectCurrency(in: trimmed)
    }

    static func detectCurrency(in text: String) -> String? {
        let normalizedFullText = normalizedSearchText(text)
        guard !normalizedFullText.isEmpty else {
            return nil
        }

        let normalizedTokens = Set(tokenCandidates(in: text))
        var scores: [String: Int] = [:]

        for entry in aliasEntries {
            if entry.requiresExactTokenMatch {
                if normalizedTokens.contains(entry.normalized) {
                    let score = 120 + min(entry.normalized.count, 16)
                    scores[entry.code] = max(scores[entry.code] ?? 0, score)
                }
            } else if normalizedFullText.contains(entry.normalized) {
                let score = 72 + min(entry.normalized.count, 20)
                scores[entry.code] = max(scores[entry.code] ?? 0, score)
            }
        }

        let ranked = scores.sorted { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key < rhs.key
            }
            return lhs.value > rhs.value
        }

        guard let best = ranked.first else {
            return nil
        }

        if ranked.count > 1, best.value - ranked[1].value < 8 {
            return nil
        }

        return best.key
    }

    static func normalizedSearchText(_ string: String) -> String {
        normalizedKey(for: string)
    }

    private struct AliasEntry: Sendable {
        let code: String
        let normalized: String
        let requiresExactTokenMatch: Bool
    }

    private static let aliasEntries: [AliasEntry] = {
        var seen = Set<String>()
        var entries: [AliasEntry] = []

        func append(code: String, alias: String, requiresExactTokenMatch: Bool? = nil) {
            let normalized = normalizedKey(for: alias)
            guard !normalized.isEmpty else {
                return
            }

            let exactMatch = requiresExactTokenMatch ?? (normalized.count <= 3)
            let key = "\(code)|\(normalized)|\(exactMatch)"
            guard seen.insert(key).inserted else {
                return
            }

            entries.append(
                AliasEntry(
                    code: code,
                    normalized: normalized,
                    requiresExactTokenMatch: exactMatch
                )
            )
        }

        for currency in CurrencyCatalog.all {
            append(code: currency.code, alias: currency.code, requiresExactTokenMatch: true)
            append(code: currency.code, alias: currency.name, requiresExactTokenMatch: false)
            append(code: currency.code, alias: currency.englishName, requiresExactTokenMatch: false)
            for alias in currency.aliases {
                append(code: currency.code, alias: alias)
            }
        }

        let manualAliases: [String: [String]] = [
            "USD": ["usdollar", "usdollars", "dollar", "dollars", "us dollar", "us dollars"],
            "CNY": ["cnh", "renminbi", "yuan", "chineseyuan", "china yuan"],
            "EUR": ["euro", "euros"],
            "RUB": ["俄罗斯", "俄罗斯卢布", "rouble", "ruble", "rubles", "roubles"],
            "JPY": ["yen", "japaneseyen", "日圆"],
            "GBP": ["pound", "pounds", "sterling", "british pound"],
            "HKD": ["hongkongdollar", "hong kong dollar"],
            "SGD": ["singaporedollar", "singapore dollar"],
            "CAD": ["canadiandollar", "canadian dollar"],
            "AUD": ["australiandollar", "australian dollar"],
            "NZD": ["newzealanddollar", "new zealand dollar"],
            "SEK": ["swedishkrona", "swedish krona"],
            "NOK": ["norwegiankrone", "norwegian krone"],
            "DKK": ["danishkrone", "danish krone"],
            "ISK": ["icelandickrona", "icelandic krona"],
            "TRY": ["tr", "turkish lira", "turkishlira", "土耳其", "土耳其里拉", "turkey"],
            "AED": ["uae dirham", "united arab emirates", "dubai"]
        ]

        for (code, values) in manualAliases {
            for value in values {
                append(code: code, alias: value)
            }
        }

        return entries.sorted {
            if $0.requiresExactTokenMatch != $1.requiresExactTokenMatch {
                return $0.requiresExactTokenMatch
            }

            return $0.normalized.count > $1.normalized.count
        }
    }()

    private static func normalizedKey(for string: String) -> String {
        let halfWidth = string.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? string
        let lowercased = halfWidth.lowercased()
        return lowercased.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) || CharacterSet.letters.contains($0) }
            .map(String.init)
            .joined()
    }

    private static func tokenCandidates(in string: String) -> [String] {
        let normalized = string.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? string
        let separated = normalized.unicodeScalars.map { scalar -> String in
            CharacterSet.alphanumerics.contains(scalar) || CharacterSet.letters.contains(scalar)
                ? String(scalar)
                : " "
        }.joined()

        return separated
            .split(whereSeparator: \.isWhitespace)
            .map { normalizedKey(for: String($0)) }
            .filter { !$0.isEmpty }
    }
}
