//
//  ElevenLabsService.swift
//  core
//
//  Created by Paramveer Singh on 2/22/26.
//
//  FIXES applied vs previous version:
//  - VitalsBuffer extracted into its own Swift actor → sampleBuffer is no longer
//    main-actor-isolated, so nonisolated/detached code can mutate it safely.
//  - timestamp() made static → callable from detached Tasks without hopping to MainActor.
//  - ingestReading() uses Task { await buffer.ingest(...) } instead of nonisolated + NSLock.
//

import Foundation
import ElevenLabs
import Combine

// MARK: — Isolated buffer actor
// Keeps all sample storage off the main actor so it can be written from any
// async context (SDK callbacks, background timers) without isolation errors.
actor VitalsBuffer {
    struct Sample {
        let timestamp: Date
        let pulse: Double
        let breathing: Double
    }

    private var samples: [Sample] = []
    private let windowSeconds: TimeInterval = 5.0

    func ingest(pulse: Double, breathing: Double) {
        let now = Date()
        samples.append(Sample(timestamp: now, pulse: pulse, breathing: breathing))
        let cutoff = now.addingTimeInterval(-windowSeconds)
        samples.removeAll { $0.timestamp < cutoff }
    }

    func snapshot() -> [Sample] { samples }

    func clear() { samples.removeAll() }
}

// MARK: — ElevenLabsService
@MainActor
class ElevenLabsService: ObservableObject {
    let agentId = "agent_9101kj219qhee47tjxbf3w6vs5pa"

    @Published var isConnected = false
    @Published var agentSpeaking = false

    private var conversation: Conversation?
    private var cancellables = Set<AnyCancellable>()

    // All sample storage lives in VitalsBuffer actor — never on MainActor
    private let buffer = VitalsBuffer()

    // Worker state (main-actor-isolated, fine)
    private var workerTask: Task<Void, Never>?
    private let workerCadenceSeconds: TimeInterval = 8.0
    private let urgentCadenceSeconds: TimeInterval = 15.0
    private var lastSentStress: String = ""
    private var lastUrgentSentTime: Date = .distantPast

    // Retry state
    private var retryCount = 0
    private let maxRetryDelay: TimeInterval = 30.0

    // MARK: — Start / Stop

    func start() async {
        retryCount = 0
        await connectWithRetry()
    }

    private func connectWithRetry() async {
        while !Task.isCancelled {
            do {
                let conv = try await ElevenLabs.startConversation(
                    agentId: agentId,
                    config: ConversationConfig()
                )
                conversation = conv
                setupObservers()
                isConnected = true
                retryCount = 0
                print("[ElevenLabs \(Self.ts())] Connected successfully")
                return
            } catch {
                retryCount += 1
                let delay = min(Double(retryCount) * 3.0, maxRetryDelay)
                print("[ElevenLabs \(Self.ts())] Connection failed (attempt \(retryCount)): \(error). Retry in \(Int(delay))s")
                isConnected = false
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    func stop() async {
        workerTask?.cancel()
        workerTask = nil
        await conversation?.endConversation()
        conversation = nil
        isConnected = false
        lastSentStress = ""
        await buffer.clear()
        print("[ElevenLabs \(Self.ts())] Stopped and disconnected")
    }

    // MARK: — Timer-driven worker

    /// Starts the periodic analysis worker. Called from ContentView once isConnected fires.
    func startWorker(stressProvider: @escaping @Sendable () -> String) {
        workerTask?.cancel()
        workerTask = Task { [weak self] in
            guard let self else { return }
            print("[ElevenLabs Worker \(Self.ts())] Started")

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.workerCadenceSeconds * 1_000_000_000))
                guard !Task.isCancelled else { break }

                let connected = await self.isConnected
                guard connected else { continue }

                let currentStress = stressProvider()
                let isUrgent = currentStress == "HIGH STRESS"
                let now = Date()

                let shouldSend: Bool
                if isUrgent {
                    let elapsed = now.timeIntervalSince(await self.lastUrgentSentTime)
                    if elapsed >= self.urgentCadenceSeconds {
                        self.lastUrgentSentTime = now
                        shouldSend = true
                    } else {
                        shouldSend = false
                    }
                } else {
                    shouldSend = currentStress != (await self.lastSentStress)
                }

                if shouldSend {
                    await self.sendAnalysis(currentStress: currentStress)
                }
            }
            print("[ElevenLabs Worker \(Self.ts())] Stopped")
        }
    }

    // MARK: — Ingest vitals readings

    /// Ingests a vitals reading into the rolling buffer.
    /// Dispatches into the VitalsBuffer actor — safe to call from any context.
    func ingestReading(pulse: Double, breathing: Double) {
        Task { await buffer.ingest(pulse: pulse, breathing: breathing) }
    }

    // MARK: — Send analysis

    func sendAnalysis(currentStress: String) async {
        guard isConnected else {
            print("[ElevenLabs \(Self.ts())] sendAnalysis skipped — not connected")
            return
        }

        let features = await computeFeatures()
        let prompt   = buildPrompt(currentStress: currentStress, features: features)

        do {
            try await conversation?.sendMessage(prompt)
            lastSentStress = currentStress
            print("[ElevenLabs \(Self.ts())] Sent — stress=\(currentStress) conf=\(String(format: "%.2f", features.confidence)) samples=\(features.sampleCount)")
        } catch {
            print("[ElevenLabs \(Self.ts())] sendMessage failed: \(error)")
            isConnected = false  // triggers worker to pause; retry can reconnect
        }
    }

    // MARK: — Feature computation

    struct VitalsFeatures {
        let avgPulse: Double
        let avgBreathing: Double
        let minPulse: Double
        let maxPulse: Double
        let hrvProxySpread: Double
        let trend: String
        let sampleCount: Int
        let confidence: Double
    }

    private func computeFeatures() async -> VitalsFeatures {
        let samples = await buffer.snapshot()

        guard !samples.isEmpty else {
            return VitalsFeatures(avgPulse: 0, avgBreathing: 0, minPulse: 0, maxPulse: 0,
                                  hrvProxySpread: 0, trend: "insufficient_data",
                                  sampleCount: 0, confidence: 0)
        }

        let pulses  = samples.map { $0.pulse }.filter { $0 > 0 }
        let breaths = samples.map { $0.breathing }.filter { $0 > 0 }

        let avgPulse  = pulses.isEmpty  ? 0.0 : pulses.reduce(0, +)  / Double(pulses.count)
        let avgBreath = breaths.isEmpty ? 0.0 : breaths.reduce(0, +) / Double(breaths.count)
        let minPulse  = pulses.min() ?? 0.0
        let maxPulse  = pulses.max() ?? 0.0

        let trend: String
        if pulses.count >= 4 {
            let half   = pulses.count / 2
            let early  = pulses.prefix(half).reduce(0, +) / Double(half)
            let recent = pulses.suffix(half).reduce(0, +) / Double(half)
            trend = recent > early + 5 ? "rising" : recent < early - 5 ? "falling" : "stable"
        } else {
            trend = "insufficient_data"
        }

        // Confidence: ratio of actual samples vs expected (1/s over 5s window)
        let confidence = min(1.0, Double(samples.count) / 5.0)

        return VitalsFeatures(avgPulse: avgPulse, avgBreathing: avgBreath,
                              minPulse: minPulse, maxPulse: maxPulse,
                              hrvProxySpread: maxPulse - minPulse,
                              trend: trend, sampleCount: samples.count,
                              confidence: confidence)
    }

    // MARK: — Prompt construction

    private func buildPrompt(currentStress: String, features: VitalsFeatures) -> String {
        let classification: String
        if features.confidence < 0.4 || features.sampleCount < 2 {
            classification = "sensor_unreliable"
        } else {
            switch currentStress {
            case "CALM":        classification = "stable"
            case "ELEVATED":    classification = "elevated_stress"
            case "HIGH STRESS": classification = "high_stress"
            default:            classification = "sensor_unreliable"
            }
        }

        let trendNote = (features.trend == "rising" &&
                        (classification == "elevated_stress" || classification == "high_stress"))
                        ? " Pulse is trending upward." : ""

        return """
        [VITALS_UPDATE v1.0]
        timestamp: \(Self.ts())
        window_seconds: 5

        vitals:
          pulse_bpm: avg=\(Int(features.avgPulse)) min=\(Int(features.minPulse)) max=\(Int(features.maxPulse)) trend=\(features.trend)
          breathing_rpm: avg=\(Int(features.avgBreathing))
          hrv_proxy_spread: \(Int(features.hrvProxySpread)) bpm
          sample_count: \(features.sampleCount)
          data_confidence: \(String(format: "%.2f", features.confidence))

        assessment:
          classification: \(classification)

        RULES: Max 2 sentences. Never diagnose. Don't repeat numbers.
        sensor_unreliable → "Sensor weak — reposition camera."
        stable → brief calm confirmation.
        elevated_stress → simple de-escalation tip.
        high_stress → urgent de-escalation + consider medical.\(trendNote)
        """
    }

    // MARK: — Combine observers

    private func setupObservers() {
        guard let conversation = conversation else { return }
        cancellables.removeAll()

        conversation.$state
            .map { $0.isActive }
            .receive(on: DispatchQueue.main)
            .assign(to: &$isConnected)

        conversation.$agentState
            .map { $0 == .speaking }
            .receive(on: DispatchQueue.main)
            .assign(to: &$agentSpeaking)
    }

    // MARK: — Utility

    /// Static so it can safely be called from any Task/actor context.
    static func ts() -> String {
        String(format: "%.3f", Date().timeIntervalSince1970)
    }
}
