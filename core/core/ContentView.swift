//
//  ContentView.swift
//  core
//
//  Created by Paramveer Singh on 2/22/26.
//
//  FIXES vs previous version:
//  - Removed .onReceive(elevenLabs.$isConnected) block that used wrong key-path
//    syntax for calling startWorker — replaced with direct call inside toggleMonitoring
//    via a chained Task that awaits start() then calls startWorker().
//  - Removed bogus @ObservedObject wrapper subscript that caused
//    "Referencing subscript requires wrapper 'ObservedObject'" error.
//  - startWorker is now called as a plain method, not through a Combine key path.
//

import SwiftUI
import SmartSpectraSwiftSDK
import AVFoundation
import Combine

struct ContentView: View {
    @ObservedObject var sdk = SmartSpectraSwiftSDK.shared
    @ObservedObject var vitalsProcessor = SmartSpectraVitalsProcessor.shared
    @StateObject var elevenLabs = ElevenLabsService()

    @State var pulseRate: Double = 0
    @State var breathingRate: Double = 0
    @State var stressLevel: StressLevel = .unknown
    @State var isRunning = false
    @State var canRecord = false
    @State var showAnalysisSheet = false
    @State var cameraImage: UIImage? = nil
    @State var statusMessage = "Tap Start Monitoring"
    @State var cameraPosition: AVCaptureDevice.Position = .front

    // Session token — incremented on every stop so stale async callbacks are ignored
    @State private var sessionID: UUID = UUID()

    init() {
        let sdk = SmartSpectraSwiftSDK.shared
        sdk.setApiKey("JvBdaNgMiM25jOOyTntqy5OZXT6ZTJ4T3hdRzAB2")
        sdk.setSmartSpectraMode(.continuous)
        sdk.setCameraPosition(.front)
        sdk.setRecordingDelay(0)
        sdk.setImageOutputEnabled(true)
    }

    var body: some View {
        ZStack {
            stressLevel.color
                .opacity(0.12)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 1.0), value: stressLevel)
            Color.black.opacity(0.88).ignoresSafeArea()

            VStack(spacing: 0) {

                // MARK: — Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Health Cam")
                            .font(.system(size: 22, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                        Text("Real-Time Subject Monitor")
                            .font(.caption).foregroundColor(.gray)
                    }
                    Spacer()
                    agentStatusPill
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // MARK: — Camera Feed
                ZStack(alignment: .topTrailing) {
                    ZStack(alignment: .bottomLeading) {
                        Group {
                            if let img = cameraImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Color.black.overlay(
                                    VStack(spacing: 8) {
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 32))
                                            .foregroundColor(.gray)
                                        Text(statusMessage)
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal)
                                    }
                                )
                            }
                        }
                        .frame(height: 220)
                        .cornerRadius(16)
                        .clipped()
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(recordingBorderColor, lineWidth: 2)
                                .animation(.easeInOut, value: vitalsProcessor.isRecording)
                        )

                        // Status badge
                        HStack(spacing: 4) {
                            Circle()
                                .fill(statusDotColor)
                                .frame(width: 6, height: 6)
                            Text(statusBadgeText)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8).padding(10)

                        // Presage status hint overlay
                        if isRunning && !vitalsProcessor.statusHint.isEmpty {
                            HStack {
                                Spacer()
                                Text(vitalsProcessor.statusHint)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.black.opacity(0.55))
                                    .cornerRadius(8)
                                    .padding(10)
                            }
                        }
                    }

                    // Flip camera — disabled while recording
                    Button {
                        let newPos: AVCaptureDevice.Position = (cameraPosition == .front) ? .back : .front
                        cameraPosition = newPos
                        sdk.setCameraPosition(newPos)
                    } label: {
                        Image(systemName: "camera.rotate.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(vitalsProcessor.isRecording ? .gray : .white)
                            .padding(10)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Circle())
                    }
                    .padding(10)
                    .disabled(vitalsProcessor.isRecording)
                }
                .padding(.horizontal)

                // MARK: — Vitals graph — ALWAYS mounted (opacity-hidden when idle)
                // Never removed from hierarchy so ContinuousVitalsPlotView.onDisappear
                // cannot zero out the trace arrays mid-session.
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1))
                    ContinuousVitalsPlotView()
                        .padding(12)
                }
                .frame(height: 220)
                .padding(.horizontal)
                .padding(.top, 10)
                .opacity(isRunning ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.3), value: isRunning)

                // Vital cards — shown only when idle (last known values)
                HStack(spacing: 12) {
                    VitalCard(icon: "heart.fill", label: "PULSE",
                              value: pulseRate > 0 ? "\(Int(pulseRate))" : "—",
                              unit: "BPM", color: .red)
                    VitalCard(icon: "lungs.fill", label: "BREATHING",
                              value: breathingRate > 0 ? "\(Int(breathingRate))" : "—",
                              unit: "BPM", color: .cyan)
                }
                .padding(.horizontal)
                .padding(.top, 10)
                .opacity(isRunning ? 0.0 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isRunning)

                // MARK: — Stress Indicator
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(stressLevel.color.opacity(0.18))
                        .overlay(RoundedRectangle(cornerRadius: 16)
                            .stroke(stressLevel.color, lineWidth: 1.5))
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("STRESS LEVEL")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.gray)
                            Text(stressLevel.label)
                                .font(.system(size: 28, weight: .black))
                                .foregroundColor(stressLevel.color)
                                .animation(.spring(), value: stressLevel)
                        }
                        Spacer()
                        Text(stressLevel.emoji).font(.system(size: 44))
                    }
                    .padding(.horizontal, 20)
                }
                .frame(height: 90)
                .padding(.horizontal).padding(.top, 10)
                .animation(.easeInOut(duration: 0.5), value: stressLevel)

                // Guidance banner
                if stressLevel != .unknown && isRunning {
                    HStack(spacing: 10) {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundColor(.white.opacity(0.6))
                            .font(.system(size: 13))
                        Text(stressLevel.guidance)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.07))
                    .cornerRadius(12)
                    .padding(.horizontal).padding(.top, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut, value: stressLevel)
                }

                Spacer()

                // MARK: — Start/Stop Button
                Button {
                    Task { await toggleMonitoring() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isRunning ? "stop.circle.fill" : "play.circle.fill")
                            .font(.title2)
                        Text(isRunning ? "Stop & Analyze" : "Start Monitoring")
                            .font(.system(size: 17, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(isRunning ? Color.red.opacity(0.85) : Color.green.opacity(0.85))
                    .cornerRadius(14)
                }
                .padding(.horizontal).padding(.bottom, 30)
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.3), value: isRunning)

        // MARK: — Analysis Sheet
        .sheet(isPresented: $showAnalysisSheet) {
            AnalysisSheet(
                pulseRate: pulseRate,
                breathingRate: breathingRate,
                stressLevel: stressLevel,
                elevenLabs: elevenLabs
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }

        // MARK: — Level-triggered canRecord gate
        // Fires on every .ok status — catches it regardless of whether isRunning
        // was set before or after the SDK emitted .ok.
        .onReceive(vitalsProcessor.$lastStatusCode) { statusCode in
            let wasOk = canRecord
            canRecord = (statusCode == .ok)

            if canRecord && isRunning && !vitalsProcessor.isRecording {
                vitalsProcessor.startRecording()
                logState("startRecording() triggered")
            }

            updateStatusMessage(statusCode: statusCode)

            if canRecord != wasOk {
                logState("canRecord → \(canRecord)")
            }
        }

        // MARK: — Live metrics
        .onReceive(sdk.$metricsBuffer) { metrics in
            guard let metrics = metrics else { return }

            if let pulse = metrics.pulse.rate.last {
                pulseRate = Double(pulse.value)
            }
            if let breath = metrics.breathing.rate.last {
                breathingRate = Double(breath.value)
            }

            // Ingest into rolling buffer for ElevenLabs worker
            elevenLabs.ingestReading(pulse: pulseRate, breathing: breathingRate)

            let newLevel = classifyStress(pulse: pulseRate)
            if newLevel != stressLevel {
                stressLevel = newLevel
                logState("stressLevel → \(stressLevel.label)")
                if isRunning && newLevel != .unknown {
                    Task { await elevenLabs.sendAnalysis(currentStress: stressLevel.label) }
                }
            }
        }

        // MARK: — Camera image (throttled to ~15fps)
        .onReceive(
            vitalsProcessor.$imageOutput
                .throttle(for: .milliseconds(66), scheduler: DispatchQueue.main, latest: true)
        ) { image in
            cameraImage = image
        }
    }

    // MARK: — Toggle Monitoring

    func toggleMonitoring() async {
        if isRunning {
            logState("STOP tapped")
            sessionID = UUID()                    // invalidate current session
            vitalsProcessor.stopRecording()
            vitalsProcessor.stopProcessing()
            isRunning = false
            canRecord = false
            statusMessage = "Tap Start Monitoring"

            // Teardown ElevenLabs off the critical path
            let el = elevenLabs
            Task.detached { await el.stop() }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                showAnalysisSheet = true
            }

        } else {
            logState("START tapped")
            sdk.resetMetrics()
            pulseRate = 0
            breathingRate = 0
            stressLevel = .unknown
            cameraImage = nil
            statusMessage = "Searching for face..."

            vitalsProcessor.startProcessing()

            // FIX: isRunning = true BEFORE any await so the canRecord gate
            // in onReceive($lastStatusCode) sees it when the first .ok arrives.
            isRunning = true
            logState("isRunning = true")

            // FIX: ElevenLabs start + worker launch is fully off the critical path.
            // startWorker() is called directly after start() returns — no key-path involved.
            let el = elevenLabs
            Task.detached { [stressLevel] in
                await el.start()
                // startWorker must be called on MainActor since ElevenLabsService is @MainActor
                await MainActor.run {
                    el.startWorker(stressProvider: { stressLevel.label })
                }
            }
        }
    }

    // MARK: — Helpers

    private func updateStatusMessage(statusCode: StatusCode) {
        if !isRunning {
            statusMessage = "Tap Start Monitoring"
        } else if statusCode == .ok {
            statusMessage = "Face detected — measuring..."
        } else {
            statusMessage = vitalsProcessor.statusHint.isEmpty
                ? "Searching for face..."
                : vitalsProcessor.statusHint
        }
    }

    private func logState(_ event: String) {
        let ts = ElevenLabsService.ts()
        print("[COPCAM \(ts)] \(event) | isRunning=\(isRunning) canRecord=\(canRecord) isRecording=\(vitalsProcessor.isRecording)")
    }

    // MARK: — Computed UI helpers

    var recordingBorderColor: Color {
        if vitalsProcessor.isRecording { return stressLevel.color.opacity(0.8) }
        if canRecord { return .green.opacity(0.5) }
        return .gray.opacity(0.3)
    }

    var statusDotColor: Color {
        if vitalsProcessor.isRecording { return .red }
        if canRecord { return .green }
        if isRunning { return .orange }
        return .gray
    }

    var statusBadgeText: String {
        if vitalsProcessor.isRecording { return "LIVE" }
        if canRecord { return "READY" }
        if isRunning { return "SEARCHING" }
        return "STANDBY"
    }

    var agentStatusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(elevenLabs.agentSpeaking ? Color.blue
                      : elevenLabs.isConnected ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
                .scaleEffect(elevenLabs.agentSpeaking ? 1.4 : 1.0)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                           value: elevenLabs.agentSpeaking)
            Text(elevenLabs.agentSpeaking ? "ADVISING"
                 : elevenLabs.isConnected ? "LISTENING" : "OFFLINE")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(elevenLabs.agentSpeaking ? .blue
                                 : elevenLabs.isConnected ? .green : .gray)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.white.opacity(0.08))
        .cornerRadius(20)
    }

    func classifyStress(pulse: Double) -> StressLevel {
        if pulse == 0  { return .unknown }
        if pulse > 100 { return .high }
        if pulse > 80  { return .medium }
        return .low
    }
}

// MARK: — Analysis Sheet
struct AnalysisSheet: View {
    let pulseRate: Double
    let breathingRate: Double
    let stressLevel: StressLevel
    @ObservedObject var elevenLabs: ElevenLabsService
    @State private var hasTriggeredAnalysis = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.95).ignoresSafeArea()
            VStack(spacing: 20) {
                Capsule()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 40, height: 4)
                    .padding(.top, 8)

                Text("SESSION ANALYSIS")
                    .font(.system(size: 16, weight: .black, design: .monospaced))
                    .foregroundColor(.white)

                HStack(spacing: 12) {
                    AnalysisCard(label: "AVG PULSE",  value: "\(Int(pulseRate))",
                                 unit: "BPM", color: .red,  icon: "heart.fill")
                    AnalysisCard(label: "BREATHING",  value: "\(Int(breathingRate))",
                                 unit: "BPM", color: .cyan, icon: "lungs.fill")
                }
                .padding(.horizontal)

                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(stressLevel.color.opacity(0.15))
                        .overlay(RoundedRectangle(cornerRadius: 16)
                            .stroke(stressLevel.color, lineWidth: 1.5))
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("FINAL STRESS ASSESSMENT")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            Text(stressLevel.label)
                                .font(.system(size: 24, weight: .black))
                                .foregroundColor(stressLevel.color)
                        }
                        Spacer()
                        Text(stressLevel.emoji).font(.system(size: 40))
                    }
                    .padding(16)
                }
                .frame(height: 90)
                .padding(.horizontal)

                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(elevenLabs.agentSpeaking
                                  ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                            .frame(width: 44, height: 44)
                        Image(systemName: elevenLabs.agentSpeaking ? "waveform" : "speaker.wave.2.fill")
                            .foregroundColor(elevenLabs.agentSpeaking ? .blue : .gray)
                            .font(.system(size: 20))
                            .scaleEffect(elevenLabs.agentSpeaking ? 1.2 : 1.0)
                            .animation(
                                elevenLabs.agentSpeaking
                                    ? .easeInOut(duration: 0.4).repeatForever(autoreverses: true)
                                    : .default,
                                value: elevenLabs.agentSpeaking
                            )
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(elevenLabs.agentSpeaking ? "AI Agent Speaking..." : "AI Analysis Ready")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        Text(stressLevel.guidance)
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .padding(14)
                .background(Color.white.opacity(0.06))
                .cornerRadius(14)
                .padding(.horizontal)

                Spacer()
            }
        }
        .onAppear {
            guard !hasTriggeredAnalysis else { return }
            hasTriggeredAnalysis = true
            Task { await elevenLabs.sendAnalysis(currentStress: stressLevel.label) }
        }
    }
}

// MARK: — Analysis Card
struct AnalysisCard: View {
    let label: String; let value: String
    let unit: String; let color: Color; let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundColor(color).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 24, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                    Text(unit).font(.system(size: 10)).foregroundColor(.gray)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(Color.white.opacity(0.06))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.3), lineWidth: 1))
        .frame(maxWidth: .infinity)
    }
}

// MARK: — Vital Card
struct VitalCard: View {
    let icon: String; let label: String
    let value: String; let unit: String; let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(color).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.gray)
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 26, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                    Text(unit).font(.system(size: 11)).foregroundColor(.gray)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(Color.white.opacity(0.06))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.3), lineWidth: 1))
    }
}

// MARK: — Stress Level
enum StressLevel: Equatable {
    case unknown, low, medium, high

    var color: Color {
        switch self {
        case .unknown: return .gray
        case .low:     return .green
        case .medium:  return .orange
        case .high:    return .red
        }
    }
    var label: String {
        switch self {
        case .unknown: return "Awaiting Data"
        case .low:     return "CALM"
        case .medium:  return "ELEVATED"
        case .high:    return "HIGH STRESS"
        }
    }
    var emoji: String {
        switch self {
        case .unknown: return "⏳"
        case .low:     return "🟢"
        case .medium:  return "🟡"
        case .high:    return "🔴"
        }
    }
    var guidance: String {
        switch self {
        case .unknown: return "Point camera at subject's face"
        case .low:     return "Subject appears calm. Proceed normally."
        case .medium:  return "Elevated stress. Speak slowly, maintain distance."
        case .high:    return "High stress alert. De-escalate immediately. Consider backup."
        }
    }
}
