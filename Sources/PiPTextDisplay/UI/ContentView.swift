// UI/ContentView.swift
// Minimal SwiftUI interface.
// The SampleBufferLayerView must be in the hierarchy before PiP starts —
// iOS validates that the source layer has an on-screen superlayer.

import SwiftUI
import AVFoundation

struct ContentView: View {

    @StateObject private var pip = PiPManager.shared
    @State private var draftText = ""
    @State private var countdownTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {

                // ── Preview of what PiP shows ──────────────────────────
                ZStack {
                    SampleBufferLayerView(layer: pip.sampleBufferDisplayLayer)
                        .aspectRatio(16/9, contentMode: .fit)
                        .cornerRadius(12)
                        .shadow(color: .white.opacity(0.1), radius: 10)
                        .onAppear {
                            pip.setupPiP()
                        }

                    if !pip.isPiPActive {
                        Text("Preview")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.4))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(8)
                    }
                }
                .padding(.horizontal)

                // ── Current text badge ─────────────────────────────────
                Text(pip.displayText)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .animation(.easeInOut(duration: 0.2), value: pip.displayText)

                // ── Custom text input ──────────────────────────────────
                HStack {
                    TextField("Enter text…", text: $draftText)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)

                    Button("Set") {
                        guard !draftText.isEmpty else { return }
                        pip.setText(draftText)
                    }
                    .buttonStyle(ActionButtonStyle(color: .blue))
                }
                .padding(.horizontal)

                // ── PiP controls ───────────────────────────────────────
                HStack(spacing: 16) {
                    Button(pip.isPiPActive ? "PiP Active ✓" : "Start PiP") {
                        pip.startPiP()
                    }
                    .buttonStyle(ActionButtonStyle(color: pip.isPiPActive ? .green : .indigo))
                    .disabled(pip.isPiPActive)

                    Button("Stop PiP") {
                        pip.stopPiP()
                    }
                    .buttonStyle(ActionButtonStyle(color: .red))
                    .disabled(!pip.isPiPActive)
                }

                Divider().background(Color.white.opacity(0.2)).padding(.horizontal)

                // ── Demo countdown ─────────────────────────────────────
                Text("Demo Countdown")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))

                Button("▶  Run Countdown Demo") {
                    runCountdownDemo()
                }
                .buttonStyle(ActionButtonStyle(color: .orange))
                .disabled(countdownTask != nil)

                if countdownTask != nil {
                    Button("✕  Cancel") { cancelDemo() }
                        .buttonStyle(ActionButtonStyle(color: .gray))
                }

                Spacer()

                // ── Pip-possible hint ──────────────────────────────────
                if !pip.isPiPPossible {
                    Label("PiP not available on this device/simulator", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.yellow.opacity(0.7))
                        .padding(.bottom, 8)
                }
            }
            .padding(.top, 32)
        }
    }

    // MARK: - Demo

    private func runCountdownDemo() {
        guard pip.isPiPActive || true else { return } // allow demo without PiP too
        cancelDemo()
        countdownTask = Task {
            for n in stride(from: 10, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                pip.setText("Fire in \(n)")
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled else { return }
            pip.setText("🔥 FIRE NOW")
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run { countdownTask = nil }
        }
    }

    private func cancelDemo() {
        countdownTask?.cancel()
        countdownTask = nil
    }
}

// MARK: - Button style helper

struct ActionButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(color.opacity(configuration.isPressed ? 0.6 : 1))
            .cornerRadius(10)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    ContentView()
}
