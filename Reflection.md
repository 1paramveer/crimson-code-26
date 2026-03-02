# Reflection: Crimson Code 2026 (Health Cam)

## Activity description
Crimson Code 2026 was a hackathon where the expectation was to build a functional prototype quickly and present a working demo. Our team built **Health Cam**, a contactless iPhone app that uses the camera to estimate **pulse, breathing rate, and stress** via rPPG, then provides **real-time verbal de-escalation guidance** through an ElevenLabs conversational AI agent. Each session is logged for analysis. We built the core prototype in 6 hours during the hackathon.

## Technical decisions
We chose **Swift/SwiftUI** to keep camera access, UI, and performance integrated for a stable demo. For biometric estimation, we integrated **Presage SmartSpectra** rather than implementing rPPG from scratch, so we could prioritize a complete end-to-end pipeline: measurement → guidance → logging. We also made the experience voice-first using **ElevenLabs**, because in stressful situations the user may not be able to read instructions easily, and audio guidance supports real-time intervention.

During development we made MVP tradeoffs: we focused on reliability of the detection loop and conversational flow rather than extra features. A key debugging decision was to read SDK internals/source behavior because the Presage recording gate only opened when `statusCode == .ok`, which was blocking headless processing. We also handled ElevenLabs persistence issues by separating intentional disconnects from post-turn state changes.

## Contributions
This was a team project. My contributions were primarily technical integration and debugging: stabilizing the biometric processing flow, troubleshooting headless pipeline readiness/state gating, and helping integrate and validate the live conversational voice loop for the demo. I also supported final testing and demo preparation.

## Quality assessment
I think my participation was strong because I helped turn two powerful components (contactless detection + voice agent) into a working end-to-end prototype that could be demonstrated. If I could redo the event, I would set up configuration/keys earlier, add quick calibration checks for lighting/face alignment (rPPG sensitivity), and write documentation during implementation instead of post-hackathon. Overall, the event improved my ability to make practical engineering decisions under time constraints while building a system that must be reliable and careful with sensitive physiological data.
