#if os(macOS)
import AppKit
import KeyboardShortcuts

// MARK: - Shortcut names

extension KeyboardShortcuts.Name {
    /// Start or pause the Clock. Default ⌥0.
    static let toggleClock = Self("toggleClock", default: .init(.zero, modifiers: [.option]))
}

// MARK: - Global hotkey

/// The single system-wide keyboard shortcut for the Clock (#11). LSAT
/// Tracker has one undifferentiated study stream, so unlike Russian
/// Tracker's Phase 4 there are no Study Type switch hotkeys to port.
///
/// The shortcut is recordable from Settings → Keyboard Shortcuts and is
/// stored by the `KeyboardShortcuts` package in `UserDefaults`. Feedback is
/// the Menu Bar Item only: no sound, HUD, or notification, per the map's
/// design principles.
///
/// The App installs the handler once at launch:
///
///     Hotkeys.install(timer: timer)
enum Hotkeys {
    /// Guards against double registration if `install` is called more than
    /// once (e.g. from more than one launch path while #24 restructures
    /// `LSAT_TrackerApp.swift`).
    private static var isInstalled = false

    /// Registers the key handler against `timer`. Safe to call more than
    /// once — only the first call installs the handler.
    static func install(timer: TimerManager) {
        guard !isInstalled else { return }
        isInstalled = true

        // Fire on key-up so a held ⌥0 does not toggle repeatedly.
        KeyboardShortcuts.onKeyUp(for: .toggleClock) { [weak timer] in
            timer?.toggle()
        }
    }
}
#endif
