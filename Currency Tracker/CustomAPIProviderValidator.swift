//
//  CustomAPIProviderValidator.swift
//  Currency Tracker
//
//  Created by Codex on 4/27/26.
//

import Foundation

nonisolated struct CustomAPIProviderValidationResult: Equatable, Sendable {
    let rate: Double
}

nonisolated enum CustomAPIProviderValidationError: Error, Equatable, Sendable {
    case incompleteConfiguration
    case invalidURL
    case httpStatus(Int)
    case invalidRatePath
    case network

    var message: String {
        switch self {
        case .incompleteConfiguration:
            String(localized: "请先填写 URL 模板和 JSON path")
        case .invalidURL:
            String(localized: "URL 模板无法生成有效请求")
        case .httpStatus(let statusCode):
            String(format: String(localized: "测试请求失败，HTTP 状态码 %d"), statusCode)
        case .invalidRatePath:
            String(localized: "测试返回中没有解析出有效汇率")
        case .network:
            String(localized: "测试请求失败，请检查网络和 API Key")
        }
    }
}

nonisolated enum CustomAPIProviderValidator {
    static func validate(
        provider: CustomAPIProvider,
        baseCode: String = "USD",
        quoteCode: String = "CNY",
        session: URLSession = .shared
    ) async -> Result<CustomAPIProviderValidationResult, CustomAPIProviderValidationError> {
        guard provider.isUsable else {
            return .failure(.incompleteConfiguration)
        }

        guard let url = provider.resolvedURL(baseCode: baseCode, quoteCode: quoteCode) else {
            return .failure(.invalidURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Currency Tracker", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               (200..<300).contains(httpResponse.statusCode) == false {
                return .failure(.httpStatus(httpResponse.statusCode))
            }

            guard let rate = try CustomAPIProvider.rateValue(from: data, path: provider.ratePath),
                  rate.isFinite,
                  rate > 0 else {
                return .failure(.invalidRatePath)
            }

            return .success(CustomAPIProviderValidationResult(rate: rate))
        } catch {
            return .failure(.network)
        }
    }
}
