//
//  ElevenLabsService.swift
//  core
//
//  Created by Paramveer Singh on 2/22/26.
//

// let apiKey = "ca1cc8020dc3fa8272c2a58a4ae6199814171663a884ff5a56b9b057f93f932e"
// let voiceId = "sB7vwSCyX0tQmU24cW2C"  // get from ElevenLabs voice library

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
    
    // Call this when stress level changes
    func sendStressUpdate(pulse: Int, breathing: Int, level: String) async {
        let message = "Subject vitals — Pulse: \(pulse) BPM, Breathing: \(breathing) BPM. Stress level: \(level). Advise officer."
        try? await conversation?.sendMessage(message)
    }
    
    func stop() async {
        await conversation?.endConversation()
        isConnected = false
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
