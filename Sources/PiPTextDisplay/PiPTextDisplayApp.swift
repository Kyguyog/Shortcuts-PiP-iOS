// PiPTextDisplayApp.swift
// Entry point. Registers the shared PiPManager singleton early so
// App Intents can reach it even when the app is backgrounded.

import SwiftUI
import AVFoundation

@main
struct PiPTextDisplayApp: App {
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Configure the AVAudioSession so PiP is permitted even without real audio.
        // The "moviePlayback" category keeps the app's process alive in background
        // and satisfies the AVPictureInPicture eligibility check.
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .moviePlayback,
                options: [.mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("⚠️  AVAudioSession setup failed: \(error)")
        }

        // Warm up the singleton before any intent fires.
        _ = PiPManager.shared
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Nothing special needed — PiP keeps the render loop alive.
    }
}
