//
//  ElevenLabsService.swift
//  core
//
//  Created by Paramveer Singh on 2/22/26.
//

// let apiKey = "ca1cc8020dc3fa8272c2a58a4ae6199814171663a884ff5a56b9b057f93f932e"
// let voiceId = "sB7vwSCyX0tQmU24cW2C"  // get from ElevenLabs voice library
// agentId = agent_9101kj219qhee47tjxbf3w6vs5pa

import Foundation
import ElevenLabs
import Combine

@MainActor
class ElevenLabsService: ObservableObject {
    let agentId = "agent_9101kj219qhee47tjxbf3w6vs5pa"

    @Published var isConnected = false
    @Published var agentSpeaking = false

    private var conversation: Conversation?
    private var cancellables = Set<AnyCancellable>()

    // Rolling data store — keeps last 10 readings
    private var pulseHistory: [Double] = []
    private var breathingHistory: [Double] = []
    private var lastSentTime: Date = .distantPast

    func start() async {
        do {
            conversation = try await ElevenLabs.startConversation(
                agentId: agentId,
                config: ConversationConfig()
            )
            setupObservers()
            isConnected = true
        } catch {
            print("ElevenLabs error: \(error)")
        }
    }

    func stop() async {
        await conversation?.endConversation()
        conversation = nil
        isConnected = false
        pulseHistory.removeAll()
        breathingHistory.removeAll()
    }

    // Call this every time Presage gives a new reading
    func ingestReading(pulse: Double, breathing: Double) {
        if pulse > 0 { pulseHistory.append(pulse) }
        if breathing > 0 { breathingHistory.append(breathing) }

        // Keep only last 10 readings
        if pulseHistory.count > 10 { pulseHistory.removeFirst() }
        if breathingHistory.count > 10 { breathingHistory.removeFirst() }
    }

    // Call this when stress level changes — sends full structured prompt
    func sendAnalysis(currentStress: String) async {
        guard isConnected else { return }

        // Throttle — don't send more than once every 8 seconds
        guard Date().timeIntervalSince(lastSentTime) > 8 else { return }
        lastSentTime = Date()

        let prompt = buildPrompt(currentStress: currentStress)
        try? await conversation?.sendMessage(prompt)
    }

    private func buildPrompt(currentStress: String) -> String {
        let avgPulse = pulseHistory.isEmpty ? 0 : pulseHistory.reduce(0, +) / Double(pulseHistory.count)
        let avgBreathing = breathingHistory.isEmpty ? 0 : breathingHistory.reduce(0, +) / Double(breathingHistory.count)
        let minPulse = pulseHistory.min() ?? 0
        let maxPulse = pulseHistory.max() ?? 0
        let pulseVariability = maxPulse - minPulse

        // Trend: is pulse going up or down?
        let trend: String
        if pulseHistory.count >= 3 {
            let recent = pulseHistory.suffix(3).reduce(0, +) / 3
            let earlier = pulseHistory.prefix(3).reduce(0, +) / 3
            if recent > earlier + 5 { trend = "rising" }
            else if recent < earlier - 5 { trend = "falling" }
            else { trend = "stable" }
        } else {
            trend = "insufficient data"
        }

        return """
        You are a real-time law enforcement assistance AI. A police officer needs your immediate verbal guidance based on the following biometric data from their subject.

        CURRENT BIOMETRICS:
        - Pulse Rate: \(Int(avgPulse)) BPM (range: \(Int(minPulse))–\(Int(maxPulse)) BPM)
        - Breathing Rate: \(Int(avgBreathing)) breaths/min
        - Heart Rate Variability: \(Int(pulseVariability)) BPM spread
        - Pulse Trend: \(trend)
        - Overall Stress Classification: \(currentStress)

        CONTEXT: This is an active law enforcement interaction. The subject is being monitored in real time.

        Based on this data, provide brief spoken guidance to the officer in 2-3 sentences. Be direct, calm, and tactical. Focus on de-escalation technique if stress is elevated. Do not repeat the numbers back — just give actionable advice.
        """
    }

    private func setupObservers() {
        conversation?.$state
            .map { $0.isActive }
            .assign(to: &$isConnected)

        conversation?.$agentState
            .map { $0 == .speaking }
            .assign(to: &$agentSpeaking)
    }
}
