import SwiftUI
import AVKit

struct ContentView: View {
    @StateObject private var pipManager = PiPManager.shared
    @State private var inputText: String = "Hello PiP"

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Live preview of what's in PiP
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black)
                        .aspectRatio(16 / 9, contentMode: .fit)

                    Text(pipManager.currentText)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                .padding(.horizontal)
                .overlay(alignment: .topTrailing) {
                    if pipManager.isPiPActive {
                        Label("PiP Live", systemImage: "pip.fill")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.red.opacity(0.85))
                            .clipShape(Capsule())
                            .padding(24)
                    }
                }

                // Text input
                HStack {
                    TextField("Enter text…", text: $inputText)
                        .textFieldStyle(.roundedBorder)

                    Button("Set") {
                        pipManager.setText(inputText)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)

                // Quick-fire buttons
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(["Fire in 10", "Fire in 5", "Fire in 3", "🔥 FIRE NOW", "Standby"], id: \.self) { preset in
                            Button(preset) {
                                pipManager.setText(preset)
                                inputText = preset
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.horizontal)
                }

                Divider()

                // PiP controls
                HStack(spacing: 16) {
                    Button {
                        pipManager.startPiP()
                    } label: {
                        Label("Start PiP", systemImage: "pip.enter")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(pipManager.isPiPActive)

                    Button {
                        pipManager.stopPiP()
                    } label: {
                        Label("Stop PiP", systemImage: "pip.exit")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(!pipManager.isPiPActive)
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("PiP Text Display")
        }
        // Hidden AVPlayerLayer required for PiP to attach to the window scene
        .background(PlayerLayerView(manager: pipManager))
    }
}

/// Invisible UIViewRepresentable that hosts the AVSampleBufferDisplayLayer
/// so AVPictureInPictureController has a valid parent layer in the view hierarchy.
struct PlayerLayerView: UIViewRepresentable {
    let manager: PiPManager

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isHidden = false
        view.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        view.layer.addSublayer(manager.displayLayer)
        manager.attachedView = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

#Preview {
    ContentView()
}
