# Currency Tracker

Currency Tracker is a macOS menu bar app for exchange rates, quick conversion, and system-wide selected-text currency conversion. It is built for people who check a small set of rates repeatedly and want the workflow to stay close to the menu bar.

<p>
  <a href="https://github.com/Agumuzi/Currency_Tracker/releases/latest"><strong>Download latest release</strong></a>
  ·
  <a href="https://agumuzi.github.io/Currency_Tracker/">Product page</a>
  ·
  <a href="https://github.com/Agumuzi/Currency_Tracker/releases">Release notes</a>
</p>

<p>
  <img src="assets/screenshots/menu-panel-history.png" width="420" alt="Currency Tracker menu bar panel with a selected currency pair, trend chart, and compact rate cards.">
</p>

## What It Does

- Keeps selected exchange-rate pairs one click away in the macOS menu bar.
- Shows compact cards with latest rates, source, refresh time, and positive or negative movement badges.
- Expands any card into a history chart or a two-way converter.
- Lets you add, remove, reorder, and search currency pairs from the ISO currency catalog supported by your configured data sources.
- Converts selected text from other apps through macOS Services or a global shortcut.
- Supports English, Russian, and Simplified Chinese.
- Stores preferences and API credentials locally on your Mac without using the system Keychain.

## Screenshots

### Menu Bar Workflow

| Rate list | History chart | Inline conversion |
| --- | --- | --- |
| <img src="assets/screenshots/menu-panel.png" alt="Currency Tracker menu bar panel showing multiple exchange-rate cards."> | <img src="assets/screenshots/menu-panel-history.png" alt="Expanded rate card with a one-month history chart."> | <img src="assets/screenshots/menu-panel-conversion.png" alt="Expanded rate card with two-way currency conversion."> |

### Settings And Configuration

| Welcome | Rates | Data sources |
| --- | --- | --- |
| <img src="assets/screenshots/settings-window.png" alt="Currency Tracker settings welcome screen with setup steps."> | <img src="assets/screenshots/settings-rates.png" alt="Settings screen for managing shown exchange-rate pairs."> | <img src="assets/screenshots/data-sources-window.png" alt="Settings screen for API provider credentials and custom API templates."> |

| Profiles | Alerts | Updates |
| --- | --- | --- |
| <img src="assets/screenshots/settings-profiles.png" alt="Settings screen for saving and switching profiles."> | <img src="assets/screenshots/settings-alerts.png" alt="Settings screen for exchange-rate threshold alerts."> | <img src="assets/screenshots/settings-updates.png" alt="Settings screen for checking updates and enabling automatic checks."> |

## Main Features

### Menu Bar Rates

Choose the pairs you care about and keep them in a compact menu bar panel. The panel supports scrolling when the list grows, a pinned always-on-top mode, manual refresh, and display modes for the menu bar item itself.

### History And Conversion

Each card can expand into a recent trend chart or a converter without leaving the panel. Chart ranges include 7 days, 1 month, 3 months, 6 months, and 1 year when historical data is available.

### Pair Management

The settings window includes a sidebar and dedicated pages for general behavior, rate pairs, profiles, alerts, refresh policy, data sources, permissions, updates, diagnostics, and system launch behavior.

### Data Sources

Currency Tracker works with public fallback sources by default. You can add credentials for mainstream providers when you need better coverage or reliability:

- Twelve Data
- ExchangeRate-API
- Open Exchange Rates
- Fixer
- Currencylayer
- Custom JSON API templates with `{base}`, `{quote}`, and `{key}` placeholders, secure entry, enable/edit states, and a built-in connection test

### Profiles And Alerts

Save different pair lists and refresh settings as profiles, then switch between them for different workflows. Rate alerts can watch selected pairs and request notification permission when a threshold is triggered.

### Updates

The app can check GitHub Releases from Settings. Update packages are downloaded, verified with SHA256 checksums, prepared, installed, relaunched, and cleaned up inside the app after user confirmation.

## Current Release

Version `1.4.0` includes:

- Custom API templates now use a clearer save/edit flow, hidden API key fields, enable/disable status, and a connection test.
- Custom API keys are kept in the app's local credential file rather than in UserDefaults.
- In-app updates now require and verify release SHA256 checksum files before extraction.
- Update preparation shows staged progress for download, verification, extraction, and app validation.
- The global shortcut copy fallback restores the previous clipboard after reading selected text.
- Release automation now builds reproducible unsigned archives, generates checksum assets, and runs a UI smoke test in CI.

## Installation

Download `Currency-Tracker-1.4.0.zip` from the latest GitHub release, unzip it, and move `Currency Tracker.app` to your Applications folder.

The app is distributed through GitHub Releases and is not notarized through Apple. On first launch, macOS may block it. Open:

`System Settings` -> `Privacy & Security` -> `Open Anyway`

After you approve it once, future launches should work normally. Because the app is still unsigned and not notarized, macOS may still ask for approval when replacing the application during an in-app update.

## Requirements

- macOS 14.0 or later
- Internet access for live exchange-rate refreshes

## Privacy

Currency Tracker is local-first. Preferences, selected pairs, refresh behavior, profiles, alerts, and API credentials are stored on your Mac. Provider keys are kept in the app's local Application Support data, not in the macOS Keychain. The app does not upload local files, clipboard contents, or device data to any backend service owned by this project.

External exchange-rate providers only receive the exchange-rate requests needed for the data sources you enable.

## Links

- [Product page](https://agumuzi.github.io/Currency_Tracker/)
- [Repository](https://github.com/Agumuzi/Currency_Tracker)
- [Releases](https://github.com/Agumuzi/Currency_Tracker/releases)
