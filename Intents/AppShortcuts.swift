import AppIntents

/// Registers pre-built Shortcut phrases so Siri and the Shortcuts app
/// surface them automatically without the user building them manually.
struct PiPAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartPiPIntent(),
            phrases: [
                "Start \(.applicationName)",
                "Open \(.applicationName) overlay"
            ],
            shortTitle: "Start PiP",
            systemImageName: "pip.enter"
        )
        AppShortcut(
            intent: StopPiPIntent(),
            phrases: [
                "Stop \(.applicationName)",
                "Close \(.applicationName) overlay"
            ],
            shortTitle: "Stop PiP",
            systemImageName: "pip.exit"
        )
        AppShortcut(
            intent: StartCountdownIntent(),
            phrases: [
                "Start \(.applicationName) countdown",
                "Fire countdown in \(.applicationName)"
            ],
            shortTitle: "PiP Countdown",
            systemImageName: "timer"
        )
    }
}
