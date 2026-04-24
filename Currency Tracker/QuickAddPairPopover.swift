//
//  QuickAddPairPopover.swift
//  Currency Tracker
//
//  Created by Codex on 4/13/26.
//

import SwiftUI

struct QuickAddPairPopover: View {
    let preferences: PreferencesStore
    let viewModel: ExchangePanelViewModel
    let onClose: () -> Void

    @State private var searchText = ""
    @State private var sourceCode = "USD"
    @State private var targetCode = "CNY"
    @State private var feedbackMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("快速添加货币对")
                .font(.system(size: 16, weight: .bold, design: .rounded))

            TextField("搜索代码、中文名或英文名", text: $searchText)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                Text("原始货币")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredSourceCurrencies.prefix(8)) { currency in
                            Button {
                                sourceCode = currency.code
                                syncTargetSelection()
                            } label: {
                                QuickAddCurrencyRow(
                                    currency: currency,
                                    isSelected: sourceCode == currency.code
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 172)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("目标货币")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Picker("目标货币", selection: $targetCode) {
                        ForEach(availableTargets) { currency in
                            Text("\(CurrencyCatalog.name(for: currency.code)) · \(currency.code)")
                                .tag(currency.code)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 180)
                }

                Spacer()
            }

            if let feedbackMessage {
                Text(feedbackMessage)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("关闭") {
                    onClose()
                }
                .buttonStyle(.borderless)

                Spacer()

                Button("加入展示") {
                    addPair()
                }
                .buttonStyle(.borderedProminent)
                .disabled(currentPair == nil)
            }
        }
        .padding(18)
        .frame(width: 360)
        .onAppear {
            initializeSelection()
        }
        .onChange(of: searchText) { _, _ in
            if filteredSourceCurrencies.contains(where: { $0.code == sourceCode }) == false,
               let first = filteredSourceCurrencies.first {
                sourceCode = first.code
                syncTargetSelection()
            }
        }
        .onChange(of: sourceCode) { _, _ in
            syncTargetSelection()
        }
    }

    private var filteredSourceCurrencies: [CurrencyInfo] {
        let sourceCurrencies = preferences.availableBaseCurrencies
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            return sourceCurrencies
        }

        return sourceCurrencies.filter { currency in
            CurrencyCatalog.matchesSearch(currency, query: query)
        }
    }

    private var availableTargets: [CurrencyInfo] {
        preferences.availableQuoteCurrencies(for: sourceCode)
    }

    private var currentPair: CurrencyPair? {
        CurrencyCatalog.supportedPair(baseCode: sourceCode, quoteCode: targetCode)
    }

    private func initializeSelection() {
        if filteredSourceCurrencies.contains(where: { $0.code == sourceCode }) == false,
           let first = filteredSourceCurrencies.first {
            sourceCode = first.code
        }

        syncTargetSelection()
    }

    private func syncTargetSelection() {
        let preferredTarget = preferences.baseCurrencyCode

        if sourceCode != preferredTarget,
           availableTargets.contains(where: { $0.code == preferredTarget }) {
            targetCode = preferredTarget
            return
        }

        if availableTargets.contains(where: { $0.code == targetCode }) == false {
            targetCode = availableTargets.first?.code ?? preferences.baseCurrencyCode
        }
    }

    private func addPair() {
        guard let currentPair else {
            return
        }

        if preferences.contains(currentPair) {
            feedbackMessage = "这个货币对已经在展示列表里。"
            return
        }

        preferences.addPair(baseCode: sourceCode, quoteCode: targetCode)
        feedbackMessage = nil
        Task {
            await viewModel.selectedPairsDidChange()
            await MainActor.run {
                onClose()
            }
        }
    }
}

private struct QuickAddCurrencyRow: View {
    let currency: CurrencyInfo
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(CurrencyCatalog.name(for: currency.code)) · \(currency.code)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(currency.englishName)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}
