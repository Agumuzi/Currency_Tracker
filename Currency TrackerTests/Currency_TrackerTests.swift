//
//  Currency_TrackerTests.swift
//  Currency TrackerTests
//
//  Created by Thomas Tao on 4/10/26.
//

import AppKit
import Foundation
import Testing
@testable import Currency_Tracker

struct Currency_TrackerTests {
    @Test
    func cbrParserNormalizesNominalValue() throws {
        let xml = """
        <?xml version="1.0" encoding="windows-1251"?>
        <ValCurs Date="10.04.2026" name="Foreign Currency Market">
            <Valute ID="R01235">
                <NumCode>840</NumCode>
                <CharCode>USD</CharCode>
                <Nominal>1</Nominal>
                <Name>Доллар США</Name>
                <Value>92,3700</Value>
            </Valute>
            <Valute ID="R01375">
                <NumCode>156</NumCode>
                <CharCode>CNY</CharCode>
                <Nominal>10</Nominal>
                <Name>Китайских юаней</Name>
                <Value>127,4000</Value>
            </Valute>
        </ValCurs>
        """.data(using: .utf8)!

        let rates = try CBRDailyParser.parseRates(from: xml)

        #expect(rates["USD"] == 92.37)
        #expect(rates["CNY"] == 12.74)
    }

    @Test
    func cbrParserExposesEffectiveDate() throws {
        let xml = """
        <?xml version="1.0" encoding="windows-1251"?>
        <ValCurs Date="10.04.2026" name="Foreign Currency Market">
            <Valute ID="R01235">
                <CharCode>USD</CharCode>
                <Nominal>1</Nominal>
                <Value>92,3700</Value>
            </Valute>
        </ValCurs>
        """.data(using: .utf8)!

        let document = try CBRDailyParser.parseDocument(from: xml)

        #expect(document.effectiveDate == "10.04.2026")
        #expect(document.ratesByCode["USD"] == 92.37)
    }

    @Test
    func currencyCatalogRejectsUnsupportedRubBasePair() {
        #expect(CurrencyCatalog.supportedPair(baseCode: "RUB", quoteCode: "USD") == nil)
        #expect(CurrencyCatalog.supportedPair(baseCode: "USD", quoteCode: "RUB") != nil)
    }

    @MainActor
    @Test
    func preferencesStoreMovesPairOrder() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let store = PreferencesStore(userDefaults: defaults)
        store.addPair(baseCode: "USD", quoteCode: "RUB")
        store.addPair(baseCode: "EUR", quoteCode: "RUB")
        let originalFirst = store.selectedPairIDs.first
        let originalSecond = store.selectedPairIDs.dropFirst().first

        if let originalSecond {
            store.movePairUp(id: originalSecond)
        }

        #expect(store.selectedPairIDs.first == originalSecond)
        #expect(store.selectedPairIDs.dropFirst().first == originalFirst)
    }

    @MainActor
    @Test
    func preferencesStoreMovesPairToDestinationIndex() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let store = PreferencesStore(userDefaults: defaults)
        store.addPair(baseCode: "USD", quoteCode: "RUB")
        store.addPair(baseCode: "EUR", quoteCode: "RUB")
        let targetID = store.selectedPairIDs.first!

        store.movePair(id: targetID, to: store.selectedPairIDs.count)

        #expect(store.selectedPairIDs.last == targetID)
    }

    @MainActor
    @Test
    func preferencesStoreStartsEmptyOnFirstLaunch() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let store = PreferencesStore(userDefaults: defaults)

        #expect(store.selectedPairs.isEmpty)
        #expect(store.featuredPairID.isEmpty)
    }

    @MainActor
    @Test
    func preferencesStorePersistsFeaturedPairAndDisplayFlags() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let store = PreferencesStore(userDefaults: defaults)
        store.addPair(baseCode: "USD", quoteCode: "RUB")
        store.addPair(baseCode: "EUR", quoteCode: "RUB")
        let targetID = store.selectedPairIDs.dropFirst().first ?? store.selectedPairIDs.first ?? ""

        store.setFeaturedPair(id: targetID)
        store.setShowsFlags(true)

        #expect(store.featuredPairID == targetID)
        #expect(store.showsFlags)
    }

    @MainActor
    @Test
    func preferencesStorePersistsBaseCurrencyCode() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let store = PreferencesStore(userDefaults: defaults)
        store.setBaseCurrencyCode("JPY")

        #expect(store.baseCurrencyCode == "JPY")
        #expect(defaults.string(forKey: "baseCurrencyCode") == "JPY")
    }

    @MainActor
    @Test
    func preferencesStorePersistsSoftwareUpdateOptions() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let lastCheck = Date(timeIntervalSince1970: 1_777_000_000)

        let store = PreferencesStore(userDefaults: defaults)
        store.setAutomaticUpdateChecksEnabled(false)
        store.skipUpdate(version: "1.2")
        store.setLastAutomaticUpdateCheckAt(lastCheck)

        let reloaded = PreferencesStore(userDefaults: defaults)

        #expect(reloaded.automaticUpdateChecksEnabled == false)
        #expect(reloaded.skippedUpdateVersion == "1.2")
        #expect(reloaded.lastAutomaticUpdateCheckAt == lastCheck)
    }

    @MainActor
    @Test
    func credentialStoreReadsAndWritesSecretsFromLocalAdapter() throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let secretStore = InMemorySecretStore()
        let store = EnhancedSourceCredentialStore(secretStore: secretStore, userDefaults: defaults)

        try store.save("  td-key  ", for: .twelveData)
        try store.save("  oxr-id  ", for: .openExchangeRates)
        try store.save("  era-key  ", for: .exchangeRateAPI)

        #expect(store.storedValue(for: .twelveData) == "td-key")
        #expect(store.storedValue(for: .openExchangeRates) == "oxr-id")
        #expect(store.storedValue(for: .exchangeRateAPI) == "era-key")
        #expect(store.configuration.hasTwelveDataKey)
        #expect(store.configuration.hasOpenExchangeRatesAppID)
        #expect(store.configuration.hasExchangeRateAPIKey)
    }

    @MainActor
    @Test
    func credentialStorePersistsSelectedAPISources() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let secretStore = InMemorySecretStore()
        let store = EnhancedSourceCredentialStore(secretStore: secretStore, userDefaults: defaults)

        store.addSelectedKind(.fixer)

        let reloaded = EnhancedSourceCredentialStore(secretStore: secretStore, userDefaults: defaults)

        #expect(reloaded.selectedKinds.contains(.twelveData))
        #expect(reloaded.selectedKinds.contains(.openExchangeRates))
        #expect(reloaded.selectedKinds.contains(.fixer))
    }

    @MainActor
    @Test
    func credentialStoreMigratesLegacyDefaultsIntoLocalAdapter() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set("legacy-td", forKey: "twelveDataAPIKey")
        defaults.set("legacy-oxr", forKey: "openExchangeRatesAppID")
        let secretStore = InMemorySecretStore()

        let store = EnhancedSourceCredentialStore(secretStore: secretStore, userDefaults: defaults)

        #expect(store.storedValue(for: .twelveData) == "legacy-td")
        #expect(store.storedValue(for: .openExchangeRates) == "legacy-oxr")
        #expect(defaults.string(forKey: "twelveDataAPIKey") == nil)
        #expect(defaults.string(forKey: "openExchangeRatesAppID") == nil)
    }

    @MainActor
    @Test
    func credentialStoreKeepsLegacyDefaultsWhenLocalMigrationFails() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set("legacy-td", forKey: "twelveDataAPIKey")
        let secretStore = FailingWriteSecretStore()

        let store = EnhancedSourceCredentialStore(secretStore: secretStore, userDefaults: defaults)

        #expect(store.storedValue(for: .twelveData) == "legacy-td")
        #expect(defaults.string(forKey: "twelveDataAPIKey") == "legacy-td")
    }

    @MainActor
    @Test
    func credentialStoreReportsLocalStoreReadFailuresSeparatelyFromEmptyState() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = EnhancedSourceCredentialStore(secretStore: FailingReadSecretStore(), userDefaults: defaults)

        #expect(store.storedValue(for: .twelveData).isEmpty)
        #expect(store.lastLoadError(for: .twelveData) == "本地凭证存储当前不可用，请稍后重试")
    }

    @MainActor
    @Test
    func apiConfigurationViewModelSavesCredentialAfterValidationSucceeds() async throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let secretStore = InMemorySecretStore()
        let credentialStore = EnhancedSourceCredentialStore(secretStore: secretStore, userDefaults: defaults)
        let viewModel = APIConfigurationViewModel(
            credentialStore: credentialStore,
            service: StubValidationService(results: [:]),
            logHandler: { _, _ in }
        )

        viewModel.beginEditing(.twelveData)
        viewModel.updateDraft("  valid-key  ", for: .twelveData)
        await viewModel.performPrimaryAction(for: .twelveData)

        let field = viewModel.field(for: .twelveData)
        #expect(field.isEditing == false)
        #expect(field.phase == .enabled)
        #expect(field.buttonTitle == "编辑")
        #expect(credentialStore.storedValue(for: .twelveData) == "valid-key")
    }

    @MainActor
    @Test
    func apiConfigurationViewModelKeepsDraftWhenValidationFails() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let credentialStore = EnhancedSourceCredentialStore(secretStore: InMemorySecretStore(), userDefaults: defaults)
        let viewModel = APIConfigurationViewModel(
            credentialStore: credentialStore,
            service: StubValidationService(results: [.twelveData: "验证失败，请检查 key"]),
            logHandler: { _, _ in }
        )

        viewModel.beginEditing(.twelveData)
        viewModel.updateDraft("broken-key", for: .twelveData)
        await viewModel.performPrimaryAction(for: .twelveData)

        let field = viewModel.field(for: .twelveData)
        #expect(field.isEditing)
        #expect(field.draftValue == "broken-key")
        #expect(field.phase == .failure("验证失败，请检查 key"))
        #expect(credentialStore.storedValue(for: .twelveData).isEmpty)
    }

    @Test
    func refreshPolicyThrottlesMenuOpenAutoRefreshWithinTenMinutes() {
        let now = Date()

        let decision = RefreshPolicy.shouldAutoRefreshOnOpen(
            lastSuccessfulRefreshAt: now.addingTimeInterval(-5 * 60),
            isEnabled: true,
            isPinned: false,
            now: now
        )

        #expect(isSkippedBecauseThrottle(decision))
    }

    @Test
    func refreshPolicyRefreshesHistoryWhenCacheMissingSelectedPairs() {
        let decision = RefreshPolicy.shouldRefreshHistory(
            lastHistoricalRefreshAt: .now,
            cachedHistoryPairIDs: [],
            selectedPairIDs: [CurrencyPair.defaults[0].id]
        )

        #expect(isRefreshDecision(decision))
    }

    @Test
    func softwareUpdateComparatorHandlesTaggedSemanticVersions() {
        #expect(SoftwareVersionComparator.normalized("v1.2.0") == "1.2.0")
        #expect(SoftwareVersionComparator.compare("v1.2", "1.1.9") == .orderedDescending)
        #expect(SoftwareVersionComparator.compare("1.1.0", "1.1") == .orderedSame)
        #expect(SoftwareVersionComparator.compare("1.0.9", "1.1") == .orderedAscending)
    }

    @Test
    func softwareUpdateParserExtractsZipAsset() throws {
        let data = Data(
            #"""
            {
              "tag_name": "v1.2",
              "name": "Currency Tracker 1.2",
              "body": "Improved update window.",
              "html_url": "https://github.com/Agumuzi/Currency_Tracker/releases/tag/v1.2",
              "assets": [
                {
                  "name": "Currency-Tracker-1.2.zip",
                  "browser_download_url": "https://github.com/Agumuzi/Currency_Tracker/releases/download/v1.2/Currency-Tracker-1.2.zip"
                }
              ]
            }
            """#.utf8
        )

        let info = try SoftwareUpdateChecker.parseLatestRelease(from: data)

        #expect(info.version == "1.2")
        #expect(info.isNewer(than: "1.1"))
        #expect(info.downloadURL?.absoluteString.hasSuffix("Currency-Tracker-1.2.zip") == true)
        #expect(info.title == "Currency Tracker 1.2")
        #expect(info.releaseNotes == "Improved update window.")
    }

    @MainActor
    @Test
    func panelWindowControllerPinnedStateDisablesAutoRefreshAndRestoresPanelBehavior() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let preferences = PreferencesStore(userDefaults: defaults)
        preferences.addPair(baseCode: "USD", quoteCode: "RUB")
        let viewModel = ExchangePanelViewModel(
            preferences: preferences,
            credentialStore: EnhancedSourceCredentialStore(secretStore: InMemorySecretStore(), userDefaults: defaults),
            previewState: .sample
        )
        let controller = PanelWindowController(viewModel: viewModel)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.hidesOnDeactivate = true

        controller.registerMenuBarWindow(panel)
        controller.togglePinnedPanel(from: panel)

        #expect(controller.isPinned)
        #expect(panel.level == .floating)
        #expect(panel.hidesOnDeactivate == false)
        #expect(viewModel.shouldAutoRefreshOnOpen() == false)

        controller.togglePinnedPanel(from: panel)

        #expect(controller.isPinned == false)
        #expect(panel.hidesOnDeactivate == true)
    }

    @MainActor
    @Test
    func panelWindowControllerKeepsPinnedStateOnMenuWindowAndDismissesTransientWindows() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let preferences = PreferencesStore(userDefaults: defaults)
        preferences.addPair(baseCode: "USD", quoteCode: "RUB")
        let viewModel = ExchangePanelViewModel(
            preferences: preferences,
            credentialStore: EnhancedSourceCredentialStore(secretStore: InMemorySecretStore(), userDefaults: defaults),
            previewState: .sample
        )
        let controller = PanelWindowController(viewModel: viewModel)
        let menuPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        menuPanel.hidesOnDeactivate = true
        let transientPanel = NSPanel(
            contentRect: NSRect(x: 20, y: 20, width: 320, height: 240),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        controller.registerMenuBarWindow(menuPanel)
        controller.togglePinnedPanel(from: menuPanel)

        #expect(controller.isPinned)
        #expect(menuPanel.level == .floating)
        #expect(menuPanel.hidesOnDeactivate == false)
        #expect(viewModel.shouldAutoRefreshOnOpen() == false)

        transientPanel.orderFront(nil)
        controller.registerMenuBarWindow(transientPanel)

        #expect(controller.isPinned)
        #expect(transientPanel.isVisible == false)
        #expect(menuPanel.level == .floating)

        controller.togglePinnedPanel(from: menuPanel)

        #expect(controller.isPinned == false)
        #expect(menuPanel.hidesOnDeactivate == true)
    }

    @MainActor
    @Test
    func dockVisibilityControllerSwitchesActivationPolicyForSettingsWindow() {
        let applicationController = TestApplicationActivationController(initialPolicy: .accessory)
        var logs: [String] = []
        let controller = DockVisibilityController(
            applicationController: applicationController,
            logHandler: { _, message in
                logs.append(message)
            }
        )

        controller.showDockForSettingsWindow()
        #expect(applicationController.activationPolicy() == .regular)

        controller.restoreMenuBarOnlyMode()
        #expect(applicationController.activationPolicy() == .accessory)
        #expect(logs == [
            "设置窗口已打开，Dock 图标已显示",
            "设置窗口已关闭，Dock 图标已隐藏"
        ])
    }

    @Test
    func trendRangeFiltersRecentPoints() {
        let now = Date()
        let points = [
            TrendPoint(timestamp: now.addingTimeInterval(-9 * 24 * 3600), value: 1),
            TrendPoint(timestamp: now.addingTimeInterval(-2 * 24 * 3600), value: 2),
            TrendPoint(timestamp: now.addingTimeInterval(-3600), value: 3)
        ]

        let filtered = TrendRange.sixHours.filter(points: points, now: now)

        #expect(filtered.count == 2)
        #expect(filtered.last?.value == 3)
    }

    @Test
    func trendPointSamplerKeepsFirstAndLastPoint() {
        let points = (0..<6).map {
            TrendPoint(timestamp: Date(timeIntervalSince1970: Double($0) * 3600), value: Double($0))
        }

        let sampled = TrendPointSampler.sample(points, maxPoints: 3)

        #expect(sampled.count == 3)
        #expect(sampled.first?.value == 0)
        #expect(sampled.last?.value == 5)
    }

    @Test
    func cbrDynamicParserNormalizesHistoricalNominalValue() throws {
        let xml = """
        <?xml version="1.0" encoding="windows-1251"?>
        <ValCurs ID="R01375" DateRange1="01.04.2026" DateRange2="10.04.2026" name="Foreign Currency Market Dynamic">
            <Record Date="01.04.2026" Id="R01375">
                <Nominal>10</Nominal>
                <Value>126,4000</Value>
            </Record>
            <Record Date="02.04.2026" Id="R01375">
                <Nominal>10</Nominal>
                <Value>127,0000</Value>
            </Record>
        </ValCurs>
        """.data(using: .utf8)!

        let points = try CBRDynamicParser.parsePoints(from: xml)

        #expect(points.count == 2)
        #expect(points.first?.value == 12.64)
        #expect(points.last?.value == 12.70)
    }

    @Test
    func ecbParserExtractsSeriesByCurrency() throws {
        let payload = """
        {
          "dataSets": [
            {
              "series": {
                "0:0:0:0:0": {
                  "observations": {
                    "0": [7.9863, 0, 0, null, null],
                    "1": [7.9967, 0, 0, null, null]
                  }
                },
                "0:1:0:0:0": {
                  "observations": {
                    "0": [1.1685, 0, 0, null, null],
                    "1": [1.1711, 0, 0, null, null]
                  }
                }
              }
            }
          ],
          "structure": {
            "dimensions": {
              "series": [
                {"id": "FREQ", "values": [{"id": "D"}]},
                {"id": "CURRENCY", "values": [{"id": "CNY"}, {"id": "USD"}]},
                {"id": "CURRENCY_DENOM", "values": [{"id": "EUR"}]},
                {"id": "EXR_TYPE", "values": [{"id": "SP00"}]},
                {"id": "EXR_SUFFIX", "values": [{"id": "A"}]}
              ],
              "observation": [
                {
                  "id": "TIME_PERIOD",
                  "values": [{"id": "2026-04-09"}, {"id": "2026-04-10"}]
                }
              ]
            }
          }
        }
        """.data(using: .utf8)!

        let series = try ECBEXRParser.parseSeriesByCurrency(from: payload)

        #expect(series["USD"]?.count == 2)
        #expect(series["USD"]?.last?.value == 1.1711)
        #expect(series["CNY"]?.last?.value == 7.9967)
    }

    @Test
    func currencyAPIParserExtractsDynamicRates() throws {
        let payload = """
        {
          "date": "2026-04-11",
          "usd": {
            "cny": 6.82803946,
            "eur": 0.85270392
          }
        }
        """.data(using: .utf8)!

        let parsed = try CurrencyAPIParser.parseRates(from: payload, expectedBaseCode: "usd")

        #expect(parsed.date == "2026-04-11")
        #expect(parsed.rates["cny"] == 6.82803946)
        #expect(parsed.rates["eur"] == 0.85270392)
    }

    @Test
    func currencyAPIParserIgnoresMetadataAndUsesExpectedBaseCode() throws {
        let payload = """
        {
          "date": "2026-04-11",
          "meta": {
            "provider": "jsdelivr"
          },
          "usd": {
            "cny": 6.82803946,
            "eur": 0.85270392
          }
        }
        """.data(using: .utf8)!

        let parsed = try CurrencyAPIParser.parseRates(from: payload, expectedBaseCode: "usd")

        #expect(parsed.date == "2026-04-11")
        #expect(parsed.rates["cny"] == 6.82803946)
        #expect(parsed.rates["eur"] == 0.85270392)
    }

    @Test
    func twelveDataParserExtractsExchangeRate() throws {
        let payload = """
        {
          "symbol": "USD/CNY",
          "rate": "6.8284",
          "timestamp": 1775779200
        }
        """.data(using: .utf8)!

        let parsed = try TwelveDataParser.parseExchangeRate(from: payload)

        #expect(parsed.rate == 6.8284)
        #expect(parsed.timestamp.map(SourceDateParser.isoQueryString(from:)) == "2026-04-10")
    }

    @Test
    func twelveDataValidationUsesLatestAPIVersionAndReadsErrorBody() async {
        TwelveDataStatusCodeURLProtocol.lastAPIVersionHeader = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TwelveDataStatusCodeURLProtocol.self]
        let service = ExchangeRateService(urlSession: URLSession(configuration: configuration))

        let validationMessage = await service.validateTwelveDataAPIKey("test-key")

        #expect(TwelveDataStatusCodeURLProtocol.lastAPIVersionHeader == "last")
        #expect(validationMessage == "验证失败，请稍后重试")
    }

    @Test
    func openExchangeRatesParserExtractsLatestRates() throws {
        let payload = """
        {
          "timestamp": 1775865600,
          "base": "USD",
          "rates": {
            "CNY": 6.8284,
            "EUR": 0.8782,
            "RUB": 85.21
          }
        }
        """.data(using: .utf8)!

        let parsed = try OpenExchangeRatesParser.parseLatest(from: payload)

        #expect(parsed.rate(for: "USD") == 1)
        #expect(parsed.rate(for: "CNY") == 6.8284)
        #expect(parsed.rate(for: "RUB") == 85.21)
    }

    @Test
    func exchangeRateAPIParserExtractsLatestRates() throws {
        let payload = """
        {
          "result": "success",
          "time_last_update_unix": 1775865600,
          "base_code": "USD",
          "conversion_rates": {
            "USD": 1,
            "CNY": 6.8284,
            "RUB": 85.21
          }
        }
        """.data(using: .utf8)!

        let parsed = try ExchangeRateAPIParser.parseLatest(from: payload)

        #expect(parsed.baseCode == "USD")
        #expect(parsed.rate(for: "USD") == 1)
        #expect(parsed.rate(for: "CNY") == 6.8284)
        #expect(parsed.timestamp.map(SourceDateParser.isoQueryString(from:)) == "2026-04-11")
    }

    @Test
    func fixerParserExtractsLatestRates() throws {
        let payload = """
        {
          "success": true,
          "timestamp": 1775865600,
          "base": "EUR",
          "date": "2026-04-11",
          "rates": {
            "USD": 1.1387,
            "CNY": 7.7742
          }
        }
        """.data(using: .utf8)!

        let parsed = try FixerParser.parseLatest(from: payload)

        #expect(parsed.baseCode == "EUR")
        #expect(parsed.rate(for: "EUR") == 1)
        #expect(parsed.rate(for: "USD") == 1.1387)
        #expect(parsed.date == "2026-04-11")
    }

    @Test
    func currencyLayerParserExtractsLiveQuotes() throws {
        let payload = """
        {
          "success": true,
          "timestamp": 1775865600,
          "source": "USD",
          "quotes": {
            "USDCNY": 6.8284,
            "USDRUB": 85.21
          }
        }
        """.data(using: .utf8)!

        let parsed = try CurrencyLayerParser.parseLive(from: payload)

        #expect(parsed.sourceCode == "USD")
        #expect(parsed.rate(for: "USD") == 1)
        #expect(parsed.rate(for: "CNY") == 6.8284)
        #expect(parsed.rate(for: "RUB") == 85.21)
    }

    @Test
    func sourceDateParserNormalizesHttpDate() {
        let date = SourceDateParser.httpDay("Fri, 10 Apr 2026 21:55:05 GMT")

        #expect(date.map(SourceDateParser.isoQueryString(from:)) == "2026-04-10")
    }

    @Test
    func legacyCacheDecodesWithoutRefreshLog() throws {
        let legacy = """
        {
          "history" : {},
          "lastRefreshAttempt" : "2026-04-10T12:00:00Z",
          "snapshots" : []
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LegacyCachedExchangeState.self, from: legacy)

        #expect(decoded.snapshots.isEmpty)
        #expect(decoded.history.isEmpty)
    }

    @MainActor
    @Test
    func exchangePanelViewModelRespectsExplicitCacheFlag() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let store = PreferencesStore(userDefaults: defaults)
        store.addPair(baseCode: "USD", quoteCode: "RUB")
        let state = CachedExchangeState(
            snapshots: [
                CurrencySnapshot(
                    pair: CurrencyPair.defaults[0],
                    rate: 92.37,
                    updatedAt: .now,
                    effectiveDateText: "2026-04-10",
                    source: .cbr,
                    isCached: true
                )
            ],
            history: [:],
            lastRefreshAttempt: .now,
            refreshLog: []
        )

        let viewModel = ExchangePanelViewModel(
            preferences: store,
            credentialStore: EnhancedSourceCredentialStore(secretStore: InMemorySecretStore(), userDefaults: defaults),
            previewState: state
        )

        #expect(viewModel.cards.first?.state == .stale)
        #expect(viewModel.cards.first?.isCached == true)
    }

    @MainActor
    @Test
    func exchangePanelViewModelCreatesLoadingCardsBeforeFirstFetch() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let store = PreferencesStore(userDefaults: defaults)
        store.addPair(baseCode: "USD", quoteCode: "RUB")
        store.addPair(baseCode: "EUR", quoteCode: "RUB")
        let viewModel = ExchangePanelViewModel(
            preferences: store,
            credentialStore: EnhancedSourceCredentialStore(secretStore: InMemorySecretStore(), userDefaults: defaults),
            previewState: CachedExchangeState(
                snapshots: [],
                history: [:],
                lastRefreshAttempt: nil,
                refreshLog: []
            )
        )

        #expect(viewModel.cards.count == store.selectedPairs.count)
        #expect(viewModel.cards.allSatisfy { $0.state == .loading })
    }

    @MainActor
    @Test
    func exchangePanelViewModelExposesFeaturedHelpSummary() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let store = PreferencesStore(userDefaults: defaults)
        store.addPair(baseCode: "USD", quoteCode: "RUB")
        store.addPair(baseCode: "EUR", quoteCode: "RUB")
        let targetPair = CurrencyPair.defaults[0]
        store.setFeaturedPair(id: targetPair.id)

        let viewModel = ExchangePanelViewModel(
            preferences: store,
            credentialStore: EnhancedSourceCredentialStore(secretStore: InMemorySecretStore(), userDefaults: defaults),
            previewState: .sample
        )

        #expect(viewModel.menuBarHelpText.contains("2026-04-10"))
        #expect(viewModel.menuBarHelpText.contains("当前 92.37"))
    }

    @Test
    func cardTrendRangeFiltersToRecentWindow() {
        let now = Date()
        let points = [
            TrendPoint(timestamp: now.addingTimeInterval(-390 * 24 * 3600), value: 1),
            TrendPoint(timestamp: now.addingTimeInterval(-40 * 24 * 3600), value: 2),
            TrendPoint(timestamp: now.addingTimeInterval(-6 * 24 * 3600), value: 3)
        ]

        let filtered = CardTrendRange.sevenDays.filter(points: points, now: now)

        #expect(filtered.count == 1)
        #expect(filtered.first?.value == 3)
    }

    @Test
    func snapshotRetainsEffectiveDateWhenCacheFlagChanges() {
        let snapshot = CurrencySnapshot(
            pair: CurrencyPair.defaults[0],
            rate: 92.37,
            updatedAt: .now,
            effectiveDateText: "2026-04-10",
            source: .cbr,
            isCached: false
        )

        let cachedSnapshot = snapshot.withCacheFlag(true)

        #expect(cachedSnapshot.effectiveDateText == "2026-04-10")
        #expect(cachedSnapshot.isCached)
    }

    @Test
    @MainActor
    func exchangeRateServiceFetchesSnapshotsUsingStubbedProviders() async {
        let session = URLSession(configuration: .mockedSessionConfiguration)
        let service = ExchangeRateService(urlSession: session)
        let result = await service.fetchSnapshots(for: CurrencyPair.defaults)
        let hasSuccessfulSource = result.sourceStatuses.contains { status in
            status.state == .success || status.state == .partial
        }

        #expect(result.snapshots.count >= 5)
        #expect(hasSuccessfulSource)
        #expect(result.errors.isEmpty)
    }

    @Test
    func moneyParserRecognizesExplicitCurrenciesAcrossFormats() {
        let explicitCode = MoneyParsing.parse("1,234.56 USD")
        let explicitSymbol = MoneyParsing.parse("€299")
        let localized = MoneyParsing.parse("1 234,56 EUR")

        #expect(matchesResolvedAmount(explicitCode, decimal("1234.56")))
        #expect(explicitCode?.currency == .explicit(code: "USD"))
        #expect(matchesResolvedAmount(explicitSymbol, decimal("299")))
        #expect(explicitSymbol?.currency == .explicit(code: "EUR"))
        #expect(matchesResolvedAmount(localized, decimal("1234.56")))
        #expect(localized?.currency == .explicit(code: "EUR"))
    }

    @Test
    func moneyParserFlagsAmbiguousSymbolsAndPureNumbers() {
        let dollar = MoneyParsing.parse("$1,234.56")
        let yen = MoneyParsing.parse("¥12,800")
        let numberOnly = MoneyParsing.parse("1,234")

        #expect(matchesResolvedAmount(dollar, decimal("1234.56")))
        #expect(dollar?.currency == .ambiguous(symbol: "$", candidates: ["USD", "CAD", "AUD", "HKD", "SGD", "NZD"]))
        #expect(matchesResolvedAmount(yen, decimal("12800")))
        #expect(yen?.currency == .ambiguous(symbol: "¥", candidates: ["CNY", "JPY"]))
        #expect(matchesAmbiguousAmount(numberOnly, rawText: "1,234"))
        #expect(numberOnly?.currency == .missing)
    }

    @Test
    func currencyInputNormalizationMapsCommonAliases() {
        #expect(CurrencyInputNormalization.normalize("美元") == "USD")
        #expect(CurrencyInputNormalization.normalize("RMB") == "CNY")
        #expect(CurrencyInputNormalization.normalize("日元") == "JPY")
        #expect(CurrencyInputNormalization.normalize("eur") == "EUR")
        #expect(CurrencyInputNormalization.normalize("卢布") == "RUB")
        #expect(CurrencyInputNormalization.normalize("Turkish Lira") == "TRY")
        #expect(CurrencyInputNormalization.detectCurrency(in: "土耳其 599.99") == "TRY")
    }

    @Test
    func moneyParserPrefersNearbyCurrencyContext() {
        let nearby = MoneyParsing.parse("约 599.99 土耳其里拉")
        let distant = MoneyParsing.parse("土耳其旅游行程已经确认，酒店和机票已锁定，最终结算金额是 599.99")

        #expect(matchesResolvedAmount(nearby, decimal("599.99")))
        #expect(nearby?.currency == .explicit(code: "TRY"))
        #expect(matchesResolvedAmount(distant, decimal("599.99")))
        #expect(distant?.currency == .missing)
    }

    @MainActor
    @Test
    func conversionCoordinatorUsesFreshCacheWithoutRefreshing() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let preferences = PreferencesStore(userDefaults: defaults)
        preferences.setBaseCurrencyCode("CNY")
        let credentialStore = EnhancedSourceCredentialStore(secretStore: InMemorySecretStore(), userDefaults: defaults)

        let pair = CurrencyPair(baseCode: "USD", quoteCode: "CNY", baseAmount: 1)
        let snapshot = CurrencySnapshot(
            pair: pair,
            rate: 7.25,
            updatedAt: .now.addingTimeInterval(-15 * 60),
            effectiveDateText: nil,
            source: .ecb,
            isCached: true
        )
        let store = InMemoryExchangeStateStore(state: CachedExchangeState(
            snapshots: [snapshot],
            history: [:],
            lastRefreshAttempt: .now.addingTimeInterval(-15 * 60),
            refreshLog: []
        ))
        let promptPanel = StubPromptPanel()
        let clipboardWriter = StubClipboardWriter()
        let service = StubSnapshotService()
        let coordinator = ConversionCoordinator(
            preferences: preferences,
            credentialStore: credentialStore,
            service: service,
            store: store,
            promptPanel: promptPanel,
            clipboardWriter: clipboardWriter,
            liveLogHandler: { _, _ in }
        )

        await coordinator.handleSelectedText("1234 USD")

        #expect(await service.fetchCallCount == 0)
        #expect(promptPanel.resultPresentations.count == 1)
        #expect(promptPanel.resultPresentations.first?.expressionText == "1234 USD ≈ 8946.50 CNY")
        #expect(clipboardWriter.writtenStrings == ["8946.50 CNY"])
        #expect(promptPanel.ambiguousPromptCount == 0)
        #expect(promptPanel.manualPromptCount == 0)
    }

    @MainActor
    @Test
    func conversionCoordinatorReusesInverseRateForRubConversions() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let preferences = PreferencesStore(userDefaults: defaults)
        preferences.setBaseCurrencyCode("CNY")
        let credentialStore = EnhancedSourceCredentialStore(secretStore: InMemorySecretStore(), userDefaults: defaults)

        let inversePair = CurrencyPair(baseCode: "CNY", quoteCode: "RUB", baseAmount: 1)
        let snapshot = CurrencySnapshot(
            pair: inversePair,
            rate: 12.5,
            updatedAt: .now.addingTimeInterval(-20 * 60),
            effectiveDateText: nil,
            source: .cbr,
            isCached: true
        )
        let store = InMemoryExchangeStateStore(state: CachedExchangeState(
            snapshots: [snapshot],
            history: [:],
            lastRefreshAttempt: .now.addingTimeInterval(-20 * 60),
            refreshLog: []
        ))
        let promptPanel = StubPromptPanel()
        let coordinator = ConversionCoordinator(
            preferences: preferences,
            credentialStore: credentialStore,
            service: StubSnapshotService(),
            store: store,
            promptPanel: promptPanel,
            clipboardWriter: StubClipboardWriter(),
            liveLogHandler: { _, _ in }
        )

        await coordinator.handleSelectedText("₽5000")

        #expect(promptPanel.resultPresentations.count == 1)
        #expect(promptPanel.resultPresentations.first?.expressionText == "5000 RUB ≈ 400.00 CNY")
    }

    @MainActor
    @Test
    func conversionCoordinatorFallsBackToStaleCacheWhenSilentRefreshFails() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let preferences = PreferencesStore(userDefaults: defaults)
        preferences.setBaseCurrencyCode("CNY")
        let credentialStore = EnhancedSourceCredentialStore(secretStore: InMemorySecretStore(), userDefaults: defaults)

        let pair = CurrencyPair(baseCode: "USD", quoteCode: "CNY", baseAmount: 1)
        let staleSnapshot = CurrencySnapshot(
            pair: pair,
            rate: 7.1,
            updatedAt: .now.addingTimeInterval(-3 * 60 * 60),
            effectiveDateText: nil,
            source: .ecb,
            isCached: true
        )
        let store = InMemoryExchangeStateStore(state: CachedExchangeState(
            snapshots: [staleSnapshot],
            history: [:],
            lastRefreshAttempt: .now.addingTimeInterval(-3 * 60 * 60),
            refreshLog: []
        ))
        let service = StubSnapshotService()
        await service.enqueue(result: ExchangeFetchResult(
            snapshots: [],
            errors: ["网络错误"],
            sourceStatuses: [],
            logs: []
        ))
        let promptPanel = StubPromptPanel()
        let coordinator = ConversionCoordinator(
            preferences: preferences,
            credentialStore: credentialStore,
            service: service,
            store: store,
            promptPanel: promptPanel,
            clipboardWriter: StubClipboardWriter(),
            liveLogHandler: { _, _ in }
        )

        await coordinator.handleSelectedText("100 USD")

        #expect(await service.fetchCallCount == 1)
        #expect(promptPanel.resultPresentations.count == 1)
        #expect(promptPanel.resultPresentations.first?.expressionText == "100 USD ≈ 710.00 CNY")
    }

    @MainActor
    @Test
    func conversionCoordinatorPromptsForAmbiguousAndNumberOnlySelections() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let preferences = PreferencesStore(userDefaults: defaults)
        preferences.setBaseCurrencyCode("CNY")
        let credentialStore = EnhancedSourceCredentialStore(secretStore: InMemorySecretStore(), userDefaults: defaults)

        let usdPair = CurrencyPair(baseCode: "USD", quoteCode: "CNY", baseAmount: 1)
        let jpyPair = CurrencyPair(baseCode: "JPY", quoteCode: "CNY", baseAmount: 1)
        let store = InMemoryExchangeStateStore(state: CachedExchangeState(
            snapshots: [
                CurrencySnapshot(pair: usdPair, rate: 7.2, updatedAt: .now.addingTimeInterval(-10 * 60), effectiveDateText: nil, source: .ecb, isCached: true),
                CurrencySnapshot(pair: jpyPair, rate: 0.05, updatedAt: .now.addingTimeInterval(-10 * 60), effectiveDateText: nil, source: .ecb, isCached: true)
            ],
            history: [:],
            lastRefreshAttempt: .now.addingTimeInterval(-10 * 60),
            refreshLog: []
        ))
        let promptPanel = StubPromptPanel()
        promptPanel.ambiguousResponse = "USD"
        promptPanel.manualResponse = "JPY"
        let coordinator = ConversionCoordinator(
            preferences: preferences,
            credentialStore: credentialStore,
            service: StubSnapshotService(),
            store: store,
            promptPanel: promptPanel,
            clipboardWriter: StubClipboardWriter(),
            liveLogHandler: { _, _ in }
        )

        await coordinator.handleSelectedText("$128")
        await coordinator.handleSelectedText("500")

        #expect(promptPanel.ambiguousPromptCount == 1)
        #expect(promptPanel.manualPromptCount == 1)
        #expect(promptPanel.resultPresentations.count == 2)
        #expect(promptPanel.resultPresentations.first?.expressionText == "128 USD ≈ 921.60 CNY")
        #expect(promptPanel.resultPresentations.last?.expressionText == "500 JPY ≈ 25.00 CNY")
    }

    @MainActor
    @Test
    func conversionCoordinatorPromptsForAmbiguousNumberInterpretation() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let preferences = PreferencesStore(userDefaults: defaults)
        preferences.setBaseCurrencyCode("USD")
        let credentialStore = EnhancedSourceCredentialStore(secretStore: InMemorySecretStore(), userDefaults: defaults)

        let pair = CurrencyPair(baseCode: "EUR", quoteCode: "USD", baseAmount: 1)
        let store = InMemoryExchangeStateStore(state: CachedExchangeState(
            snapshots: [
                CurrencySnapshot(pair: pair, rate: 1.08, updatedAt: .now.addingTimeInterval(-10 * 60), effectiveDateText: nil, source: .ecb, isCached: true)
            ],
            history: [:],
            lastRefreshAttempt: .now.addingTimeInterval(-10 * 60),
            refreshLog: []
        ))
        let promptPanel = StubPromptPanel()
        promptPanel.amountResponse = decimal("1.234")
        let clipboardWriter = StubClipboardWriter()
        let coordinator = ConversionCoordinator(
            preferences: preferences,
            credentialStore: credentialStore,
            service: StubSnapshotService(),
            store: store,
            promptPanel: promptPanel,
            clipboardWriter: clipboardWriter,
            liveLogHandler: { _, _ in }
        )

        await coordinator.handleSelectedText("1,234 EUR")

        #expect(promptPanel.amountPromptCount == 1)
        #expect(promptPanel.resultPresentations.first?.expressionText == "1.234 EUR ≈ 1.3327 USD")
        #expect(clipboardWriter.writtenStrings == ["1.3327 USD"])
    }
}

private func decimal(_ string: String) -> Decimal {
    Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
}

private actor InMemoryExchangeStateStore: ExchangeStateStoring {
    private var state: CachedExchangeState?

    init(state: CachedExchangeState?) {
        self.state = state
    }

    func load() async -> CachedExchangeState? {
        state
    }

    func save(_ state: CachedExchangeState) async {
        self.state = state
    }
}

private actor StubSnapshotService: ExchangeSnapshotFetching {
    private(set) var fetchCallCount = 0
    private var queuedResults: [ExchangeFetchResult] = []

    func enqueue(result: ExchangeFetchResult) {
        queuedResults.append(result)
    }

    func fetchSnapshots(
        for pairs: [CurrencyPair],
        configuration: EnhancedSourceConfiguration
    ) async -> ExchangeFetchResult {
        fetchCallCount += 1
        if queuedResults.isEmpty {
            return ExchangeFetchResult(snapshots: [], errors: [], sourceStatuses: [], logs: [])
        }

        return queuedResults.removeFirst()
    }
}

@MainActor
private final class StubPromptPanel: LightweightPromptPaneling {
    var ambiguousResponse: String?
    var manualResponse: String?
    var amountResponse: Decimal?
    private(set) var ambiguousPromptCount = 0
    private(set) var manualPromptCount = 0
    private(set) var amountPromptCount = 0
    private(set) var lastError: (title: String, message: String)?
    private(set) var resultPresentations: [ConversionPresentation] = []

    func chooseCurrencyForAmbiguousSymbol(
        amount: Decimal,
        symbol: String,
        candidates: [String],
        targetCurrencyCode: String
    ) async -> String? {
        ambiguousPromptCount += 1
        return ambiguousResponse
    }

    func chooseCurrencyForManualInput(
        amount: Decimal,
        targetCurrencyCode: String
    ) async -> String? {
        manualPromptCount += 1
        return manualResponse
    }

    func chooseAmountInterpretation(
        rawText: String,
        options: [MoneyParsing.AmountOption]
    ) async -> Decimal? {
        amountPromptCount += 1
        return amountResponse ?? options.first?.value
    }

    func showResult(_ presentation: ConversionPresentation) async -> Bool {
        resultPresentations.append(presentation)
        return true
    }

    func showError(title: String, message: String) async {
        lastError = (title, message)
    }
}

@MainActor
private final class StubClipboardWriter: ClipboardWriting {
    private(set) var writtenStrings: [String] = []

    func write(_ string: String) -> Bool {
        writtenStrings.append(string)
        return true
    }
}

private final class InMemorySecretStore: SecretStoring {
    private var values: [String: String] = [:]

    func read(account: String) throws -> String? {
        values[account]
    }

    func write(_ value: String, account: String) throws {
        values[account] = value
    }

    func delete(account: String) throws {
        values[account] = nil
    }
}

private final class FailingWriteSecretStore: SecretStoring {
    func read(account: String) throws -> String? {
        nil
    }

    func write(_ value: String, account: String) throws {
        throw SecretStoreFailure()
    }

    func delete(account: String) throws {}
}

private struct SecretStoreFailure: Error {}

private func matchesResolvedAmount(_ parsed: MoneyParsing.ParsedAmount?, _ expected: Decimal) -> Bool {
    guard let parsed else {
        return false
    }

    if case .resolved(let amount) = parsed.amount {
        return amount == expected
    }

    return false
}

private func matchesAmbiguousAmount(_ parsed: MoneyParsing.ParsedAmount?, rawText: String) -> Bool {
    guard let parsed else {
        return false
    }

    if case .ambiguous(let candidate, let options) = parsed.amount {
        return candidate == rawText && options.count == 2
    }

    return false
}

private func isSkippedBecauseThrottle(_ decision: PanelAutoRefreshDecision) -> Bool {
    if case .skippedBecauseThrottle = decision {
        return true
    }

    return false
}

private func isRefreshDecision(_ decision: HistoryRefreshDecision) -> Bool {
    if case .refresh = decision {
        return true
    }

    return false
}

private final class FailingReadSecretStore: SecretStoring {
    func read(account: String) throws -> String? {
        throw SecretStoreFailure()
    }

    func write(_ value: String, account: String) throws {}

    func delete(account: String) throws {}
}

private struct StubValidationService: APIValidationServicing {
    let results: [EnhancedCredentialKind: String]

    func validateCredential(_ credential: String, for kind: EnhancedCredentialKind) async -> String? {
        results[kind]
    }
}

@MainActor
private final class TestApplicationActivationController: ApplicationActivationControlling {
    private var currentPolicy: NSApplication.ActivationPolicy

    init(initialPolicy: NSApplication.ActivationPolicy) {
        currentPolicy = initialPolicy
    }

    func activationPolicy() -> NSApplication.ActivationPolicy {
        currentPolicy
    }

    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) {
        currentPolicy = activationPolicy
    }
}

private final class MockURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        do {
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try Self.responseData(for: url))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func responseData(for url: URL) throws -> Data {
        let absoluteString = url.absoluteString

        if absoluteString.contains("XML_daily.asp") {
            return """
            <?xml version="1.0" encoding="windows-1251"?>
            <ValCurs Date="10.04.2026" name="Foreign Currency Market">
                <Valute ID="R01235">
                    <CharCode>USD</CharCode>
                    <Nominal>1</Nominal>
                    <Value>92,3700</Value>
                </Valute>
                <Valute ID="R01375">
                    <CharCode>CNY</CharCode>
                    <Nominal>10</Nominal>
                    <Value>127,4000</Value>
                </Valute>
                <Valute ID="R01239">
                    <CharCode>EUR</CharCode>
                    <Nominal>1</Nominal>
                    <Value>100,2100</Value>
                </Valute>
            </ValCurs>
            """.data(using: .utf8)!
        }

        if absoluteString.contains("lastNObservations=5") {
            return """
            {
              "dataSets": [
                {
                  "series": {
                    "0:0:0:0:0": {
                      "observations": {
                        "0": [7.1000, 0, 0, null, null],
                        "1": [7.2400, 0, 0, null, null]
                      }
                    },
                    "0:1:0:0:0": {
                      "observations": {
                        "0": [7.8000, 0, 0, null, null],
                        "1": [7.8900, 0, 0, null, null]
                      }
                    }
                  }
                }
              ],
              "structure": {
                "dimensions": {
                  "series": [
                    {"id": "FREQ", "values": [{"id": "D"}]},
                    {"id": "CURRENCY", "values": [{"id": "USD"}, {"id": "CNY"}]},
                    {"id": "CURRENCY_DENOM", "values": [{"id": "EUR"}]},
                    {"id": "EXR_TYPE", "values": [{"id": "SP00"}]},
                    {"id": "EXR_SUFFIX", "values": [{"id": "A"}]}
                  ],
                  "observation": [
                    {
                      "id": "TIME_PERIOD",
                      "values": [{"id": "2026-04-09"}, {"id": "2026-04-10"}]
                    }
                  ]
                }
              }
            }
            """.data(using: .utf8)!
        }

        throw URLError(.resourceUnavailable)
    }
}

private final class TwelveDataStatusCodeURLProtocol: URLProtocol {
    nonisolated(unsafe) static var lastAPIVersionHeader: String?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        Self.lastAPIVersionHeader = request.value(forHTTPHeaderField: "X-API-Version")
        let response = HTTPURLResponse(
            url: url,
            statusCode: 401,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let payload = """
        {
          "code": 401,
          "status": "error",
          "message": "Invalid symbol"
        }
        """.data(using: .utf8)!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLSessionConfiguration {
    static var mockedSessionConfiguration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 2
        configuration.waitsForConnectivity = false
        return configuration
    }
}
