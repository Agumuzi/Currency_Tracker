//
//  ConversionPresentation.swift
//  Currency Tracker
//
//  Created by Codex on 4/13/26.
//

import Foundation

nonisolated struct ConversionPresentation: Equatable, Sendable {
    let sourceAmount: Decimal
    let sourceCurrencyCode: String
    let targetAmount: Decimal
    let targetCurrencyCode: String

    var expressionText: String {
        "\(ServiceConversionFormatting.sourceAmount(sourceAmount)) \(sourceCurrencyCode) ≈ \(ServiceConversionFormatting.resultAmount(targetAmount)) \(targetCurrencyCode)"
    }

    var clipboardText: String {
        "\(ServiceConversionFormatting.resultAmount(targetAmount)) \(targetCurrencyCode)"
    }
}

nonisolated enum ServiceConversionFormatting {
    static func sourceAmount(_ value: Decimal) -> String {
        sourceFormatter.string(from: value as NSDecimalNumber) ?? NSDecimalNumber(decimal: value).stringValue
    }

    static func resultAmount(_ value: Decimal) -> String {
        resultFormatter.string(from: value as NSDecimalNumber) ?? NSDecimalNumber(decimal: value).stringValue
    }

    private static let sourceFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 4
        return formatter
    }()

    private static let resultFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 4
        return formatter
    }()
}
