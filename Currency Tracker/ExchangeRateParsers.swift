//
//  ExchangeRateParsers.swift
//  Currency Tracker
//
//  Created by Codex on 4/12/26.
//

import Foundation

nonisolated struct FrankfurterRateEntry: Decodable, Sendable {
    let date: String
    let base: String
    let quote: String
    let rate: Double
}

nonisolated struct FloatRatesEntry: Decodable, Sendable {
    let rate: Double
    let date: String
}

nonisolated struct CurrencyAPIRates: Sendable {
    let date: String
    let rates: [String: Double]
}

nonisolated struct TwelveDataExchangeRate: Sendable {
    let rate: Double
    let timestamp: Date?
}

nonisolated enum TwelveDataParser {
    static func parseExchangeRate(from data: Data) throws -> TwelveDataExchangeRate {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let object else {
            throw EnhancedProviderError.noData
        }

        if let status = object["status"] as? String, status.lowercased() == "error" {
            let message = object["message"] as? String ?? "未知错误"
            throw EnhancedProviderError.transport(message)
        }

        let rawRate = object["rate"] as? String ?? (object["rate"] as? NSNumber)?.stringValue
        guard let rawRate, let rate = Double(rawRate) else {
            throw EnhancedProviderError.noData
        }

        let rawTimestamp = object["timestamp"] as? TimeInterval
            ?? (object["timestamp"] as? NSNumber)?.doubleValue
        let timestamp = rawTimestamp.map { Date(timeIntervalSince1970: $0) }

        return TwelveDataExchangeRate(rate: rate, timestamp: timestamp)
    }
}

nonisolated enum CurrencyAPIParser {
    static func parseRates(from data: Data, expectedBaseCode: String? = nil) throws -> CurrencyAPIRates {
        let payload = try JSONDecoder().decode(CurrencyAPIPayload.self, from: data)
        let candidateRatesByBaseCode = payload.ratesByBaseCode

        if let expectedBaseCode {
            guard let rates = candidateRatesByBaseCode[expectedBaseCode.lowercased()] else {
                throw URLError(.cannotParseResponse)
            }

            return CurrencyAPIRates(date: payload.date, rates: rates)
        }

        guard candidateRatesByBaseCode.count == 1,
              let rates = candidateRatesByBaseCode.values.first else {
            throw URLError(.cannotParseResponse)
        }

        return CurrencyAPIRates(date: payload.date, rates: rates)
    }
}

nonisolated private struct CurrencyAPIPayload: Decodable {
    let date: String
    let ratesByBaseCode: [String: [String: Double]]

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKeys.self)
        date = try container.decodeIfPresent(String.self, forKey: DynamicCodingKeys("date")) ?? ""

        var parsedRatesByBaseCode: [String: [String: Double]] = [:]

        for key in container.allKeys where key.stringValue.range(of: #"^[a-z]{3}$"#, options: .regularExpression) != nil {
            let rawRates = try container.decode([String: Double].self, forKey: key)
            let normalizedRates = rawRates.reduce(into: [String: Double]()) { partialResult, entry in
                partialResult[entry.key.lowercased()] = entry.value
            }

            if !normalizedRates.isEmpty {
                parsedRatesByBaseCode[key.stringValue.lowercased()] = normalizedRates
            }
        }

        ratesByBaseCode = parsedRatesByBaseCode
    }
}

nonisolated private struct DynamicCodingKeys: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

nonisolated struct OpenExchangeRatesLatest: Sendable {
    let timestamp: Date
    let rates: [String: Double]

    func rate(for currencyCode: String) -> Double? {
        if currencyCode == "USD" {
            return 1
        }

        return rates[currencyCode]
    }
}

nonisolated enum OpenExchangeRatesParser {
    static func parseLatest(from data: Data) throws -> OpenExchangeRatesLatest {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let object else {
            throw EnhancedProviderError.noData
        }

        if let error = object["error"] as? Bool, error {
            let message = object["message"] as? String ?? "未知错误"
            throw EnhancedProviderError.transport(message)
        }

        guard let timestamp = object["timestamp"] as? TimeInterval ?? (object["timestamp"] as? NSNumber)?.doubleValue,
              let rawRates = object["rates"] as? [String: Any] else {
            throw EnhancedProviderError.noData
        }

        let rates = rawRates.reduce(into: [String: Double]()) { partialResult, entry in
            if let value = entry.value as? Double {
                partialResult[entry.key] = value
            } else if let number = entry.value as? NSNumber {
                partialResult[entry.key] = number.doubleValue
            }
        }

        return OpenExchangeRatesLatest(timestamp: Date(timeIntervalSince1970: timestamp), rates: rates)
    }
}

nonisolated struct ExchangeRateAPILatest: Sendable {
    let timestamp: Date?
    let baseCode: String
    let rates: [String: Double]

    func rate(for currencyCode: String) -> Double? {
        if currencyCode == baseCode {
            return 1
        }

        return rates[currencyCode]
    }
}

nonisolated enum ExchangeRateAPIParser {
    static func parseLatest(from data: Data) throws -> ExchangeRateAPILatest {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let object else {
            throw EnhancedProviderError.noData
        }

        if let result = object["result"] as? String, result.lowercased() != "success" {
            let message = object["error-type"] as? String ?? result
            throw EnhancedProviderError.transport(message)
        }

        guard let baseCode = object["base_code"] as? String,
              let rawRates = object["conversion_rates"] as? [String: Any] else {
            throw EnhancedProviderError.noData
        }

        let rates = parseNumberMap(rawRates)
        let timestampValue = object["time_last_update_unix"] as? TimeInterval
            ?? (object["time_last_update_unix"] as? NSNumber)?.doubleValue

        return ExchangeRateAPILatest(
            timestamp: timestampValue.map { Date(timeIntervalSince1970: $0) },
            baseCode: baseCode.uppercased(),
            rates: rates
        )
    }
}

nonisolated struct FixerLatest: Sendable {
    let timestamp: Date?
    let date: String?
    let baseCode: String
    let rates: [String: Double]

    func rate(for currencyCode: String) -> Double? {
        if currencyCode == baseCode {
            return 1
        }

        return rates[currencyCode]
    }
}

nonisolated enum FixerParser {
    static func parseLatest(from data: Data) throws -> FixerLatest {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let object else {
            throw EnhancedProviderError.noData
        }

        if let success = object["success"] as? Bool, success == false {
            let errorObject = object["error"] as? [String: Any]
            let message = errorObject?["info"] as? String
                ?? errorObject?["type"] as? String
                ?? "Fixer error"
            throw EnhancedProviderError.transport(message)
        }

        guard let rawRates = object["rates"] as? [String: Any] else {
            throw EnhancedProviderError.noData
        }

        let timestampValue = object["timestamp"] as? TimeInterval
            ?? (object["timestamp"] as? NSNumber)?.doubleValue
        let baseCode = (object["base"] as? String ?? "EUR").uppercased()

        return FixerLatest(
            timestamp: timestampValue.map { Date(timeIntervalSince1970: $0) },
            date: object["date"] as? String,
            baseCode: baseCode,
            rates: parseNumberMap(rawRates)
        )
    }
}

nonisolated struct CurrencyLayerLive: Sendable {
    let timestamp: Date?
    let sourceCode: String
    let quotes: [String: Double]

    func rate(for currencyCode: String) -> Double? {
        if currencyCode == sourceCode {
            return 1
        }

        return quotes["\(sourceCode)\(currencyCode)"]
    }
}

nonisolated enum CurrencyLayerParser {
    static func parseLive(from data: Data) throws -> CurrencyLayerLive {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let object else {
            throw EnhancedProviderError.noData
        }

        if let success = object["success"] as? Bool, success == false {
            let errorObject = object["error"] as? [String: Any]
            let message = errorObject?["info"] as? String
                ?? errorObject?["type"] as? String
                ?? "Currencylayer error"
            throw EnhancedProviderError.transport(message)
        }

        guard let rawQuotes = object["quotes"] as? [String: Any] else {
            throw EnhancedProviderError.noData
        }

        let timestampValue = object["timestamp"] as? TimeInterval
            ?? (object["timestamp"] as? NSNumber)?.doubleValue
        let sourceCode = (object["source"] as? String ?? "USD").uppercased()

        return CurrencyLayerLive(
            timestamp: timestampValue.map { Date(timeIntervalSince1970: $0) },
            sourceCode: sourceCode,
            quotes: parseNumberMap(rawQuotes)
        )
    }
}

nonisolated private func parseNumberMap(_ rawValues: [String: Any]) -> [String: Double] {
    rawValues.reduce(into: [String: Double]()) { partialResult, entry in
        if let value = entry.value as? Double {
            partialResult[entry.key.uppercased()] = value
        } else if let number = entry.value as? NSNumber {
            partialResult[entry.key.uppercased()] = number.doubleValue
        }
    }
}

nonisolated struct ECBDataResponse: Decodable, Sendable {
    let dataSets: [ECBDataSet]
    let structure: ECBStructure
}

nonisolated struct ECBDataSet: Decodable, Sendable {
    let series: [String: ECBSeries]
}

nonisolated struct ECBSeries: Decodable, Sendable {
    let observations: [String: [Double?]]
}

nonisolated struct ECBStructure: Decodable, Sendable {
    let dimensions: ECBDimensions
}

nonisolated struct ECBDimensions: Decodable, Sendable {
    let series: [ECBDimension]
    let observation: [ECBDimension]
}

nonisolated struct ECBDimension: Decodable, Sendable {
    let id: String
    let values: [ECBDimensionValue]
}

nonisolated struct ECBDimensionValue: Decodable, Sendable {
    let id: String
}

nonisolated enum ECBEXRParser {
    static func parseSeriesByCurrency(from data: Data) throws -> [String: [TrendPoint]] {
        let response = try JSONDecoder().decode(ECBDataResponse.self, from: data)
        guard let dataSet = response.dataSets.first,
              response.structure.dimensions.series.count > 1,
              let timeDimension = response.structure.dimensions.observation.first else {
            return [:]
        }

        let currencyCodes = response.structure.dimensions.series[1].values.map(\.id)
        let dayKeys = timeDimension.values.map(\.id)
        var seriesByCurrency: [String: [TrendPoint]] = [:]

        for (seriesKey, series) in dataSet.series {
            let indices = seriesKey.split(separator: ":").compactMap { Int($0) }
            guard indices.count > 1, currencyCodes.indices.contains(indices[1]) else {
                continue
            }

            let currencyCode = currencyCodes[indices[1]]
            let points = series.observations.compactMap { observationKey, values -> TrendPoint? in
                guard let observationIndex = Int(observationKey),
                      dayKeys.indices.contains(observationIndex),
                      let rawValue = values.first ?? nil,
                      let timestamp = SourceDateParser.isoDay(dayKeys[observationIndex]) else {
                    return nil
                }

                return TrendPoint(timestamp: timestamp, value: rawValue)
            }.sorted { lhs, rhs in
                lhs.timestamp < rhs.timestamp
            }

            seriesByCurrency[currencyCode] = points
        }

        return seriesByCurrency
    }
}

nonisolated struct HTTPStatusError: Error, Sendable {
    let statusCode: Int
    let body: String?
}

nonisolated enum EnhancedProviderError: Error, Sendable {
    case unsupportedPair
    case rateLimited
    case authenticationFailed
    case noData
    case transport(String)
}

nonisolated struct LegacyCachedExchangeState: Codable, Sendable {
    var snapshots: [CurrencySnapshot]
    var history: [String: [TrendPoint]]
    var lastRefreshAttempt: Date?
}

nonisolated struct CBRDailyDocument: Sendable {
    let effectiveDate: String?
    let ratesByCode: [String: Double]
}

nonisolated final class CBRCurrencyReferenceParser: NSObject, XMLParserDelegate {
    private var currencyIDsByCode: [String: String] = [:]
    private var currentElement = ""
    private var currentItemID = ""
    private var currentISOCode = ""

    static func parseCurrencyIDs(from data: Data) throws -> [String: String] {
        let parserDelegate = CBRCurrencyReferenceParser()
        let parser = XMLParser(data: data)
        parser.delegate = parserDelegate

        guard parser.parse() else {
            throw parser.parserError ?? URLError(.cannotParseResponse)
        }

        return parserDelegate.currencyIDsByCode
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName

        if elementName == "Item" {
            currentItemID = attributeDict["ID"] ?? ""
            currentISOCode = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentElement == "ISO_Char_Code" {
            currentISOCode += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "Item" {
            let normalizedCode = currentISOCode.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedID = currentItemID.trimmingCharacters(in: .whitespacesAndNewlines)

            if !normalizedCode.isEmpty, !normalizedID.isEmpty, currencyIDsByCode[normalizedCode] == nil {
                currencyIDsByCode[normalizedCode] = normalizedID
            }
        }

        currentElement = ""
    }
}

nonisolated final class CBRDynamicParser: NSObject, XMLParserDelegate {
    private var points: [TrendPoint] = []
    private var currentElement = ""
    private var currentDateText = ""
    private var currentNominal = ""
    private var currentValue = ""

    static func parsePoints(from data: Data) throws -> [TrendPoint] {
        let parserDelegate = CBRDynamicParser()
        let parser = XMLParser(data: data)
        parser.delegate = parserDelegate

        guard parser.parse() else {
            throw parser.parserError ?? URLError(.cannotParseResponse)
        }

        return parserDelegate.points.sorted { $0.timestamp < $1.timestamp }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName

        if elementName == "Record" {
            currentDateText = attributeDict["Date"] ?? ""
            currentNominal = ""
            currentValue = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        switch currentElement {
        case "Nominal":
            currentNominal += string
        case "Value":
            currentValue += string
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "Record" {
            let nominalText = currentNominal.trimmingCharacters(in: .whitespacesAndNewlines)
            let valueText = currentValue.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")

            if let date = SourceDateParser.cbrDay(currentDateText),
               let nominal = Double(nominalText),
               let value = Double(valueText),
               nominal > 0 {
                points.append(TrendPoint(timestamp: date, value: value / nominal))
            }
        }

        currentElement = ""
    }
}

nonisolated final class CBRDailyParser: NSObject, XMLParserDelegate {
    private var ratesByCode: [String: Double] = [:]
    private var currentElement = ""
    private var currentCode = ""
    private var currentNominal = ""
    private var currentValue = ""
    private var effectiveDate: String?

    static func parseRates(from data: Data) throws -> [String: Double] {
        try parseDocument(from: data).ratesByCode
    }

    static func parseDocument(from data: Data) throws -> CBRDailyDocument {
        let parserDelegate = CBRDailyParser()
        let parser = XMLParser(data: data)
        parser.delegate = parserDelegate

        guard parser.parse() else {
            throw parser.parserError ?? URLError(.cannotParseResponse)
        }

        return CBRDailyDocument(
            effectiveDate: parserDelegate.effectiveDate,
            ratesByCode: parserDelegate.ratesByCode
        )
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName

        if elementName == "ValCurs" {
            effectiveDate = attributeDict["Date"]
        }

        if elementName == "Valute" {
            currentCode = ""
            currentNominal = ""
            currentValue = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        switch currentElement {
        case "CharCode":
            currentCode += string
        case "Nominal":
            currentNominal += string
        case "Value":
            currentValue += string
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "Valute" {
            let normalizedCode = currentCode.trimmingCharacters(in: .whitespacesAndNewlines)
            let nominalText = currentNominal.trimmingCharacters(in: .whitespacesAndNewlines)
            let valueText = currentValue.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")

            if let nominal = Double(nominalText), let value = Double(valueText), nominal > 0 {
                ratesByCode[normalizedCode] = value / nominal
            }
        }

        currentElement = ""
    }
}
