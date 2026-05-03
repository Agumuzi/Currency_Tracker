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
    let fractionDigits: Int

    var expressionText: String {
        "\(ServiceConversionFormatting.sourceAmount(sourceAmount)) \(sourceCurrencyCode) ≈ \(ServiceConversionFormatting.resultAmount(targetAmount, fractionDigits: fractionDigits)) \(targetCurrencyCode)"
    }

    var clipboardText: String {
        "\(ServiceConversionFormatting.resultAmount(targetAmount, fractionDigits: fractionDigits)) \(targetCurrencyCode)"
    }
}

nonisolated enum ServiceConversionFormatting {
    static func sourceAmount(_ value: Decimal) -> String {
        sourceFormatter.string(from: value as NSDecimalNumber) ?? NSDecimalNumber(decimal: value).stringValue
    }

    static func resultAmount(_ value: Decimal, fractionDigits: Int = 4) -> String {
        CurrencyDisplayFormatting.plainNumber(value, fractionDigits: fractionDigits)
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

}
