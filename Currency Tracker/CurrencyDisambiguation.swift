//
//  CurrencyDisambiguation.swift
//  Currency Tracker
//
//  Created by Codex on 4/12/26.
//

import Foundation

nonisolated struct CurrencyChoice: Identifiable, Hashable, Sendable {
    let code: String
    let name: String

    var id: String {
        code
    }
}

nonisolated enum CurrencySymbolMatch: Equatable, Sendable {
    case explicit(code: String)
    case ambiguous(symbol: String, candidates: [String])
}

nonisolated enum CurrencyDisambiguation {
    static let ambiguousSymbolCandidates: [String: [String]] = [
        "$": ["USD", "CAD", "AUD", "HKD", "SGD", "NZD"],
        "¥": ["CNY", "JPY"],
        "￥": ["CNY", "JPY"],
        "kr": ["SEK", "NOK", "DKK", "ISK"]
    ]

    private static let explicitSymbolMappings: [(token: String, code: String)] = [
        ("HK$", "HKD"),
        ("US$", "USD"),
        ("CA$", "CAD"),
        ("C$", "CAD"),
        ("AU$", "AUD"),
        ("A$", "AUD"),
        ("NZ$", "NZD"),
        ("S$", "SGD"),
        ("CN¥", "CNY"),
        ("JP¥", "JPY"),
        ("€", "EUR"),
        ("£", "GBP"),
        ("₽", "RUB"),
        ("₩", "KRW"),
        ("₺", "TRY")
    ]

    static func resolve(in text: String) -> CurrencySymbolMatch? {
        let normalizedText = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))

        for mapping in explicitSymbolMappings.sorted(by: { $0.token.count > $1.token.count }) {
            if normalizedText.range(of: mapping.token, options: [.caseInsensitive]) != nil {
                return .explicit(code: mapping.code)
            }
        }

        if containsStandaloneToken("kr", in: normalizedText) {
            if let inferred = inferCandidate(in: normalizedText, candidates: ambiguousSymbolCandidates["kr"] ?? []) {
                return .explicit(code: inferred)
            }
            return .ambiguous(symbol: "kr", candidates: ambiguousSymbolCandidates["kr"] ?? [])
        }

        if normalizedText.contains("￥") {
            if let inferred = inferCandidate(in: normalizedText, candidates: ambiguousSymbolCandidates["￥"] ?? []) {
                return .explicit(code: inferred)
            }
            return .ambiguous(symbol: "￥", candidates: ambiguousSymbolCandidates["￥"] ?? [])
        }

        if normalizedText.contains("¥") {
            if let inferred = inferCandidate(in: normalizedText, candidates: ambiguousSymbolCandidates["¥"] ?? []) {
                return .explicit(code: inferred)
            }
            return .ambiguous(symbol: "¥", candidates: ambiguousSymbolCandidates["¥"] ?? [])
        }

        if normalizedText.contains("$") {
            if let inferred = inferCandidate(in: normalizedText, candidates: ambiguousSymbolCandidates["$"] ?? []) {
                return .explicit(code: inferred)
            }
            return .ambiguous(symbol: "$", candidates: ambiguousSymbolCandidates["$"] ?? [])
        }

        return nil
    }

    private static func containsStandaloneToken(_ token: String, in text: String) -> Bool {
        var currentToken = ""

        for character in text {
            if character.isASCII, character.isLetter {
                currentToken.append(character.lowercased())
            } else {
                if currentToken == token {
                    return true
                }
                currentToken.removeAll(keepingCapacity: true)
            }
        }

        return currentToken == token
    }

    static func choices(for codes: [String]) -> [CurrencyChoice] {
        codes.map { code in
            CurrencyChoice(code: code, name: CurrencyCatalog.name(for: code))
        }
    }

    private static func inferCandidate(in text: String, candidates: [String]) -> String? {
        guard !candidates.isEmpty else {
            return nil
        }

        let normalizedText = CurrencyInputNormalization.normalizedSearchText(text)
        guard !normalizedText.isEmpty else {
            return nil
        }

        var scores: [String: Int] = [:]

        for code in candidates {
            guard let info = CurrencyCatalog.info(for: code) else {
                continue
            }

            let tokens = [info.code, info.name, info.englishName] + info.aliases
            for token in tokens {
                let normalizedToken = CurrencyInputNormalization.normalizedSearchText(token)
                guard !normalizedToken.isEmpty else {
                    continue
                }

                if normalizedText.contains(normalizedToken) {
                    scores[code] = max(scores[code] ?? 0, normalizedToken.count)
                }
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

        if ranked.count > 1, best.value == ranked[1].value {
            return nil
        }

        return best.key
    }
}
