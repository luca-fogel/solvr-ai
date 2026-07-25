# solvr.ai 🧮

A native iOS app that solves math problems from a photo. Point your camera at a problem,
and solvr.ai reads it, works it out, and teaches you how — powered by Claude.

## What it does

1. **Scan** — capture a math problem with the camera (with a crop/zone overlay for accuracy)
2. **Detect & OCR** — detects the problem region and extracts the text
3. **Solve** — sends it to Claude, which returns a full worked solution
4. **Learn** — view it as step-by-step working, key formulas, a short lesson, related videos,
   or keep asking follow-up questions in a chat

## Features

- 📷 Camera scanner with live problem detection and crop overlay
- 🔤 On-device OCR before sending to the model
- 🧠 Claude-powered step-by-step solutions
- 📚 Multiple result views: Steps · Formulas · Lesson · Videos · Chat
- 🕘 History of past problems
- 🔐 API key stored securely in the Keychain
- 🎨 Themed SwiftUI interface (MVVM architecture)

## Architecture

Built with **SwiftUI** using an **MVVM** pattern:

| Layer | Contents |
|-------|----------|
| `Models/` | `Problem`, `ChatMessage`, `ClaudeResponse`, `StepItem`, `FormulaItem`, `LessonContent` … |
| `Services/` | `ClaudeAPIManager`, `CameraManager`, `OCRService`, `KeychainManager`, `NetworkMonitor` |
| `ViewModels/` | `HomeViewModel`, `ScannerViewModel`, `ResultsViewModel`, `ChatViewModel` |
| `Views/` | `Home`, `Scanner`, `Results`, `History`, `Settings`, `Launch` + reusable components |
| `Utilities/` | `Theme`, `HTMLBuilder`, `Extensions`, helpers |

## Getting started

1. Open `solvr.ai.xcodeproj` in Xcode
2. Add your Claude API key in the app's **Settings** (stored in the Keychain)
3. Build & run on a device with a camera (iOS)
