# PiPTextDisplay — Developer Reference

## Overview

This project implements a **hacky-but-working** Picture-in-Picture system that
displays dynamically generated text frames controlled by iOS Shortcuts.

No video files are used. Every PiP frame is synthesised at runtime from a
CoreGraphics draw call, wrapped in a `CMSampleBuffer`, and pushed into an
`AVSampleBufferDisplayLayer`.

---

## Project Structure

```
PiPTextDisplay/
├── Sources/PiPTextDisplay/
│   ├── PiPTextDisplayApp.swift       # @main, AVAudioSession config
│   ├── UI/
│   │   └── ContentView.swift         # SwiftUI UI + demo countdown
│   ├── PiP/
│   │   ├── PiPManager.swift          # Central controller (singleton)
│   │   └── SampleBufferLayerView.swift  # UIViewRepresentable host
│   ├── Rendering/
│   │   └── TextFrameRenderer.swift   # CGContext → CVPixelBuffer → CMSampleBuffer
│   └── Intents/
│       └── PiPIntents.swift          # App Intents (Shortcuts)
└── Resources/
    └── Info.plist
```

---

## How the Frame Pipeline Works

```
setText("Fire in 3")
        │
        ▼
  _pendingText (os_unfair_lock protected)
        │
        ▼  (DispatchSourceTimer @ 30 fps)
  TextFrameRenderer.makeSampleBuffer(text:)
        │
        ├─ CVPixelBufferPool  ──► CVPixelBuffer (1280×720, BGRA)
        │
        ├─ CGContext (backed by pixel buffer memory — zero-copy)
        │       ├─ Fill background
        │       └─ NSAttributedString.draw(in:)
        │
        ├─ CMSampleTimingInfo (synthetic monotonic PTS)
        │
        └─ CMSampleBuffer
                │
                ▼
  AVSampleBufferDisplayLayer.enqueue(_:)
                │
                ▼
  AVPictureInPictureController (ContentSource = sampleBufferDisplayLayer)
                │
                ▼
         🪟 PiP Window
```

### Why CVPixelBufferPool?

Allocating a new `CVPixelBuffer` every frame would hit the allocator 30 times/sec.
The pool keeps 3 pre-allocated buffers in rotation — the layer borrows one,
we write the next frame into another, and the third is the spare.

---

## iOS Limitations & Workarounds

### 1. Background Frame-Rate Throttling

When the app enters the background **without** PiP being active, iOS suspends
the app after ~30 s. With PiP active, the process stays alive but the
`DispatchSourceTimer` may be coalesced by the OS to **~1 fps** under battery
pressure.

**Impact:** Text updates from Shortcuts still reach `_pendingText` instantly
(App Intents run in-process), but the frame might not render for up to ~1 s.
For the countdown use case this is imperceptible.

**Workaround if you need guaranteed real-time rendering:**
- Keep a silent `AVPlayer` playing a 1-hour silence file in the background
  alongside PiP. This prevents CPU coalescing. Overkill for most use cases.

### 2. PiP Eligibility

`AVPictureInPictureController.isPictureInPicturePossible` returns `false` on:
- Simulator (PiP is not supported — test on device)
- iPad with Stage Manager + split-screen in some configurations
- Non-Pro iPhones running iOS < 14 (irrelevant here since we target 17+)

### 3. AVAudioSession Requirement

PiP with `AVSampleBufferDisplayLayer` **requires** the app to have an active
`.playback` audio session. We configure this in `AppDelegate.init`. Without it,
`startPictureInPicture()` silently fails.

You do NOT need to actually play audio — setting the category is sufficient.

### 4. App Intent Background Execution

App Intents are launched in the same process as the host app. If the host app
has been jettisoned (e.g. after long suspension), iOS re-launches it in the
background specifically to run the intent. The app's full init path runs, so
`PiPManager.shared` is always available.

However, you **cannot** call `pip.startPiP()` from an intent that fires when
the app is not foregrounded — `AVPictureInPictureController` requires the app's
window hierarchy to exist. `setText()` and `stopPiP()` work fine from intents
in all states.

### 5. The "Source Layer Must Be On Screen" Rule

PiP will fail silently if `AVSampleBufferDisplayLayer` is not attached to a
view that is part of the live UIWindow hierarchy at the moment
`startPictureInPicture()` is called. `SampleBufferLayerView` handles this by
being placed in `ContentView`. Once PiP starts the layer can be hidden or
the app backgrounded.

---

## Xcode Project Setup Checklist

1. **Create new iOS App project** (SwiftUI, minimum iOS 17).
2. Add all `.swift` files from `Sources/PiPTextDisplay/` in their respective groups.
3. **Info.plist** → add `UIBackgroundModes` → `audio` (Background Audio).
4. **Signing & Capabilities** tab → add:
   - *Background Modes* → ✓ Audio, AirPlay, and Picture in Picture
   - *App Intents* (automatically handled for sideloading)
5. Set **Bundle Identifier** to match `Info.plist`.
6. Run on a **physical iPhone** — PiP does not work in Simulator.

---

## Shortcuts Integration

### Manual Shortcut: Fire Countdown

```
┌─────────────────────────────────────┐
│  Shortcut: Fire Countdown           │
├─────────────────────────────────────┤
│  Start PiP Display                  │  ← StartPiPIntent
│                                     │
│  Repeat 10 times                    │
│  │  Set PiP Text                    │  ← SetPiPTextIntent
│  │    Text: "Fire in (Repeat Index)"│
│  │  Wait 1 second                   │
│  End Repeat                         │
│                                     │
│  Set PiP Text "🔥 FIRE NOW"         │  ← SetPiPTextIntent
│  Wait 3 seconds                     │
│  Stop PiP Display                   │  ← StopPiPIntent
└─────────────────────────────────────┘
```

*Repeat Index* is a Shortcuts magic variable that starts at 1 and counts up.
Use **10 - Repeat Index + 1** or insert a Calculate step to get a countdown.

Alternatively, use a variable:

```
Set Variable (n) to 10
Repeat 10 times
  Set PiP Text "Fire in (n)"
  Set Variable (n) to (n - 1)
  Wait 1 second
End Repeat
Set PiP Text "🔥 FIRE NOW"
```

### Automation Trigger

In Shortcuts → Automation, you can trigger `Set PiP Text` on:
- Time of day
- NFC tag tap
- Siri voice command
- Focus mode change

---

## Customising the Renderer

Edit `TextFrameRenderer.Config` to adjust appearance:

```swift
var config = TextFrameRenderer.Config()
config.width           = 1920   // Full HD
config.height          = 1080
config.fps             = 60
config.backgroundColor = UIColor(red: 0.05, green: 0, blue: 0.1, alpha: 1).cgColor
config.textColor       = .systemYellow
config.font            = UIFont(name: "Impact", size: 120)!
```

To render **multi-line text with emoji support** (already works), just pass
a string with `\n` — `NSAttributedString.draw(in:)` handles it natively.

---

## Fallback Strategies

If for any reason the `AVSampleBufferDisplayLayer` approach is blocked:

### Option A: Looping Pixel Buffer with Metadata Overlay
Pre-render a 10-second solid-colour H.264 video and loop it with `AVPlayerLooper`.
Push text via `AVPlayerItemVideoOutput` + Metal overlay. More complex, but
bypasses the sample buffer layer approach entirely.

### Option B: Live Activities (Lock Screen / Dynamic Island)
For iOS 16.1+, use `ActivityKit` + a WidgetKit extension to push countdown text
to the Dynamic Island and Lock Screen. Not a PiP window, but survives all
background restrictions and doesn't require screen-on.

### Option C: Remote Notification Silent Push
Use a background push (`content-available: 1`) to wake the app in the background,
update `displayText`, and let the next render tick push the frame. Requires a
push server but works even when the app is suspended.

---

## Known Issues

| Issue | Cause | Fix |
|---|---|---|
| PiP button greyed out | Simulator | Use physical device |
| PiP immediately closes | AVAudioSession not active | Check AppDelegate setup |
| Frames stop updating after 60 s | System killed render timer | Add a background `UITaskIdentifier` or use the silent-player trick |
| "Failed to start PiP" | Source layer not in hierarchy | Ensure `SampleBufferLayerView` is on screen before calling `startPiP()` |

---

*Built against iOS 17 SDK. Tested on iPhone 15 Pro (iOS 18.1).*
