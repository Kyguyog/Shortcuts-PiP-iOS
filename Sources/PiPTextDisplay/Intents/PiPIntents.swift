// Intents/PiPIntents.swift
// Exposes three Shortcuts actions:
//   • Start PiP
//   • Set PiP Text
//   • Stop PiP
//
// App Intents run in-process (same address space) so they can reach
// PiPManager.shared directly. On iOS 17+ they are available immediately
// after first launch without any additional registration step.
//
// IMPORTANT: Because App Intents may fire while the app is in the
// background, all methods must be `nonisolated` or use structured
// concurrency correctly. PiPManager.setText() is explicitly nonisolated
// for this reason.

import AppIntents
import AVKit

// MARK: - Start PiP

struct StartPiPIntent: AppIntent {

    static var title: LocalizedStringResource = "Start PiP Display"
    static var description = IntentDescription("Starts the Picture-in-Picture text display.")

    // Make it appear in Shortcuts automatically.
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = PiPManager.shared
        if !manager.isPiPActive {
            manager.startPiP()
        }
        return .result(dialog: "PiP display started.")
    }
}

// MARK: - Set PiP Text

struct SetPiPTextIntent: AppIntent {

    static var title: LocalizedStringResource = "Set PiP Text"
    static var description = IntentDescription(
        "Updates the text shown in the Picture-in-Picture display.",
        categoryName: "PiP Display"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Text", description: "The text to display in the PiP window.")
    var text: String

    nonisolated func perform() async throws -> some IntentResult & ProvidesDialog {
        PiPManager.shared.setText(text)
        return .result(dialog: "PiP text updated.")
    }
}

// MARK: - Stop PiP

struct StopPiPIntent: AppIntent {

    static var title: LocalizedStringResource = "Stop PiP Display"
    static var description = IntentDescription("Stops the Picture-in-Picture display.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        PiPManager.shared.stopPiP()
        return .result(dialog: "PiP display stopped.")
    }
}

// MARK: - Shortcut suggestions
// Surfaces a pre-built shortcut in the Shortcuts app gallery.

struct PiPShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SetPiPTextIntent(),
            phrases: [
                "Set PiP text with \(.applicationName)",
                "Update \(.applicationName) display",
            ],
            shortTitle: "Set PiP Text",
            systemImageName: "pip"
        )
        AppShortcut(
            intent: StartPiPIntent(),
            phrases: ["Start \(.applicationName) PiP"],
            shortTitle: "Start PiP",
            systemImageName: "pip.enter"
        )
        AppShortcut(
            intent: StopPiPIntent(),
            phrases: ["Stop \(.applicationName) PiP"],
            shortTitle: "Stop PiP",
            systemImageName: "pip.exit"
        )
    }
}
