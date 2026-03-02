# 🏥 HealthCam

**Contactless, real-time health monitoring powered by iPhone camera and AI voice guidance.**

> Built in 6 hours at the [CrimsonCode Hackathon 2026](https://crimsoncode-2026.devpost.com/) at Washington State University.

[![Devpost](https://img.shields.io/badge/Devpost-HealthCam-blue?logo=devpost)](https://devpost.com/software/health-cam)
[![Swift](https://img.shields.io/badge/Swift-92.6%25-orange?logo=swift)](https://github.com/1paramveer/crimson-code-26)
[![Platform](https://img.shields.io/badge/Platform-iOS-lightgrey?logo=apple)](https://github.com/1paramveer/crimson-code-26)

---

## Overview

HealthCam uses an iPhone's front-facing camera to contactlessly measure **pulse rate**, **breathing rate**, and **stress levels** via remote photoplethysmography (rPPG). An AI agent powered by ElevenLabs delivers **live verbal de-escalation guidance** in real time. Every session is automatically analyzed and logged.

No wearables. No extra hardware. No friction.

## Inspiration

Health problems can escalate fast. HealthCam was built to give officers and individuals a real-time edge — physiological data on a subject's stress state — before things go wrong.

## How It Works

1. **Face Detection** — The iPhone camera captures the user's face using AVFoundation and CoreImage.
2. **Biometric Extraction** — The Presage SmartSpectra SDK performs rPPG analysis to extract pulse, breathing rate, and stress indicators from subtle skin-color changes.
3. **AI Voice Agent** — ElevenLabs Conversational AI SDK processes the biometric data and delivers real-time, voice-first de-escalation guidance.
4. **Session Logging** — Every interaction is logged and analyzed for post-session review.

## Tech Stack

| Layer | Technology |
|---|---|
| **Language** | Swift, SwiftUI |
| **IDE** | Xcode |
| **Biometrics Engine** | Presage SmartSpectra SDK (rPPG) |
| **Voice AI** | ElevenLabs Conversational AI SDK |
| **Real-Time Communication** | LiveKit |
| **Frameworks** | AVFoundation, CoreImage, Combine |
| **Serialization** | SwiftProtobuf |

## Project Structure

```
crimson-code-26/
├── SmartSpectra-swift-sdk/   # Presage SmartSpectra SDK integration for rPPG biometric detection
├── core/                     # Core iOS application — SwiftUI views, AI agent, session logic
```

## Challenges

- Getting Presage's headless processing pipeline working without their native UI — the SDK's recording gate only opens when `statusCode == .ok`.
- ElevenLabs session persistence required separating intentional disconnects from post-turn state changes.
- rPPG is extremely sensitive to lighting conditions and face positioning.

## What's Next

- 📹 Body cam integration
- 👥 Multi-subject tracking
- 📊 Department-level analytics dashboard
- 🧠 PTSD early-warning indicators for officers

## Getting Started

### Prerequisites

- macOS with Xcode installed
- iOS device with a front-facing camera (simulator not supported for camera-based rPPG)
- Presage SmartSpectra SDK credentials
- ElevenLabs API key

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/1paramveer/crimson-code-26.git
   cd crimson-code-26
   ```

2. Open the project in Xcode:
   ```bash
   open core/*.xcodeproj
   ```

3. Configure your API keys for SmartSpectra and ElevenLabs in the appropriate configuration files.

4. Build and run on a physical iOS device.

## Developers

- **Paramveer Singh** — [@1paramveer](https://github.com/1paramveer)
- **Aman Verma** - [@aman-verma-wsu](https://github.com/amanverma-wsu)
- **Srishanth** - [@SURAKANTISRISHANTHREDDY](https://github.com/SURAKANTISRISHANTHREDDY)

<p align="center">
  <i>Built with ❤️ at CrimsonCode 2026 — Washington State University</i>
</p>
