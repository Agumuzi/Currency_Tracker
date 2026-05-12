# Changelog

## 1.6.2 - 2026-05-13

- Fixes the menu bar panel placement so it stays fully below the macOS menu bar instead of being clipped at the top of the screen.
- Clamps the transient panel to the clicked status item's screen, including smaller or secondary displays.

## 1.6.1 - 2026-05-06

- Replaces the dynamic SwiftUI menu bar scene with an AppKit status item to avoid launch hangs when the menu bar icon lifecycle changes.
- Keeps the 1.6 menu bar visibility, background activity, update permission review, and ad-hoc packaging improvements.

## 1.6 - 2026-05-06

- Adds Settings controls for showing or hiding the menu bar icon and for pausing background activity.
- Pauses scheduled refresh, automatic update checks, and global shortcut listening when background activity is disabled, while keeping manual refresh available.
- Detects when an in-app update may require reviewing previously granted system permissions and opens the Permissions settings page after relaunch.
- Signs the full app bundle ad-hoc before packaging so release zips have sealed resources and bound bundle metadata.

## 1.5.7 - 2026-05-06

- Fixes app lifecycle handling so clicking the Dock icon reopens the settings window when the app is running but no menu bar window is visible.
- Keeps the app responsive when macOS sends a reopen event, reducing the perceived "stuck" state if the menu bar item fails to appear.

## 1.5.6 - 2026-05-05

- Fixes the GitHub release build quitting immediately after launch on macOS.
- Keeps the menu bar app resident when macOS sends status item visibility changes, while preserving explicit Quit and update-relaunch flows.
- Repackages the macOS app for GitHub distribution as a clean, non-notarized release that users can manually approve in System Settings.

## 1.5.5 - 2026-05-04

- Fixes global text-conversion shortcut reliability after Accessibility permission changes.
- Adds an Accessibility-backed global key monitor fallback alongside the Carbon hot key registration.
- Improves selected-text copy fallback timing and restores the previous clipboard contents after reading.
- Allows converter inputs to evaluate basic calculations such as `100+20`, `100 - 25=`, `12*3`, `10/4`, and `(2+3)*4`.
- Updates the in-app update checker to use the public `Agumuzi/Currency-Tracker` GitHub repository.
