import AppIntents
import AVFoundation

// MARK: - Start PiP

struct StartPiPIntent: AppIntent {
    static let title: LocalizedStringResource = "Start PiP Display"
    static let description = IntentDescription("Starts the Picture-in-Picture text display overlay.")

    // Allow running without the app in the foreground (iOS 16+).
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        // Post a Darwin notification so the main app process starts PiP,
        // then also attempt a direct call in case we are in-process.
        DarwinNotifier.post(.startPiP)
        PiPManager.shared.startPiP()
        return .result()
    }
}

// MARK: - Set PiP Text

struct SetPiPTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Set PiP Text"
    static let description = IntentDescription(
        "Updates the text shown in the Picture-in-Picture overlay.",
        categoryName: "PiP Display"
    )
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Text", description: "The text to display in the PiP window.")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // Write to shared storage first so the main process can read it.
        UserDefaults(suiteName: AppGroup.id)?.set(text, forKey: AppGroup.textKey)
        DarwinNotifier.post(.textDidChange)

        // Direct call works when the intent runs in the main app process.
        PiPManager.shared.setText(text)

        return .result(value: text)
    }
}

// MARK: - Stop PiP

struct StopPiPIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop PiP Display"
    static let description = IntentDescription("Stops the Picture-in-Picture text display overlay.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        DarwinNotifier.post(.stopPiP)
        PiPManager.shared.stopPiP()
        return .result()
    }
}

// MARK: - Countdown Intent (convenience)

/// Runs a countdown in Shortcuts without needing a Repeat block.
/// "Fire in N" → "Fire in N-1" → … → "🔥 FIRE NOW"
struct StartCountdownIntent: AppIntent {
    static let title: LocalizedStringResource = "PiP Countdown"
    static let description = IntentDescription(
        "Runs a live countdown in PiP, then shows a final message.",
        categoryName: "PiP Display"
    )
    static let openAppWhenRun: Bool = false

    @Parameter(title: "From", description: "Starting countdown value.", default: 10)
    var from: Int

    @Parameter(title: "Final Message", description: "Text to show when countdown reaches zero.", default: "🔥 FIRE NOW")
    var finalMessage: String

    @Parameter(title: "Prefix", description: "Label before the number.", default: "Fire in")
    var prefix: String

    @MainActor
    func perform() async throws -> some IntentResult {
        PiPManager.shared.startPiP()

        for i in stride(from: from, through: 1, by: -1) {
            PiPManager.shared.setText("\(prefix) \(i)")
            // Give the frame renderer a tick to update, then wait 1 second.
            try await Task.sleep(for: .seconds(1))
        }

        PiPManager.shared.setText(finalMessage)
        return .result()
    }
}
