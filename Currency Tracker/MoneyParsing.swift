//
//  MoneyParsing.swift
//  Currency Tracker
//
//  Created by Codex on 4/12/26.
//

import Foundation

nonisolated enum MoneyParsing {
    nonisolated struct ParsedAmount: Equatable, Sendable {
        let amount: AmountResolution
        let currency: CurrencyResolution
    }

    nonisolated enum AmountResolution: Equatable, Sendable {
        case resolved(Decimal)
        case ambiguous(rawText: String, options: [AmountOption])
    }

    nonisolated struct AmountOption: Identifiable, Equatable, Sendable {
        let value: Decimal
        let description: String

        var id: String {
            "\(description)|\(NSDecimalNumber(decimal: value).stringValue)"
        }
    }

    nonisolated enum CurrencyResolution: Equatable, Sendable {
        case explicit(code: String)
        case ambiguous(symbol: String, candidates: [String])
        case missing
    }

    static func parse(_ text: String) -> ParsedAmount? {
        let normalizedText = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{3000}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let amountText = extractAmountCandidate(from: normalizedText),
              let amount = parseAmountResolution(from: amountText) else {
            return nil
        }

        let analysisText = normalizedText.replacingOccurrences(of: amountText, with: " ")
        let nearbyContext = amountNearbyContext(in: normalizedText, amountText: amountText)

        if let explicitCode = explicitCurrencyCode(in: nearbyContext)
            ?? explicitCurrencyCode(in: analysisText)
            ?? CurrencyInputNormalization.detectCurrency(in: nearbyContext) {
            return ParsedAmount(amount: amount, currency: .explicit(code: explicitCode))
        }

        if let symbolMatch = CurrencyDisambiguation.resolve(in: normalizedText) {
            switch symbolMatch {
            case .explicit(let code):
                return ParsedAmount(amount: amount, currency: .explicit(code: code))
            case .ambiguous(let symbol, let candidates):
                return ParsedAmount(amount: amount, currency: .ambiguous(symbol: symbol, candidates: candidates))
            }
        }

        return ParsedAmount(amount: amount, currency: .missing)
    }

    private static func explicitCurrencyCode(in text: String) -> String? {
        var token = ""

        func flushToken() -> String? {
            defer { token.removeAll(keepingCapacity: true) }
            guard token.count == 3 else {
                return nil
            }

            let candidate = token.uppercased()
            return CurrencyCatalog.info(for: candidate) != nil ? candidate : nil
        }

        for character in text {
            if character.isASCII, character.isLetter {
                token.append(character)
            } else if let resolved = flushToken() {
                return resolved
            }
        }

        return flushToken()
    }

    private static func extractAmountCandidate(from text: String) -> String? {
        var bestCandidate: String?
        var currentCandidate = ""

        func commitCurrentCandidate() {
            let trimmedCandidate = currentCandidate
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,'’"))

            defer { currentCandidate.removeAll(keepingCapacity: true) }

            guard trimmedCandidate.contains(where: \.isNumber) else {
                return
            }

            let shouldReplaceBest: Bool
            if let bestCandidate {
                let trimmedBest = bestCandidate.filter(\.isNumber).count
                let trimmedCurrent = trimmedCandidate.filter(\.isNumber).count
                shouldReplaceBest = trimmedCurrent > trimmedBest || (
                    trimmedCurrent == trimmedBest && trimmedCandidate.count > bestCandidate.count
                )
            } else {
                shouldReplaceBest = true
            }

            if shouldReplaceBest {
                bestCandidate = trimmedCandidate
            }
        }

        for character in text {
            if isAmountCharacter(character) {
                currentCandidate.append(character)
            } else {
                commitCurrentCandidate()
            }
        }

        commitCurrentCandidate()
        return bestCandidate
    }

    private static func parseAmountResolution(from amountText: String) -> AmountResolution? {
        let candidate = normalizedAmountText(amountText)
        guard candidate.contains(where: \.isNumber) else {
            return nil
        }

        if let ambiguousSeparator = ambiguousSingleSeparator(in: candidate) {
            let options = amountOptions(for: candidate, ambiguousSeparator: ambiguousSeparator)
            if options.count > 1 {
                return .ambiguous(rawText: amountText, options: options)
            }
        }

        guard let resolved = parseDecimal(from: candidate) else {
            return nil
        }

        return .resolved(resolved)
    }

    private static func amountOptions(
        for amountText: String,
        ambiguousSeparator: Character
    ) -> [AmountOption] {
        var options: [AmountOption] = []

        if let groupedValue = parseAsGroupedInteger(from: amountText, separator: ambiguousSeparator) {
            options.append(
                AmountOption(
                    value: groupedValue,
                    description: "按千分位解析"
                )
            )
        }

        if let decimalValue = parseAsDecimalValue(from: amountText, decimalSeparator: ambiguousSeparator) {
            options.append(
                AmountOption(
                    value: decimalValue,
                    description: "按小数解析"
                )
            )
        }

        var seen = Set<String>()
        return options.filter { option in
            seen.insert(option.id).inserted
        }
    }

    private static func parseDecimal(from amountText: String) -> Decimal? {
        let candidate = normalizedAmountText(amountText)
        let decimalSeparator = inferredDecimalSeparator(in: candidate)
        return normalizedDecimal(from: candidate, decimalSeparator: decimalSeparator)
    }

    private static func normalizedAmountText(_ amountText: String) -> String {
        amountText
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{3000}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func inferredDecimalSeparator(in candidate: String) -> Character? {
        let commaCount = candidate.filter { $0 == "," }.count
        let dotCount = candidate.filter { $0 == "." }.count

        if commaCount > 0 && dotCount > 0 {
            return lastSeparator(in: candidate)
        }

        if commaCount > 0 {
            return inferSeparator(in: candidate, separator: ",", count: commaCount)
        }

        if dotCount > 0 {
            return inferSeparator(in: candidate, separator: ".", count: dotCount)
        }

        return nil
    }

    private static func normalizedDecimal(
        from amountText: String,
        decimalSeparator: Character?
    ) -> Decimal? {
        var candidate = amountText
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")

        switch decimalSeparator {
        case ",":
            candidate = candidate.replacingOccurrences(of: ".", with: "")
            if candidate.filter({ $0 == "," }).count > 1 {
                candidate = candidate.replacingOccurrences(of: ",", with: "")
            } else {
                candidate = candidate.replacingOccurrences(of: ",", with: ".")
            }
        case ".":
            candidate = candidate.replacingOccurrences(of: ",", with: "")
        default:
            candidate = candidate
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: ".", with: "")
        }

        let validationPattern = #"^[+-]?\d+(?:\.\d+)?$"#
        guard candidate.range(of: validationPattern, options: .regularExpression) != nil else {
            return nil
        }

        return Decimal(string: candidate, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func ambiguousSingleSeparator(in text: String) -> Character? {
        let compact = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")

        for separator in [",", "."] {
            let separatorCharacter = Character(separator)
            guard compact.filter({ $0 == separatorCharacter }).count == 1 else {
                continue
            }

            let groups = compact.split(separator: separatorCharacter, omittingEmptySubsequences: false)
            guard groups.count == 2 else {
                continue
            }

            let leadingDigits = groups[0].filter(\.isNumber).count
            let trailingDigits = groups[1].filter(\.isNumber).count
            guard leadingDigits == 1, trailingDigits == 3 else {
                continue
            }

            return separatorCharacter
        }

        return nil
    }

    private static func parseAsGroupedInteger(
        from amountText: String,
        separator: Character
    ) -> Decimal? {
        let stripped = amountText
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: String(separator), with: "")

        return normalizedDecimal(from: stripped, decimalSeparator: nil)
    }

    private static func parseAsDecimalValue(
        from amountText: String,
        decimalSeparator: Character
    ) -> Decimal? {
        normalizedDecimal(from: amountText, decimalSeparator: decimalSeparator)
    }

    private static func inferSeparator(
        in text: String,
        separator: Character,
        count: Int
    ) -> Character? {
        let groups = text
            .split(separator: separator, omittingEmptySubsequences: false)
            .map { $0.filter(\.isNumber) }

        guard let lastGroup = groups.last else {
            return nil
        }

        guard groups.count >= 2 else {
            return nil
        }

        if count == 1 {
            switch lastGroup.count {
            case 1...2:
                return separator
            case 3:
                return nil
            default:
                return nil
            }
        }

        let middleGroups = groups.dropFirst().dropLast()
        let middleGroupsAreThousands = middleGroups.allSatisfy { $0.count == 3 }

        if lastGroup.count == 3 && middleGroupsAreThousands {
            return nil
        }

        if middleGroupsAreThousands, (1...2).contains(lastGroup.count) {
            return separator
        }

        return nil
    }

    private static func lastSeparator(in text: String) -> Character? {
        let lastComma = text.lastIndex(of: ",")
        let lastDot = text.lastIndex(of: ".")

        switch (lastComma, lastDot) {
        case let (comma?, dot?):
            return comma > dot ? "," : "."
        case (_?, nil):
            return ","
        case (nil, _?):
            return "."
        case (nil, nil):
            return nil
        }
    }

    private static func isAmountCharacter(_ character: Character) -> Bool {
        if character.isNumber {
            return true
        }

        return " +-.,'’".contains(character)
    }

    private static func amountNearbyContext(in text: String, amountText: String) -> String {
        guard let range = text.range(of: amountText) else {
            return text
        }

        let windowSize = 28
        let prefix = String(text[..<range.lowerBound].suffix(windowSize))
        let suffix = String(text[range.upperBound...].prefix(windowSize))
        return "\(prefix) \(suffix)"
    }
}
