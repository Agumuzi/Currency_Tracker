//
//  Item.swift
//  Currency Tracker
//
//  Created by Thomas Tao on 4/10/26.
//

import Foundation
import Observation
import ServiceManagement
import SwiftUI

nonisolated struct CurrencyInfo: Identifiable, Codable, Hashable, Sendable {
    let code: String
    let name: String
    let englishName: String
    let aliases: [String]

    var id: String {
        code
    }
}

nonisolated struct CurrencyPair: Identifiable, Codable, Hashable, Sendable {
    let baseCode: String
    let quoteCode: String
    let baseAmount: Int

    var id: String {
        "\(baseCode)-\(quoteCode)-\(baseAmount)"
    }

    var displayName: String {
        "\(CurrencyCatalog.name(for: baseCode)) / \(CurrencyCatalog.name(for: quoteCode))"
    }

    var compactLabel: String {
        "\(baseCode)/\(quoteCode)"
    }

    var subtitle: String {
        "\(baseAmount) \(baseCode) → \(quoteCode)"
    }

    var requiresCBR: Bool {
        quoteCode == "RUB"
    }

    static let defaults: [CurrencyPair] = [
        CurrencyPair(baseCode: "USD", quoteCode: "RUB", baseAmount: 1),
        CurrencyPair(baseCode: "CNY", quoteCode: "RUB", baseAmount: 1),
        CurrencyPair(baseCode: "EUR", quoteCode: "RUB", baseAmount: 1),
        CurrencyPair(baseCode: "USD", quoteCode: "CNY", baseAmount: 1),
        CurrencyPair(baseCode: "EUR", quoteCode: "CNY", baseAmount: 1)
    ]
}

nonisolated enum CurrencyCatalog {
    private static let knownCurrencies: [CurrencyInfo] = [
        CurrencyInfo(code: "USD", name: "美元", englishName: "US Dollar", aliases: ["美金", "dollar", "dollars", "us dollar", "united states", "usa", "america"]),
        CurrencyInfo(code: "CNY", name: "人民币", englishName: "Chinese Yuan", aliases: ["rmb", "renminbi", "yuan", "china", "chinese yuan", "元"]),
        CurrencyInfo(code: "EUR", name: "欧元", englishName: "Euro", aliases: ["euro", "euros", "europe"]),
        CurrencyInfo(code: "RUB", name: "卢布", englishName: "Russian Ruble", aliases: ["ruble", "rubles", "rouble", "roubles", "russia", "russian"]),
        CurrencyInfo(code: "GBP", name: "英镑", englishName: "British Pound", aliases: ["pound", "pounds", "sterling", "united kingdom", "britain", "uk"]),
        CurrencyInfo(code: "JPY", name: "日元", englishName: "Japanese Yen", aliases: ["yen", "japan", "japanese"]),
        CurrencyInfo(code: "HKD", name: "港币", englishName: "Hong Kong Dollar", aliases: ["港元", "hong kong", "hongkong"]),
        CurrencyInfo(code: "SGD", name: "新加坡元", englishName: "Singapore Dollar", aliases: ["singapore", "singapore dollar"]),
        CurrencyInfo(code: "CHF", name: "瑞士法郎", englishName: "Swiss Franc", aliases: ["franc", "swiss", "switzerland"]),
        CurrencyInfo(code: "AUD", name: "澳元", englishName: "Australian Dollar", aliases: ["australia", "australian dollar"]),
        CurrencyInfo(code: "CAD", name: "加元", englishName: "Canadian Dollar", aliases: ["canada", "canadian dollar"]),
        CurrencyInfo(code: "NZD", name: "新西兰元", englishName: "New Zealand Dollar", aliases: ["new zealand", "newzealand", "kiwi dollar"]),
        CurrencyInfo(code: "SEK", name: "瑞典克朗", englishName: "Swedish Krona", aliases: ["sweden", "swedish"]),
        CurrencyInfo(code: "NOK", name: "挪威克朗", englishName: "Norwegian Krone", aliases: ["norway", "norwegian"]),
        CurrencyInfo(code: "DKK", name: "丹麦克朗", englishName: "Danish Krone", aliases: ["denmark", "danish"]),
        CurrencyInfo(code: "ISK", name: "冰岛克朗", englishName: "Icelandic Krona", aliases: ["iceland", "icelandic"]),
        CurrencyInfo(code: "KRW", name: "韩元", englishName: "South Korean Won", aliases: ["won", "korea", "south korea", "korean"]),
        CurrencyInfo(code: "THB", name: "泰铢", englishName: "Thai Baht", aliases: ["baht", "thailand", "thai"]),
        CurrencyInfo(code: "TRY", name: "土耳其里拉", englishName: "Turkish Lira", aliases: ["turkey", "turkish", "turkish lira", "土耳其", "tr"]),
        CurrencyInfo(code: "AED", name: "阿联酋迪拉姆", englishName: "UAE Dirham", aliases: ["dirham", "uae", "united arab emirates", "dubai"])
    ]

    private static let generatedCodeExclusions: Set<String> = [
        "XXX",
        "XTS"
    ]

    private static let englishLocale = Locale(identifier: "en_US_POSIX")

    static let all: [CurrencyInfo] = {
        let knownCodes = Set(knownCurrencies.map(\.code))
        let generatedCurrencies = Locale.commonISOCurrencyCodes
            .map { $0.uppercased() }
            .filter { code in
                code.count == 3
                    && knownCodes.contains(code) == false
                    && generatedCodeExclusions.contains(code) == false
            }
            .sorted()
            .map { code in
                let englishName = englishLocale.localizedString(forCurrencyCode: code) ?? code
                return CurrencyInfo(
                    code: code,
                    name: englishName,
                    englishName: englishName,
                    aliases: [englishName]
                )
            }

        return knownCurrencies + generatedCurrencies
    }()

    static func name(for code: String) -> String {
        let normalizedCode = code.uppercased()
        guard let currency = info(for: normalizedCode) else {
            return normalizedCode
        }

        if knownCurrencies.contains(where: { $0.code == currency.code }) {
            return String(localized: String.LocalizationValue(currency.name))
        }

        return Locale.autoupdatingCurrent.localizedString(forCurrencyCode: currency.code)
            ?? currency.englishName
    }

    static func englishName(for code: String) -> String {
        let normalizedCode = code.uppercased()
        return info(for: normalizedCode)?.englishName ?? normalizedCode
    }

    static func flag(for code: String) -> String {
        switch code {
        case "USD": "🇺🇸"
        case "CNY": "🇨🇳"
        case "EUR": "🇪🇺"
        case "RUB": "🇷🇺"
        case "GBP": "🇬🇧"
        case "JPY": "🇯🇵"
        case "HKD": "🇭🇰"
        case "SGD": "🇸🇬"
        case "CHF": "🇨🇭"
        case "AUD": "🇦🇺"
        case "CAD": "🇨🇦"
        case "NZD": "🇳🇿"
        case "SEK": "🇸🇪"
        case "NOK": "🇳🇴"
        case "DKK": "🇩🇰"
        case "ISK": "🇮🇸"
        case "KRW": "🇰🇷"
        case "THB": "🇹🇭"
        case "TRY": "🇹🇷"
        case "AED": "🇦🇪"
        default: "🏳️"
        }
    }

    static func info(for code: String) -> CurrencyInfo? {
        let normalizedCode = code.uppercased()
        return all.first { $0.code == normalizedCode }
    }

    static func matchesSearch(_ currency: CurrencyInfo, query: String) -> Bool {
        let normalizedQuery = CurrencyInputNormalization.normalizedSearchText(query)
        guard !normalizedQuery.isEmpty else {
            return true
        }

        return searchableTokens(for: currency).contains { token in
            CurrencyInputNormalization.normalizedSearchText(token).contains(normalizedQuery)
        }
    }

    static func searchableTokens(for currency: CurrencyInfo) -> [String] {
        var tokens = [currency.code, currency.name, currency.englishName]
        if let localizedName = Locale.autoupdatingCurrent.localizedString(forCurrencyCode: currency.code) {
            tokens.append(localizedName)
        }
        return tokens + currency.aliases
    }

    static func supportedPair(baseCode: String, quoteCode: String, baseAmount: Int = 1) -> CurrencyPair? {
        guard baseCode != quoteCode else {
            return nil
        }

        guard baseCode != "RUB" else {
            return nil
        }

        guard info(for: baseCode) != nil, info(for: quoteCode) != nil else {
            return nil
        }

        return CurrencyPair(baseCode: baseCode, quoteCode: quoteCode, baseAmount: baseAmount)
    }

    static func supportedQuotes(for baseCode: String) -> [CurrencyInfo] {
        all.filter { supportedPair(baseCode: baseCode, quoteCode: $0.code) != nil }
    }
}

nonisolated enum ExchangeSource: String, Codable, Sendable, CaseIterable {
    case custom = "CustomAPI"
    case twelveData = "TwelveData"
    case exchangeRateAPI = "ExchangeRateAPI"
    case openExchangeRates = "OpenExchangeRates"
    case fixer = "Fixer"
    case currencyLayer = "CurrencyLayer"
    case cbr = "CBR"
    case ecb = "ECB"
    case frankfurter = "Frankfurter"
    case floatRates = "FloatRates"
    case currencyAPI = "CurrencyAPI"

    var displayName: String {
        switch self {
        case .custom:
            "Custom API"
        case .twelveData:
            "Twelve Data"
        case .exchangeRateAPI:
            "ExchangeRate-API"
        case .openExchangeRates:
            "Open Exchange Rates"
        case .fixer:
            "Fixer"
        case .currencyLayer:
            "Currencylayer"
        case .cbr:
            "CBR"
        case .ecb:
            "ECB Direct"
        case .frankfurter:
            "Frankfurter"
        case .floatRates:
            "FloatRates"
        case .currencyAPI:
            "Currency API"
        }
    }
}

nonisolated enum MenuBarDisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case iconOnly
    case featuredRate
    case compactPair

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .iconOnly:
            String(localized: "只显示图标")
        case .featuredRate:
            String(localized: "显示重点汇率")
        case .compactPair:
            String(localized: "显示货币对和汇率")
        }
    }
}

nonisolated enum CurrencyDisplayFormatting {
    static let displayBaseAmountOptions = [1, 100]
    static let fractionDigitOptions = [2, 4, 6]

    static func normalizedDisplayBaseAmount(_ value: Int) -> Int {
        displayBaseAmountOptions.contains(value) ? value : 1
    }

    static func normalizedFractionDigits(_ value: Int) -> Int {
        fractionDigitOptions.contains(value) ? value : 4
    }

    static func rateText(
        snapshotRate: Double,
        pairBaseAmount: Int,
        displayBaseAmount: Int,
        fractionDigits: Int
    ) -> String {
        let unitRate = snapshotRate / Double(max(pairBaseAmount, 1))
        let displayRate = unitRate * Double(normalizedDisplayBaseAmount(displayBaseAmount))
        return localizedNumber(displayRate, fractionDigits: fractionDigits)
    }

    static func localizedNumber(_ value: Double, fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = normalizedFractionDigits(fractionDigits)
        formatter.maximumFractionDigits = normalizedFractionDigits(fractionDigits)
        return formatter.string(from: value as NSNumber) ?? String(format: "%.\(normalizedFractionDigits(fractionDigits))f", value)
    }

    static func plainNumber(_ value: Decimal, fractionDigits: Int) -> String {
        plainNumber(NSDecimalNumber(decimal: value).doubleValue, fractionDigits: fractionDigits)
    }

    static func plainNumber(_ value: Double, fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = normalizedFractionDigits(fractionDigits)
        formatter.maximumFractionDigits = normalizedFractionDigits(fractionDigits)
        return formatter.string(from: value as NSNumber) ?? String(format: "%.\(normalizedFractionDigits(fractionDigits))f", value)
    }
}

nonisolated enum AmountInputParsing {
    static func parseDecimal(_ text: String) -> Decimal? {
        let normalizedText = normalizedInputText(text)

        switch parseArithmeticExpression(normalizedText) {
        case .value(let value):
            return value
        case .invalid:
            return nil
        case .notExpression:
            break
        }

        guard let amountText = extractAmountCandidate(from: normalizedText) else {
            return nil
        }

        return parseDecimalCandidate(amountText)
    }

    private static func normalizedInputText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{3000}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseDecimalCandidate(_ amountText: String) -> Decimal? {
        let compact = amountText
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard compact.contains(where: \.isNumber) else {
            return nil
        }

        let normalized = normalizeDecimalSeparators(in: compact)
        let validationPattern = #"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$"#
        guard normalized.range(of: validationPattern, options: .regularExpression) != nil else {
            return nil
        }

        let decimalText: String
        if normalized.hasPrefix(".") {
            decimalText = "0\(normalized)"
        } else if normalized.hasSuffix(".") {
            decimalText = String(normalized.dropLast())
        } else {
            decimalText = normalized
        }

        return Decimal(string: decimalText, locale: Locale(identifier: "en_US_POSIX"))
    }

    private enum ArithmeticExpressionParseResult {
        case notExpression
        case invalid
        case value(Decimal)
    }

    private static func parseArithmeticExpression(_ text: String) -> ArithmeticExpressionParseResult {
        var expression = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var hasTrailingEquals = false

        while expression.last == "=" {
            hasTrailingEquals = true
            expression = String(expression.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let hasOperator = containsArithmeticOperator(in: expression)
        guard hasTrailingEquals || hasOperator else {
            return .notExpression
        }

        guard !expression.isEmpty,
              expression.contains(where: \.isNumber),
              expression.allSatisfy(isArithmeticExpressionCharacter) else {
            return .invalid
        }

        var parser = ArithmeticExpressionParser(text: expression)
        guard let value = parser.parse() else {
            return .invalid
        }

        return .value(value)
    }

    private static func containsArithmeticOperator(in text: String) -> Bool {
        var index = text.startIndex

        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }

        if index < text.endIndex, text[index] == "+" || text[index] == "-" {
            index = text.index(after: index)
        }

        while index < text.endIndex {
            if "+-*/".contains(text[index]) {
                return true
            }
            index = text.index(after: index)
        }

        return false
    }

    private static func isArithmeticExpressionCharacter(_ character: Character) -> Bool {
        character.isNumber
            || character.isWhitespace
            || ".,'’+-*/()".contains(character)
    }

    private struct ArithmeticExpressionParser {
        private let characters: [Character]
        private var index = 0

        init(text: String) {
            characters = Array(text)
        }

        mutating func parse() -> Decimal? {
            guard let value = parseExpression() else {
                return nil
            }

            skipWhitespace()
            return index == characters.count ? value : nil
        }

        private mutating func parseExpression() -> Decimal? {
            guard var value = parseTerm() else {
                return nil
            }

            while true {
                skipWhitespace()

                if match("+") {
                    guard let rhs = parseTerm(),
                          let result = Self.apply("+", lhs: value, rhs: rhs) else {
                        return nil
                    }
                    value = result
                } else if match("-") {
                    guard let rhs = parseTerm(),
                          let result = Self.apply("-", lhs: value, rhs: rhs) else {
                        return nil
                    }
                    value = result
                } else {
                    return value
                }
            }
        }

        private mutating func parseTerm() -> Decimal? {
            guard var value = parseFactor() else {
                return nil
            }

            while true {
                skipWhitespace()

                if match("*") {
                    guard let rhs = parseFactor(),
                          let result = Self.apply("*", lhs: value, rhs: rhs) else {
                        return nil
                    }
                    value = result
                } else if match("/") {
                    guard let rhs = parseFactor(),
                          let result = Self.apply("/", lhs: value, rhs: rhs) else {
                        return nil
                    }
                    value = result
                } else {
                    return value
                }
            }
        }

        private mutating func parseFactor() -> Decimal? {
            skipWhitespace()

            if match("+") {
                return parseFactor()
            }

            if match("-") {
                guard let value = parseFactor() else {
                    return nil
                }
                return Self.apply("*", lhs: Decimal(-1), rhs: value)
            }

            if match("(") {
                guard let value = parseExpression(), match(")") else {
                    return nil
                }
                return value
            }

            return parseNumber()
        }

        private mutating func parseNumber() -> Decimal? {
            skipWhitespace()

            let startIndex = index
            var token = ""
            var hasDigit = false

            while index < characters.count {
                let character = characters[index]
                if character.isNumber {
                    hasDigit = true
                    token.append(character)
                    index += 1
                } else if character.isWhitespace || ".,'’".contains(character) {
                    token.append(character)
                    index += 1
                } else {
                    break
                }
            }

            guard hasDigit, let value = AmountInputParsing.parseDecimalCandidate(token) else {
                index = startIndex
                return nil
            }

            return value
        }

        private mutating func skipWhitespace() {
            while index < characters.count, characters[index].isWhitespace {
                index += 1
            }
        }

        private mutating func match(_ character: Character) -> Bool {
            guard index < characters.count, characters[index] == character else {
                return false
            }

            index += 1
            return true
        }

        private static func apply(_ operation: Character, lhs: Decimal, rhs: Decimal) -> Decimal? {
            let left = NSDecimalNumber(decimal: lhs)
            let right = NSDecimalNumber(decimal: rhs)
            let result: NSDecimalNumber

            switch operation {
            case "+":
                result = left.adding(right)
            case "-":
                result = left.subtracting(right)
            case "*":
                result = left.multiplying(by: right)
            case "/":
                guard right.compare(NSDecimalNumber.zero) != .orderedSame else {
                    return nil
                }
                result = left.dividing(by: right)
            default:
                return nil
            }

            guard result.doubleValue.isFinite else {
                return nil
            }

            return result.decimalValue
        }
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

            if let bestCandidate {
                let bestDigitCount = bestCandidate.filter(\.isNumber).count
                let currentDigitCount = trimmedCandidate.filter(\.isNumber).count
                if currentDigitCount < bestDigitCount {
                    return
                }
            }

            bestCandidate = trimmedCandidate
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

    private static func normalizeDecimalSeparators(in text: String) -> String {
        let commaCount = text.filter { $0 == "," }.count
        let dotCount = text.filter { $0 == "." }.count

        if commaCount > 0 && dotCount > 0 {
            let decimalSeparator = lastSeparator(in: text)
            return normalizeMixedSeparators(in: text, decimalSeparator: decimalSeparator)
        }

        if commaCount > 0 {
            return normalizeSingleSeparator(in: text, separator: ",")
        }

        if dotCount > 0 {
            return normalizeSingleSeparator(in: text, separator: ".")
        }

        return text
    }

    private static func normalizeMixedSeparators(in text: String, decimalSeparator: Character) -> String {
        var result = ""
        for character in text {
            if character == decimalSeparator {
                result.append(".")
            } else if character == "," || character == "." {
                continue
            } else {
                result.append(character)
            }
        }
        return result
    }

    private static func normalizeSingleSeparator(in text: String, separator: Character) -> String {
        let parts = text.split(separator: separator, omittingEmptySubsequences: false).map(String.init)

        guard parts.count > 2 else {
            return text.replacingOccurrences(of: String(separator), with: ".")
        }

        let middleGroupsAreThousands = parts.dropFirst().allSatisfy { $0.count == 3 && $0.allSatisfy(\.isNumber) }
        if middleGroupsAreThousands {
            return text.replacingOccurrences(of: String(separator), with: "")
        }

        let prefix = parts.dropLast().joined()
        let suffix = parts.last ?? ""
        return "\(prefix).\(suffix)"
    }

    private static func lastSeparator(in text: String) -> Character {
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
            return "."
        }
    }

    private static func isAmountCharacter(_ character: Character) -> Bool {
        if character.isNumber {
            return true
        }

        return " +-.,'’".contains(character)
    }
}

nonisolated struct CurrencyConversionGraph: Sendable {
    private let edges: [String: [String: Double]]

    init(snapshots: [CurrencySnapshot]) {
        var edges: [String: [String: Double]] = [:]

        for snapshot in snapshots where snapshot.rate > 0 {
            let pair = snapshot.pair
            let unitRate = snapshot.rate / Double(max(pair.baseAmount, 1))
            guard unitRate > 0, unitRate.isFinite else {
                continue
            }

            edges[pair.baseCode, default: [:]][pair.quoteCode] = unitRate
            edges[pair.quoteCode, default: [:]][pair.baseCode] = 1 / unitRate
        }

        self.edges = edges
    }

    func conversionMultipliers(from sourceCode: String) -> [String: Double] {
        var multipliers = [sourceCode: 1.0]
        var queue = [sourceCode]
        var index = 0

        while index < queue.count {
            let current = queue[index]
            index += 1

            guard let currentMultiplier = multipliers[current],
                  let targets = edges[current] else {
                continue
            }

            for (target, edgeRate) in targets where multipliers[target] == nil {
                let multiplier = currentMultiplier * edgeRate
                guard multiplier.isFinite, multiplier > 0 else {
                    continue
                }
                multipliers[target] = multiplier
                queue.append(target)
            }
        }

        return multipliers
    }

    static func orderedCurrencyCodes(from pairs: [CurrencyPair]) -> [String] {
        var seen = Set<String>()
        var codes: [String] = []

        for pair in pairs {
            for code in [pair.baseCode, pair.quoteCode] where seen.insert(code).inserted {
                codes.append(code)
            }
        }

        return codes
    }
}

nonisolated enum RateAlertDirection: String, Codable, CaseIterable, Identifiable, Sendable {
    case above
    case below

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .above:
            String(localized: "高于")
        case .below:
            String(localized: "低于")
        }
    }
}

nonisolated struct RateAlert: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var pairID: String
    var direction: RateAlertDirection
    var threshold: Double
    var isEnabled: Bool
    var lastTriggeredAt: Date?

    init(
        id: UUID = UUID(),
        pairID: String,
        direction: RateAlertDirection,
        threshold: Double,
        isEnabled: Bool = true,
        lastTriggeredAt: Date? = nil
    ) {
        self.id = id
        self.pairID = pairID
        self.direction = direction
        self.threshold = threshold
        self.isEnabled = isEnabled
        self.lastTriggeredAt = lastTriggeredAt
    }

    func isTriggered(by rate: Double) -> Bool {
        switch direction {
        case .above:
            rate >= threshold
        case .below:
            rate <= threshold
        }
    }
}

nonisolated struct SettingsProfile: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var selectedPairIDs: [String]
    var converterCurrenciesFollowSelectedPairs: Bool
    var converterCurrencyCodes: [String]
    var baseCurrencyCode: String
    var autoRefreshMinutes: Int
    var menuBarOpenRefreshEnabled: Bool
    var showsFlags: Bool
    var trendPointLimit: Int
    var rateDisplayBaseAmount: Int
    var conversionFractionDigits: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        selectedPairIDs: [String],
        converterCurrenciesFollowSelectedPairs: Bool = true,
        converterCurrencyCodes: [String] = [],
        baseCurrencyCode: String,
        autoRefreshMinutes: Int,
        menuBarOpenRefreshEnabled: Bool,
        showsFlags: Bool,
        trendPointLimit: Int,
        rateDisplayBaseAmount: Int = 1,
        conversionFractionDigits: Int = 4,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.selectedPairIDs = selectedPairIDs
        self.converterCurrenciesFollowSelectedPairs = converterCurrenciesFollowSelectedPairs
        self.converterCurrencyCodes = PreferencesStore.normalizedCurrencyCodes(converterCurrencyCodes)
        self.baseCurrencyCode = baseCurrencyCode
        self.autoRefreshMinutes = autoRefreshMinutes
        self.menuBarOpenRefreshEnabled = menuBarOpenRefreshEnabled
        self.showsFlags = showsFlags
        self.trendPointLimit = trendPointLimit
        self.rateDisplayBaseAmount = CurrencyDisplayFormatting.normalizedDisplayBaseAmount(rateDisplayBaseAmount)
        self.conversionFractionDigits = CurrencyDisplayFormatting.normalizedFractionDigits(conversionFractionDigits)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case selectedPairIDs
        case converterCurrenciesFollowSelectedPairs
        case converterCurrencyCodes
        case baseCurrencyCode
        case autoRefreshMinutes
        case menuBarOpenRefreshEnabled
        case showsFlags
        case trendPointLimit
        case rateDisplayBaseAmount
        case conversionFractionDigits
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        selectedPairIDs = try container.decode([String].self, forKey: .selectedPairIDs)
        converterCurrenciesFollowSelectedPairs = try container.decodeIfPresent(
            Bool.self,
            forKey: .converterCurrenciesFollowSelectedPairs
        ) ?? true
        converterCurrencyCodes = PreferencesStore.normalizedCurrencyCodes(
            try container.decodeIfPresent([String].self, forKey: .converterCurrencyCodes) ?? []
        )
        baseCurrencyCode = try container.decode(String.self, forKey: .baseCurrencyCode)
        autoRefreshMinutes = try container.decode(Int.self, forKey: .autoRefreshMinutes)
        menuBarOpenRefreshEnabled = try container.decode(Bool.self, forKey: .menuBarOpenRefreshEnabled)
        showsFlags = try container.decode(Bool.self, forKey: .showsFlags)
        trendPointLimit = try container.decode(Int.self, forKey: .trendPointLimit)
        rateDisplayBaseAmount = CurrencyDisplayFormatting.normalizedDisplayBaseAmount(
            try container.decodeIfPresent(Int.self, forKey: .rateDisplayBaseAmount) ?? 1
        )
        conversionFractionDigits = CurrencyDisplayFormatting.normalizedFractionDigits(
            try container.decodeIfPresent(Int.self, forKey: .conversionFractionDigits) ?? 4
        )
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(selectedPairIDs, forKey: .selectedPairIDs)
        try container.encode(converterCurrenciesFollowSelectedPairs, forKey: .converterCurrenciesFollowSelectedPairs)
        try container.encode(converterCurrencyCodes, forKey: .converterCurrencyCodes)
        try container.encode(baseCurrencyCode, forKey: .baseCurrencyCode)
        try container.encode(autoRefreshMinutes, forKey: .autoRefreshMinutes)
        try container.encode(menuBarOpenRefreshEnabled, forKey: .menuBarOpenRefreshEnabled)
        try container.encode(showsFlags, forKey: .showsFlags)
        try container.encode(trendPointLimit, forKey: .trendPointLimit)
        try container.encode(rateDisplayBaseAmount, forKey: .rateDisplayBaseAmount)
        try container.encode(conversionFractionDigits, forKey: .conversionFractionDigits)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

nonisolated struct CustomAPIProvider: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var urlTemplate: String
    var apiKey: String
    var ratePath: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        urlTemplate: String,
        apiKey: String = "",
        ratePath: String = "rate",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.urlTemplate = urlTemplate
        self.apiKey = apiKey
        self.ratePath = ratePath
        self.isEnabled = isEnabled
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var resolvedDisplayName: String {
        trimmedName.isEmpty ? String(localized: "自定义 API") : trimmedName
    }

    var isUsable: Bool {
        !urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !ratePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var localSecretAccount: String {
        "custom-api-provider.\(id.uuidString.lowercased()).api-key"
    }

    var sanitizedForPreferences: CustomAPIProvider {
        var provider = self
        provider.apiKey = ""
        return provider
    }

    func resolvedURL(baseCode: String, quoteCode: String) -> URL? {
        let encodedBase = baseCode.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? baseCode
        let encodedQuote = quoteCode.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? quoteCode
        let encodedKey = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiKey
        let resolvedTemplate = urlTemplate
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "{base}", with: encodedBase)
            .replacingOccurrences(of: "{quote}", with: encodedQuote)
            .replacingOccurrences(of: "{key}", with: encodedKey)
        return URL(string: resolvedTemplate)
    }

    static func rateValue(from data: Data, path: String) throws -> Double? {
        let object = try JSONSerialization.jsonObject(with: data)
        let segments = path
            .split(separator: ".")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !segments.isEmpty else {
            return nil
        }

        let value = segments.reduce(object as Any?) { current, segment in
            guard let current else {
                return nil
            }

            if let dictionary = current as? [String: Any] {
                return dictionary[segment]
            }

            if let array = current as? [Any], let index = Int(segment), array.indices.contains(index) {
                return array[index]
            }

            return nil
        }

        if let number = value as? NSNumber {
            return number.doubleValue
        }

        if let string = value as? String {
            return Double(
                string
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: ",", with: ".")
            )
        }

        return nil
    }
}

nonisolated enum TrendRange: String, Codable, CaseIterable, Identifiable, Sendable {
    case sixHours
    case oneDay
    case oneWeek
    case all

    var title: String {
        switch self {
        case .sixHours:
            String(localized: "近 7 天")
        case .oneDay:
            String(localized: "近 30 天")
        case .oneWeek:
            String(localized: "近 90 天")
        case .all:
            String(localized: "近 180 天")
        }
    }

    var id: String {
        rawValue
    }

    func filter(points: [TrendPoint], now: Date = .now) -> [TrendPoint] {
        let cutoff: Date? = switch self {
        case .sixHours:
            now.addingTimeInterval(-7 * 24 * 3600)
        case .oneDay:
            now.addingTimeInterval(-30 * 24 * 3600)
        case .oneWeek:
            now.addingTimeInterval(-90 * 24 * 3600)
        case .all:
            now.addingTimeInterval(-180 * 24 * 3600)
        }

        guard let cutoff else {
            return points
        }

        let filtered = points.filter { $0.timestamp >= cutoff }
        return filtered.isEmpty ? Array(points.suffix(1)) : filtered
    }
}

nonisolated enum CardTrendRange: String, CaseIterable, Identifiable, Sendable {
    case sevenDays
    case oneMonth
    case threeMonths
    case sixMonths
    case oneYear

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .sevenDays:
            String(localized: "7天")
        case .oneMonth:
            String(localized: "1月")
        case .threeMonths:
            String(localized: "3月")
        case .sixMonths:
            String(localized: "6月")
        case .oneYear:
            String(localized: "1年")
        }
    }

    func filter(points: [TrendPoint], now: Date = .now) -> [TrendPoint] {
        let dayCount: Double = switch self {
        case .sevenDays:
            7
        case .oneMonth:
            30
        case .threeMonths:
            90
        case .sixMonths:
            180
        case .oneYear:
            365
        }

        let cutoff = now.addingTimeInterval(-dayCount * 24 * 3600)
        let filtered = points.filter { $0.timestamp >= cutoff }
        return filtered.isEmpty ? Array(points.suffix(1)) : filtered
    }
}

nonisolated struct TrendPoint: Codable, Hashable, Sendable {
    let timestamp: Date
    let value: Double
}

nonisolated enum TrendPointSampler {
    static func sample(_ points: [TrendPoint], maxPoints: Int) -> [TrendPoint] {
        guard maxPoints > 0, points.count > maxPoints else {
            return points
        }

        guard maxPoints > 1 else {
            return [points.last!]
        }

        let lastIndex = points.count - 1
        let denominator = maxPoints - 1

        return (0..<maxPoints).map { sampleIndex in
            let scaledIndex = Int(round(Double(sampleIndex * lastIndex) / Double(denominator)))
            return points[scaledIndex]
        }
    }
}

nonisolated struct CurrencySnapshot: Identifiable, Codable, Hashable, Sendable {
    let pair: CurrencyPair
    let rate: Double
    let updatedAt: Date
    let effectiveDateText: String?
    let source: ExchangeSource
    let isCached: Bool

    var id: String {
        pair.id
    }

    func withCacheFlag(_ isCached: Bool) -> CurrencySnapshot {
        CurrencySnapshot(
            pair: pair,
            rate: rate,
            updatedAt: updatedAt,
            effectiveDateText: effectiveDateText,
            source: source,
            isCached: isCached
        )
    }
}

nonisolated enum CurrencyCardState: Sendable, Equatable {
    case loading
    case ready
    case stale
    case failed
}

nonisolated struct CurrencyCardModel: Identifiable, Sendable {
    let pair: CurrencyPair
    let snapshot: CurrencySnapshot?
    let historyPoints: [TrendPoint]
    let previousValue: Double?
    let state: CurrencyCardState
    let sampleLimit: Int
    let displayBaseAmount: Int
    let fractionDigits: Int

    var id: String {
        pair.id
    }

    var subtitle: String {
        "\(displayBaseAmount) \(pair.baseCode) → \(pair.quoteCode)"
    }

    var compactPairLabel: String {
        pair.compactLabel
    }

    var valueText: String {
        guard let snapshot else {
            switch state {
            case .loading:
                return String(localized: "加载中")
            case .failed:
                return String(localized: "暂不可用")
            case .ready, .stale:
                return "--"
            }
        }

        return CurrencyDisplayFormatting.rateText(
            snapshotRate: snapshot.rate,
            pairBaseAmount: pair.baseAmount,
            displayBaseAmount: displayBaseAmount,
            fractionDigits: fractionDigits
        )
    }

    var valueColor: Color {
        switch state {
        case .loading:
            return .secondary
        case .failed:
            return Color(red: 0.74, green: 0.20, blue: 0.18)
        case .ready, .stale:
            return Color.primary
        }
    }

    var statusChipText: String? {
        guard snapshot == nil else {
            return nil
        }

        switch state {
        case .loading:
            return String(localized: "等待数据")
        case .failed:
            return String(localized: "需要重试")
        case .ready, .stale:
            return nil
        }
    }

    var statusChipColor: Color {
        switch state {
        case .loading:
            return .secondary
        case .failed:
            return Color(red: 0.74, green: 0.20, blue: 0.18)
        case .ready:
            return Color(red: 0.09, green: 0.53, blue: 0.32)
        case .stale:
            return Color(red: 0.78, green: 0.50, blue: 0.11)
        }
    }

    var detailSegments: [String] {
        guard let snapshot else {
            switch state {
            case .loading:
                return [String(localized: "等待首次拉取")]
            case .failed:
                return [String(localized: "上一轮刷新未拿到该货币对")]
            case .ready, .stale:
                return []
            }
        }

        var segments: [String] = []
        if let effectiveDateText = snapshot.effectiveDateText, !effectiveDateText.isEmpty {
            segments.append(effectiveDateText)
        }
        segments.append(ExchangeFormatter.time.string(from: snapshot.updatedAt))
        if snapshot.isCached {
            segments.append(String(localized: "缓存"))
        }
        return segments
    }

    var isCached: Bool {
        snapshot?.isCached ?? false
    }

    var changeText: String? {
        guard snapshot != nil else {
            return nil
        }

        guard let previousValue, previousValue > 0 else {
            return nil
        }

        let currentRate = displayedRate(snapshot?.rate ?? 0)
        let previousRate = displayedRate(previousValue)
        let delta = currentRate - previousRate
        guard abs(delta) >= 0.000_1 else {
            return String(localized: "持平")
        }

        let prefix = delta > 0 ? "+" : ""
        let formatted = CurrencyDisplayFormatting.localizedNumber(delta, fractionDigits: fractionDigits)
        return "\(prefix)\(formatted)"
    }

    var changeColor: Color {
        guard let previousValue, let snapshot else {
            return .secondary
        }

        if snapshot.rate > previousValue {
            return Color(red: 0.07, green: 0.55, blue: 0.33)
        }

        if snapshot.rate < previousValue {
            return Color(red: 0.74, green: 0.20, blue: 0.18)
        }

        return .secondary
    }

    var sparklineColor: Color {
        if let previousValue, let snapshot, displayedRate(snapshot.rate) < displayedRate(previousValue) {
            return Color(red: 0.70, green: 0.25, blue: 0.22)
        }

        return Color(red: 0.57, green: 0.70, blue: 0.92)
    }

    func chartPoints(for range: CardTrendRange) -> [TrendPoint] {
        let filtered = range.filter(points: historyPoints)
        return TrendPointSampler.sample(filtered, maxPoints: sampleLimit).map {
            TrendPoint(timestamp: $0.timestamp, value: displayedRate($0.value))
        }
    }

    private func displayedRate(_ value: Double?) -> Double {
        guard let value else {
            return 0
        }

        return (value / Double(max(pair.baseAmount, 1))) * Double(displayBaseAmount)
    }
}

nonisolated enum ExchangeFormatter {
    static let decimal: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 4
        return formatter
    }()

    static let compactChange: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 4
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

nonisolated struct CachedExchangeState: Codable, Sendable {
    var snapshots: [CurrencySnapshot]
    var history: [String: [TrendPoint]]
    var lastRefreshAttempt: Date?
    var lastSuccessfulRefreshAt: Date? = nil
    var lastAutomaticRefreshAttempt: Date? = nil
    var lastHistoricalRefresh: Date? = nil
    var refreshLog: [RefreshLogEntry]
}

nonisolated struct EnhancedSourceConfiguration: Codable, Hashable, Sendable {
    let twelveDataAPIKey: String
    let exchangeRateAPIKey: String
    let openExchangeRatesAppID: String
    let fixerAPIKey: String
    let currencyLayerAPIKey: String
    let customProviders: [CustomAPIProvider]

    init(
        twelveDataAPIKey: String = "",
        exchangeRateAPIKey: String = "",
        openExchangeRatesAppID: String = "",
        fixerAPIKey: String = "",
        currencyLayerAPIKey: String = "",
        customProviders: [CustomAPIProvider] = []
    ) {
        self.twelveDataAPIKey = twelveDataAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.exchangeRateAPIKey = exchangeRateAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.openExchangeRatesAppID = openExchangeRatesAppID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.fixerAPIKey = fixerAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.currencyLayerAPIKey = currencyLayerAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.customProviders = customProviders.filter { $0.isEnabled && $0.isUsable }
    }

    var hasTwelveDataKey: Bool {
        !twelveDataAPIKey.isEmpty
    }

    var hasExchangeRateAPIKey: Bool {
        !exchangeRateAPIKey.isEmpty
    }

    var hasOpenExchangeRatesAppID: Bool {
        !openExchangeRatesAppID.isEmpty
    }

    var hasFixerAPIKey: Bool {
        !fixerAPIKey.isEmpty
    }

    var hasCurrencyLayerAPIKey: Bool {
        !currencyLayerAPIKey.isEmpty
    }

    func credential(for kind: EnhancedCredentialKind) -> String {
        switch kind {
        case .twelveData:
            twelveDataAPIKey
        case .exchangeRateAPI:
            exchangeRateAPIKey
        case .openExchangeRates:
            openExchangeRatesAppID
        case .fixer:
            fixerAPIKey
        case .currencyLayer:
            currencyLayerAPIKey
        }
    }

    func withCustomProviders(_ providers: [CustomAPIProvider]) -> EnhancedSourceConfiguration {
        EnhancedSourceConfiguration(
            twelveDataAPIKey: twelveDataAPIKey,
            exchangeRateAPIKey: exchangeRateAPIKey,
            openExchangeRatesAppID: openExchangeRatesAppID,
            fixerAPIKey: fixerAPIKey,
            currencyLayerAPIKey: currencyLayerAPIKey,
            customProviders: providers
        )
    }

    static let empty = EnhancedSourceConfiguration()
}

nonisolated struct DispatchLogEntry: Sendable {
    let level: RefreshLogEntry.Level
    let message: String
}

nonisolated struct ExchangeFetchResult: Sendable {
    var snapshots: [CurrencySnapshot]
    var errors: [String]
    var sourceStatuses: [SourceStatus]
    var logs: [DispatchLogEntry]
}

nonisolated struct ProviderFetchResult: Sendable {
    var snapshots: [CurrencySnapshot]
    var errors: [String]
    var sourceStatus: SourceStatus
    var logs: [DispatchLogEntry]
}

nonisolated struct HistoricalFetchResult: Sendable {
    var historyByPairID: [String: [TrendPoint]]
    var errors: [String]
}

nonisolated enum SourceDateParser {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        return calendar
    }()
    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    static func isoDay(_ string: String) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else {
            return nil
        }

        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: parts[0],
            month: parts[1],
            day: parts[2],
            hour: 12
        ))
    }

    static func cbrDay(_ string: String) -> Date? {
        let parts = string.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else {
            return nil
        }

        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: parts[2],
            month: parts[1],
            day: parts[0],
            hour: 12
        ))
    }

    static func httpDay(_ string: String) -> Date? {
        guard let parsedDate = httpDateFormatter.date(from: string) else {
            return nil
        }

        let components = calendar.dateComponents([.year, .month, .day], from: parsedDate)
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: components.year,
            month: components.month,
            day: components.day,
            hour: 12
        ))
    }

    static func isoQueryString(from date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
    }

    static func cbrQueryString(from date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%02d/%02d/%04d", components.day ?? 1, components.month ?? 1, components.year ?? 1970)
    }
}

nonisolated struct SourceStatus: Codable, Hashable, Sendable, Identifiable {
    let source: ExchangeSource
    let state: State
    let message: String
    let timestamp: Date

    enum State: String, Codable, Sendable {
        case success
        case partial
        case failure
        case idle
    }

    var id: String {
        source.rawValue
    }
}

nonisolated struct RefreshLogEntry: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let timestamp: Date
    let level: Level
    let message: String

    enum Level: String, Codable, Sendable {
        case info
        case warning
        case error
    }

    init(id: UUID = UUID(), timestamp: Date, level: Level, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }
}

@MainActor
@Observable
final class PreferencesStore {
    var selectedPairIDs: [String]
    var converterCurrenciesFollowSelectedPairs: Bool
    var converterCurrencyCodes: [String]
    var autoRefreshMinutes: Int
    var menuBarOpenRefreshEnabled: Bool
    var trendPointLimit: Int
    var featuredPairID: String
    var showsFlags: Bool
    var baseCurrencyCode: String
    var textConversionShortcut: GlobalShortcutDescriptor?
    var automaticUpdateChecksEnabled: Bool
    var skippedUpdateVersion: String?
    var lastAutomaticUpdateCheckAt: Date?
    var menuBarDisplayMode: MenuBarDisplayMode
    var rateDisplayBaseAmount: Int
    var conversionFractionDigits: Int
    var rateAlerts: [RateAlert]
    var settingsProfiles: [SettingsProfile]
    var activeProfileID: UUID?
    var customAPIProviders: [CustomAPIProvider]

    private let userDefaults: UserDefaults
    private let secretStore: any SecretStoring
    private let selectedPairsKey = "selectedPairIDs"
    private let converterCurrenciesFollowSelectedPairsKey = "converterCurrenciesFollowSelectedPairs"
    private let converterCurrencyCodesKey = "converterCurrencyCodes"
    private let autoRefreshKey = "autoRefreshMinutes"
    private let menuBarOpenRefreshKey = "menuBarOpenRefreshEnabled"
    private let trendPointLimitKey = "trendPointLimit"
    private let featuredPairKey = "featuredPairID"
    private let showsFlagsKey = "showsFlags"
    private let baseCurrencyKey = "baseCurrencyCode"
    private let textConversionShortcutKey = "textConversionShortcut"
    private let automaticUpdateChecksKey = "automaticUpdateChecksEnabled"
    private let skippedUpdateVersionKey = "skippedUpdateVersion"
    private let lastAutomaticUpdateCheckAtKey = "lastAutomaticUpdateCheckAt"
    private let menuBarDisplayModeKey = "menuBarDisplayMode"
    private let rateDisplayBaseAmountKey = "rateDisplayBaseAmount"
    private let conversionFractionDigitsKey = "conversionFractionDigits"
    private let rateAlertsKey = "rateAlerts"
    private let settingsProfilesKey = "settingsProfiles"
    private let activeProfileIDKey = "activeProfileID"
    private let customAPIProvidersKey = "customAPIProviders"

    init(userDefaults: UserDefaults = .standard, secretStore: (any SecretStoring)? = nil) {
        self.userDefaults = userDefaults
        let resolvedSecretStore = secretStore ?? LocalSecretStore(service: "com.thomas.currency-tracker")
        self.secretStore = resolvedSecretStore

        let storedPairIDs = userDefaults.stringArray(forKey: selectedPairsKey) ?? []
        let initialSelectedPairIDs = storedPairIDs.filter { Self.pair(for: $0) != nil }
        selectedPairIDs = initialSelectedPairIDs
        if userDefaults.object(forKey: converterCurrenciesFollowSelectedPairsKey) == nil {
            converterCurrenciesFollowSelectedPairs = true
        } else {
            converterCurrenciesFollowSelectedPairs = userDefaults.bool(forKey: converterCurrenciesFollowSelectedPairsKey)
        }
        converterCurrencyCodes = Self.normalizedCurrencyCodes(
            userDefaults.stringArray(forKey: converterCurrencyCodesKey) ?? []
        )

        if let storedRefresh = userDefaults.object(forKey: autoRefreshKey) as? Int,
           [0, 5, 10, 30, 60].contains(storedRefresh) {
            autoRefreshMinutes = storedRefresh
        } else {
            autoRefreshMinutes = 10
        }

        if userDefaults.object(forKey: menuBarOpenRefreshKey) == nil {
            menuBarOpenRefreshEnabled = true
        } else {
            menuBarOpenRefreshEnabled = userDefaults.bool(forKey: menuBarOpenRefreshKey)
        }

        let storedTrendLimit = userDefaults.integer(forKey: trendPointLimitKey)
        trendPointLimit = [12, 20, 30, 50].contains(storedTrendLimit) ? storedTrendLimit : 20

        let storedFeaturedPairID = userDefaults.string(forKey: featuredPairKey)
        featuredPairID = initialSelectedPairIDs.contains(storedFeaturedPairID ?? "") ? (storedFeaturedPairID ?? "") : (initialSelectedPairIDs.first ?? "")

        if userDefaults.object(forKey: showsFlagsKey) == nil {
            showsFlags = false
        } else {
            showsFlags = userDefaults.bool(forKey: showsFlagsKey)
        }

        let storedBaseCurrency = userDefaults.string(forKey: baseCurrencyKey)?.uppercased()
        if let storedBaseCurrency, CurrencyCatalog.info(for: storedBaseCurrency) != nil {
            baseCurrencyCode = storedBaseCurrency
        } else {
            baseCurrencyCode = Self.defaultBaseCurrencyCode()
        }

        textConversionShortcut = Self.decodeShortcut(from: userDefaults.data(forKey: textConversionShortcutKey))

        if userDefaults.object(forKey: automaticUpdateChecksKey) == nil {
            automaticUpdateChecksEnabled = true
        } else {
            automaticUpdateChecksEnabled = userDefaults.bool(forKey: automaticUpdateChecksKey)
        }
        skippedUpdateVersion = userDefaults.string(forKey: skippedUpdateVersionKey)
        lastAutomaticUpdateCheckAt = userDefaults.object(forKey: lastAutomaticUpdateCheckAtKey) as? Date
        menuBarDisplayMode = Self.decodeRawRepresentable(MenuBarDisplayMode.self, from: userDefaults.string(forKey: menuBarDisplayModeKey)) ?? .iconOnly
        let storedDisplayBaseAmount = userDefaults.integer(forKey: rateDisplayBaseAmountKey)
        rateDisplayBaseAmount = CurrencyDisplayFormatting.normalizedDisplayBaseAmount(storedDisplayBaseAmount)
        let storedFractionDigits = userDefaults.integer(forKey: conversionFractionDigitsKey)
        conversionFractionDigits = CurrencyDisplayFormatting.normalizedFractionDigits(storedFractionDigits)
        rateAlerts = Self.decodeArray(RateAlert.self, from: userDefaults.data(forKey: rateAlertsKey))
            .filter { Self.pair(for: $0.pairID) != nil && $0.threshold > 0 }
        settingsProfiles = Self.decodeArray(SettingsProfile.self, from: userDefaults.data(forKey: settingsProfilesKey))
            .filter { !$0.selectedPairIDs.isEmpty || (!$0.converterCurrenciesFollowSelectedPairs && !$0.converterCurrencyCodes.isEmpty) }
        activeProfileID = Self.decodeUUID(from: userDefaults.string(forKey: activeProfileIDKey))
        let customProviderLoad = Self.loadCustomAPIProviders(
            from: userDefaults.data(forKey: customAPIProvidersKey),
            secretStore: resolvedSecretStore
        )
        customAPIProviders = customProviderLoad.providers

        if customProviderLoad.shouldRewritePreferences {
            persist()
        }
    }

    var selectedPairs: [CurrencyPair] {
        selectedPairIDs.compactMap(Self.pair(for:))
    }

    var effectiveConverterCurrencyCodes: [String] {
        converterCurrenciesFollowSelectedPairs
            ? CurrencyConversionGraph.orderedCurrencyCodes(from: selectedPairs)
            : converterCurrencyCodes
    }

    var converterRefreshPairs: [CurrencyPair] {
        Self.converterRefreshPairs(
            for: effectiveConverterCurrencyCodes,
            baseCurrencyCode: baseCurrencyCode
        )
    }

    var refreshPairs: [CurrencyPair] {
        var seen = Set<String>()
        var pairs: [CurrencyPair] = []

        for pair in selectedPairs + (converterCurrenciesFollowSelectedPairs ? [] : converterRefreshPairs)
            where seen.insert(pair.id).inserted {
            pairs.append(pair)
        }

        return pairs
    }

    static func pairForDisplay(id: String) -> CurrencyPair? {
        pair(for: id)
    }

    var availableBaseCurrencies: [CurrencyInfo] {
        CurrencyCatalog.all.filter { $0.code != "RUB" }
    }

    var availableBaseCurrencyOptions: [CurrencyInfo] {
        CurrencyCatalog.all
    }

    var autoRefreshIntervalOptions: [Int] {
        [0, 5, 10, 30, 60]
    }

    var rateDisplayBaseAmountOptions: [Int] {
        CurrencyDisplayFormatting.displayBaseAmountOptions
    }

    var conversionFractionDigitOptions: [Int] {
        CurrencyDisplayFormatting.fractionDigitOptions
    }

    var enabledCustomAPIProviders: [CustomAPIProvider] {
        customAPIProviders.filter { $0.isEnabled && $0.isUsable }
    }

    func availableQuoteCurrencies(for baseCode: String) -> [CurrencyInfo] {
        CurrencyCatalog.supportedQuotes(for: baseCode)
    }

    func contains(_ pair: CurrencyPair) -> Bool {
        selectedPairIDs.contains(pair.id)
    }

    func setConverterCurrenciesFollowSelectedPairs(_ value: Bool) {
        guard converterCurrenciesFollowSelectedPairs != value else {
            return
        }

        if value == false && converterCurrencyCodes.isEmpty {
            converterCurrencyCodes = CurrencyConversionGraph.orderedCurrencyCodes(from: selectedPairs)
        }

        converterCurrenciesFollowSelectedPairs = value
        persist()
    }

    func addConverterCurrency(code: String) {
        let normalized = code.uppercased()
        guard CurrencyCatalog.info(for: normalized) != nil else {
            return
        }

        guard !converterCurrencyCodes.contains(normalized) else {
            return
        }

        converterCurrencyCodes.append(normalized)
        persist()
    }

    func removeConverterCurrency(code: String) {
        converterCurrencyCodes.removeAll { $0 == code.uppercased() }
        persist()
    }

    func moveConverterCurrencyUp(code: String) {
        let normalized = code.uppercased()
        guard let index = converterCurrencyCodes.firstIndex(of: normalized), index > 0 else {
            return
        }

        converterCurrencyCodes.swapAt(index, index - 1)
        persist()
    }

    func moveConverterCurrencyDown(code: String) {
        let normalized = code.uppercased()
        guard let index = converterCurrencyCodes.firstIndex(of: normalized),
              index < converterCurrencyCodes.count - 1 else {
            return
        }

        converterCurrencyCodes.swapAt(index, index + 1)
        persist()
    }

    func addPair(baseCode: String, quoteCode: String) {
        guard let pair = CurrencyCatalog.supportedPair(baseCode: baseCode, quoteCode: quoteCode) else {
            return
        }

        guard !selectedPairIDs.contains(pair.id) else {
            return
        }

        selectedPairIDs.append(pair.id)
        if selectedPairIDs.count == 1 {
            featuredPairID = pair.id
        }
        persist()
    }

    func removePair(id: String) {
        selectedPairIDs.removeAll { $0 == id }
        if featuredPairID == id {
            featuredPairID = selectedPairIDs.first ?? ""
        }
        persist()
    }

    func movePairs(from source: IndexSet, to destination: Int) {
        selectedPairIDs.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    func movePair(id: String, to index: Int) {
        guard let sourceIndex = selectedPairIDs.firstIndex(of: id) else {
            return
        }

        let clampedIndex = max(0, min(index, selectedPairIDs.count))
        guard sourceIndex != clampedIndex && sourceIndex + 1 != clampedIndex else {
            return
        }

        movePairs(from: IndexSet(integer: sourceIndex), to: clampedIndex)
    }

    func movePairUp(id: String) {
        guard let index = selectedPairIDs.firstIndex(of: id), index > 0 else {
            return
        }

        selectedPairIDs.swapAt(index, index - 1)
        persist()
    }

    func movePairDown(id: String) {
        guard let index = selectedPairIDs.firstIndex(of: id), index < selectedPairIDs.count - 1 else {
            return
        }

        selectedPairIDs.swapAt(index, index + 1)
        persist()
    }

    func setFeaturedPair(id: String) {
        guard selectedPairIDs.contains(id) else {
            return
        }

        featuredPairID = id
        persist()
    }

    func setAutoRefreshMinutes(_ value: Int) {
        guard autoRefreshIntervalOptions.contains(value) else {
            return
        }

        autoRefreshMinutes = value
        persist()
    }

    func setMenuBarOpenRefreshEnabled(_ value: Bool) {
        menuBarOpenRefreshEnabled = value
        persist()
    }

    func setTrendPointLimit(_ value: Int) {
        trendPointLimit = value
        persist()
    }

    func setShowsFlags(_ value: Bool) {
        showsFlags = value
        persist()
    }

    func setBaseCurrencyCode(_ value: String) {
        let normalized = value.uppercased()
        guard CurrencyCatalog.info(for: normalized) != nil else {
            return
        }

        baseCurrencyCode = normalized
        persist()
    }

    func setTextConversionShortcut(_ shortcut: GlobalShortcutDescriptor?) {
        textConversionShortcut = shortcut
        persist()
    }

    func setMenuBarDisplayMode(_ value: MenuBarDisplayMode) {
        menuBarDisplayMode = value
        persist()
    }

    func setRateDisplayBaseAmount(_ value: Int) {
        let normalized = CurrencyDisplayFormatting.normalizedDisplayBaseAmount(value)
        guard normalized != rateDisplayBaseAmount else {
            return
        }

        rateDisplayBaseAmount = normalized
        persist()
    }

    func setConversionFractionDigits(_ value: Int) {
        let normalized = CurrencyDisplayFormatting.normalizedFractionDigits(value)
        guard normalized != conversionFractionDigits else {
            return
        }

        conversionFractionDigits = normalized
        persist()
    }

    func setAutomaticUpdateChecksEnabled(_ value: Bool) {
        automaticUpdateChecksEnabled = value
        persist()
    }

    func skipUpdate(version: String) {
        skippedUpdateVersion = version
        persist()
    }

    func setLastAutomaticUpdateCheckAt(_ date: Date?) {
        lastAutomaticUpdateCheckAt = date
        persist()
    }

    func addRateAlert(pairID: String, direction: RateAlertDirection, threshold: Double) {
        guard Self.pair(for: pairID) != nil, threshold > 0 else {
            return
        }

        rateAlerts.append(RateAlert(pairID: pairID, direction: direction, threshold: threshold))
        persist()
    }

    func updateRateAlert(_ alert: RateAlert) {
        guard let index = rateAlerts.firstIndex(where: { $0.id == alert.id }) else {
            return
        }

        rateAlerts[index] = alert
        persist()
    }

    func setRateAlertTriggered(id: UUID, at date: Date) {
        guard let index = rateAlerts.firstIndex(where: { $0.id == id }) else {
            return
        }

        rateAlerts[index].lastTriggeredAt = date
        persist()
    }

    func removeRateAlert(id: UUID) {
        rateAlerts.removeAll { $0.id == id }
        persist()
    }

    func saveCurrentProfile(named name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty
            ? String(format: String(localized: "配置 %d"), settingsProfiles.count + 1)
            : trimmedName
        let profile = SettingsProfile(
            name: resolvedName,
            selectedPairIDs: selectedPairIDs,
            converterCurrenciesFollowSelectedPairs: converterCurrenciesFollowSelectedPairs,
            converterCurrencyCodes: converterCurrencyCodes,
            baseCurrencyCode: baseCurrencyCode,
            autoRefreshMinutes: autoRefreshMinutes,
            menuBarOpenRefreshEnabled: menuBarOpenRefreshEnabled,
            showsFlags: showsFlags,
            trendPointLimit: trendPointLimit,
            rateDisplayBaseAmount: rateDisplayBaseAmount,
            conversionFractionDigits: conversionFractionDigits
        )
        settingsProfiles.append(profile)
        activeProfileID = profile.id
        persist()
    }

    func applyProfile(id: UUID) {
        guard let profile = settingsProfiles.first(where: { $0.id == id }) else {
            return
        }

        selectedPairIDs = profile.selectedPairIDs.filter { Self.pair(for: $0) != nil }
        converterCurrenciesFollowSelectedPairs = profile.converterCurrenciesFollowSelectedPairs
        converterCurrencyCodes = Self.normalizedCurrencyCodes(profile.converterCurrencyCodes)
        baseCurrencyCode = CurrencyCatalog.info(for: profile.baseCurrencyCode) == nil ? baseCurrencyCode : profile.baseCurrencyCode
        autoRefreshMinutes = autoRefreshIntervalOptions.contains(profile.autoRefreshMinutes) ? profile.autoRefreshMinutes : autoRefreshMinutes
        menuBarOpenRefreshEnabled = profile.menuBarOpenRefreshEnabled
        showsFlags = profile.showsFlags
        trendPointLimit = [12, 20, 30, 50].contains(profile.trendPointLimit) ? profile.trendPointLimit : trendPointLimit
        rateDisplayBaseAmount = CurrencyDisplayFormatting.normalizedDisplayBaseAmount(profile.rateDisplayBaseAmount)
        conversionFractionDigits = CurrencyDisplayFormatting.normalizedFractionDigits(profile.conversionFractionDigits)
        featuredPairID = selectedPairIDs.contains(featuredPairID) ? featuredPairID : (selectedPairIDs.first ?? "")
        activeProfileID = id
        persist()
    }

    func updateProfileName(id: UUID, name: String) {
        guard let index = settingsProfiles.firstIndex(where: { $0.id == id }) else {
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }

        settingsProfiles[index].name = trimmedName
        settingsProfiles[index].updatedAt = .now
        persist()
    }

    func deleteProfile(id: UUID) {
        settingsProfiles.removeAll { $0.id == id }
        if activeProfileID == id {
            activeProfileID = nil
        }
        persist()
    }

    func addCustomAPIProvider() {
        customAPIProviders.append(
            CustomAPIProvider(
                name: String(format: String(localized: "自定义 API %d"), customAPIProviders.count + 1),
                urlTemplate: "",
                ratePath: "rate",
                isEnabled: false
            )
        )
        persist()
    }

    func updateCustomAPIProvider(_ provider: CustomAPIProvider) {
        guard let index = customAPIProviders.firstIndex(where: { $0.id == provider.id }) else {
            return
        }

        customAPIProviders[index] = provider
        persist()
    }

    func removeCustomAPIProvider(id: UUID) {
        if let provider = customAPIProviders.first(where: { $0.id == id }) {
            try? secretStore.delete(account: provider.localSecretAccount)
        }
        customAPIProviders.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        userDefaults.set(selectedPairIDs, forKey: selectedPairsKey)
        userDefaults.set(converterCurrenciesFollowSelectedPairs, forKey: converterCurrenciesFollowSelectedPairsKey)
        userDefaults.set(converterCurrencyCodes, forKey: converterCurrencyCodesKey)
        userDefaults.set(autoRefreshMinutes, forKey: autoRefreshKey)
        userDefaults.set(menuBarOpenRefreshEnabled, forKey: menuBarOpenRefreshKey)
        userDefaults.set(trendPointLimit, forKey: trendPointLimitKey)
        userDefaults.set(featuredPairID, forKey: featuredPairKey)
        userDefaults.set(showsFlags, forKey: showsFlagsKey)
        userDefaults.set(baseCurrencyCode, forKey: baseCurrencyKey)
        userDefaults.set(Self.encodeShortcut(textConversionShortcut), forKey: textConversionShortcutKey)
        userDefaults.set(automaticUpdateChecksEnabled, forKey: automaticUpdateChecksKey)
        userDefaults.set(menuBarDisplayMode.rawValue, forKey: menuBarDisplayModeKey)
        userDefaults.set(rateDisplayBaseAmount, forKey: rateDisplayBaseAmountKey)
        userDefaults.set(conversionFractionDigits, forKey: conversionFractionDigitsKey)
        userDefaults.set(Self.encodeArray(rateAlerts), forKey: rateAlertsKey)
        userDefaults.set(Self.encodeArray(settingsProfiles), forKey: settingsProfilesKey)
        userDefaults.set(Self.encodeArray(customAPIProvidersForPreferences()), forKey: customAPIProvidersKey)

        if let activeProfileID {
            userDefaults.set(activeProfileID.uuidString, forKey: activeProfileIDKey)
        } else {
            userDefaults.removeObject(forKey: activeProfileIDKey)
        }

        if let skippedUpdateVersion {
            userDefaults.set(skippedUpdateVersion, forKey: skippedUpdateVersionKey)
        } else {
            userDefaults.removeObject(forKey: skippedUpdateVersionKey)
        }

        if let lastAutomaticUpdateCheckAt {
            userDefaults.set(lastAutomaticUpdateCheckAt, forKey: lastAutomaticUpdateCheckAtKey)
        } else {
            userDefaults.removeObject(forKey: lastAutomaticUpdateCheckAtKey)
        }
    }

    nonisolated static func normalizedCurrencyCodes(_ codes: [String]) -> [String] {
        var seen = Set<String>()
        var normalizedCodes: [String] = []

        for code in codes.map({ $0.uppercased() }) {
            guard CurrencyCatalog.info(for: code) != nil,
                  seen.insert(code).inserted else {
                continue
            }

            normalizedCodes.append(code)
        }

        return normalizedCodes
    }

    nonisolated static func converterRefreshPairs(
        for currencyCodes: [String],
        baseCurrencyCode: String
    ) -> [CurrencyPair] {
        let codes = normalizedCurrencyCodes(currencyCodes)
        guard codes.count > 1 else {
            return []
        }

        let normalizedBaseCurrencyCode = baseCurrencyCode.uppercased()
        let anchorCode: String
        if normalizedBaseCurrencyCode != "RUB",
           CurrencyCatalog.info(for: normalizedBaseCurrencyCode) != nil {
            anchorCode = normalizedBaseCurrencyCode
        } else if let firstNonRUBCode = codes.first(where: { $0 != "RUB" }) {
            anchorCode = firstNonRUBCode
        } else {
            return []
        }

        var seen = Set<String>()
        var pairs: [CurrencyPair] = []

        for code in codes where code != anchorCode {
            let pair: CurrencyPair?
            if code == "RUB" {
                pair = CurrencyCatalog.supportedPair(baseCode: anchorCode, quoteCode: code)
            } else {
                pair = CurrencyCatalog.supportedPair(baseCode: code, quoteCode: anchorCode)
            }

            if let pair, seen.insert(pair.id).inserted {
                pairs.append(pair)
            }
        }

        return pairs
    }

    private static func pair(for id: String) -> CurrencyPair? {
        let components = id.split(separator: "-")
        guard components.count == 3 else {
            return nil
        }

        guard let baseAmount = Int(components[2]) else {
            return nil
        }

        return CurrencyCatalog.supportedPair(
            baseCode: String(components[0]),
            quoteCode: String(components[1]),
            baseAmount: baseAmount
        )
    }

    private static func defaultBaseCurrencyCode() -> String {
        if let localeCurrency = Locale.autoupdatingCurrent.currency?.identifier.uppercased(),
           CurrencyCatalog.info(for: localeCurrency) != nil {
            return localeCurrency
        }

        return "USD"
    }

    private static func loadCustomAPIProviders(
        from data: Data?,
        secretStore: any SecretStoring
    ) -> (providers: [CustomAPIProvider], shouldRewritePreferences: Bool) {
        let decodedProviders = Self.decodeArray(CustomAPIProvider.self, from: data)
        var shouldRewritePreferences = false

        let providers = decodedProviders.map { provider in
            var hydratedProvider = provider
            let legacyAPIKey = provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

            if !legacyAPIKey.isEmpty {
                if (try? secretStore.write(legacyAPIKey, account: provider.localSecretAccount)) != nil {
                    shouldRewritePreferences = true
                }
            }

            if let storedAPIKey = try? secretStore.read(account: provider.localSecretAccount)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !storedAPIKey.isEmpty {
                hydratedProvider.apiKey = storedAPIKey
            } else {
                hydratedProvider.apiKey = legacyAPIKey
            }

            return hydratedProvider
        }

        return (providers, shouldRewritePreferences)
    }

    private func customAPIProvidersForPreferences() -> [CustomAPIProvider] {
        customAPIProviders = customAPIProviders.map { provider in
            var normalizedProvider = provider
            normalizedProvider.apiKey = provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

            if normalizedProvider.apiKey.isEmpty {
                try? secretStore.delete(account: normalizedProvider.localSecretAccount)
            } else {
                try? secretStore.write(normalizedProvider.apiKey, account: normalizedProvider.localSecretAccount)
            }

            return normalizedProvider
        }

        return customAPIProviders.map(\.sanitizedForPreferences)
    }

    private static func encodeShortcut(_ shortcut: GlobalShortcutDescriptor?) -> Data? {
        guard let shortcut else {
            return nil
        }

        return try? JSONEncoder().encode(shortcut)
    }

    private static func decodeShortcut(from data: Data?) -> GlobalShortcutDescriptor? {
        guard let data else {
            return nil
        }

        return try? JSONDecoder().decode(GlobalShortcutDescriptor.self, from: data)
    }

    private static func encodeArray<T: Encodable>(_ values: [T]) -> Data? {
        try? JSONEncoder().encode(values)
    }

    private static func decodeArray<T: Decodable>(_ type: T.Type, from data: Data?) -> [T] {
        guard let data else {
            return []
        }

        return (try? JSONDecoder().decode([T].self, from: data)) ?? []
    }

    private static func decodeRawRepresentable<T: RawRepresentable>(_ type: T.Type, from value: T.RawValue?) -> T? {
        guard let value else {
            return nil
        }

        return T(rawValue: value)
    }

    private static func decodeUUID(from value: String?) -> UUID? {
        guard let value else {
            return nil
        }

        return UUID(uuidString: value)
    }
}

@MainActor
@Observable
final class LaunchAtLoginController {
    var isEnabled = false
    var requiresApproval = false
    var lastErrorMessage: String?

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval

        if status == .notFound {
            lastErrorMessage = "系统暂时无法确认开机启动状态。"
        } else {
            lastErrorMessage = nil
        }
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }

            refreshStatus()
        } catch {
            refreshStatus()
            lastErrorMessage = enabled ? "开机启动注册失败" : "开机启动关闭失败"
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

actor ExchangeRateStore {
    private let cacheURL: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directoryURL = baseURL.appendingPathComponent("CurrencyTracker", isDirectory: true)

        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        cacheURL = directoryURL.appendingPathComponent("exchange-cache.json")
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() async -> CachedExchangeState? {
        guard let data = try? Data(contentsOf: cacheURL) else {
            return nil
        }

        if let state = try? decoder.decode(CachedExchangeState.self, from: data) {
            return state
        }

        guard let legacyState = try? decoder.decode(LegacyCachedExchangeState.self, from: data) else {
            return nil
        }

        return CachedExchangeState(
            snapshots: legacyState.snapshots,
            history: legacyState.history,
            lastRefreshAttempt: legacyState.lastRefreshAttempt,
            refreshLog: []
        )
    }

    func save(_ state: CachedExchangeState) async {
        guard let data = try? encoder.encode(state) else {
            return
        }

        try? data.write(to: cacheURL, options: [.atomic])
    }
}


extension CachedExchangeState {
    static let empty = CachedExchangeState(snapshots: [], history: [:], lastRefreshAttempt: nil, refreshLog: [])

    mutating func mergeSnapshots(_ snapshots: [CurrencySnapshot]) {
        guard !snapshots.isEmpty else {
            return
        }

        var snapshotsByID = Dictionary(uniqueKeysWithValues: self.snapshots.map { ($0.id, $0) })
        for snapshot in snapshots {
            snapshotsByID[snapshot.id] = snapshot
        }
        self.snapshots = Array(snapshotsByID.values)
    }

    mutating func prependLogs(_ entries: [RefreshLogEntry]) {
        guard !entries.isEmpty else {
            return
        }

        refreshLog = entries.reversed() + refreshLog
        refreshLog = Array(refreshLog.prefix(30))
    }

    static let sample = CachedExchangeState(
        snapshots: [
            CurrencySnapshot(pair: CurrencyPair.defaults[0], rate: 92.37, updatedAt: .now, effectiveDateText: "2026-04-10", source: .cbr, isCached: false),
            CurrencySnapshot(pair: CurrencyPair.defaults[1], rate: 12.74, updatedAt: .now, effectiveDateText: "2026-04-10", source: .cbr, isCached: false),
            CurrencySnapshot(pair: CurrencyPair.defaults[2], rate: 100.21, updatedAt: .now, effectiveDateText: "2026-04-10", source: .cbr, isCached: false),
            CurrencySnapshot(pair: CurrencyPair.defaults[3], rate: 7.24, updatedAt: .now, effectiveDateText: "2026-04-10", source: .ecb, isCached: false),
            CurrencySnapshot(pair: CurrencyPair.defaults[4], rate: 7.89, updatedAt: .now, effectiveDateText: "2026-04-10", source: .ecb, isCached: false)
        ],
        history: [
            CurrencyPair.defaults[0].id: [
                TrendPoint(timestamp: .now.addingTimeInterval(-5 * 24 * 3600), value: 91.82),
                TrendPoint(timestamp: .now.addingTimeInterval(-4 * 24 * 3600), value: 92.05),
                TrendPoint(timestamp: .now.addingTimeInterval(-2 * 24 * 3600), value: 92.11),
                TrendPoint(timestamp: .now.addingTimeInterval(-24 * 3600), value: 92.37)
            ]
        ],
        lastRefreshAttempt: .now,
        refreshLog: [
            RefreshLogEntry(timestamp: .now.addingTimeInterval(-120), level: .info, message: "预览数据已载入"),
            RefreshLogEntry(timestamp: .now.addingTimeInterval(-60), level: .warning, message: "ECB 预览来源仅用于界面展示")
        ]
    )
}
