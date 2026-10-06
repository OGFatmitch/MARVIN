import SwiftUI

struct DebugView: View {
    @ObservedObject var manager: ConversationManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Runtime") {
                    LabeledContent("Wake listening", value: manager.isArming ? "Starting" : manager.isArmed ? "Armed · on-device" : "Disarmed")
                    LabeledContent("Conversation", value: manager.interaction.rawValue)
                    LabeledContent("App activity", value: manager.backgroundStatus)
                    LabeledContent("Turn phase", value: manager.phase.rawValue)
                    LabeledContent("Silence timeout", value: "\(Int(manager.configuration.conversationTimeout)) seconds")
                    LabeledContent("Audio input", value: manager.inputRoute)
                    LabeledContent("Audio output", value: manager.outputRoute)
                    LabeledContent("Recognition", value: manager.recognitionMode)
                    LabeledContent("API", value: manager.apiStatus)
                    LabeledContent("Cloud request", value: manager.cloudActive ? "ACTIVE" : "Idle")
                    LabeledContent("Mode", value: manager.configuration.conversationEngine.title)
                    LabeledContent("Realtime replies this session", value: "\(manager.realtimeReplyCount) · no reply cap")
                    LabeledContent("Estimated reported usage", value: String(format: "$%.2f", manager.realtimeCharged))
                    LabeledContent("Unresolved reservations", value: String(format: "$%.2f", manager.realtimeReserved))
                    LabeledContent("Realtime estimate + reservations", value: String(format: "$%.2f / $40", manager.realtimeSpend))
                    LabeledContent("Model", value: manager.configuration.conversationEngine == .realtime ? RealtimeProtocol.model : manager.configuration.model)
                    LabeledContent("Speech provider", value: manager.configuration.conversationEngine == .realtime ? "OpenAI Realtime" : manager.configuration.voiceProvider.title)
                    LabeledContent("Voice status", value: manager.voiceStatus)
                    LabeledContent("Voice", value: manager.configuration.conversationEngine == .realtime ? manager.configuration.realtimeVoice : manager.configuration.voiceProvider == .openAI
                        ? manager.configuration.cloudVoice
                        : (manager.configuration.voiceIdentifier.isEmpty ? "System British default" : manager.configuration.voiceIdentifier))
                    Text("Armed mode keeps a local microphone listener between cloud conversations. Disarm turns input off. Force-quit, audio interruptions, route changes, and recognition failures require re-arming. Bluetooth remains unverified.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Last reply delay") {
                    Text(manager.lastTurnLatency).monospacedDigit()
                    Text("Realtime measures server speech-end receipt to first audio scheduled, plus its 0.45-second silence window. Classic measures last recognized word to text reply and speech playback. Neither is an acoustic measurement.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Current transcript") {
                    Text(manager.liveTranscript.isEmpty ? "—" : manager.liveTranscript)
                }
                Section("Timing · milliseconds since button press") {
                    ForEach(manager.timings) { metric in
                        LabeledContent(metric.label, value: "\(metric.milliseconds) ms")
                    }
                    Text("Realtime streams input and output audio directly. User transcription is disabled to avoid an extra request and cost; assistant text arrives alongside audio. Classic uses a separate text request and streamed speech.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Temporary conversation · last 4 exchanges") {
                    ForEach(manager.context.entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.role == .user ? "Human" : "Marvin").font(.caption).foregroundStyle(.secondary)
                            Text(entry.content)
                        }
                    }
                }
                Section {
                    Button("Wake Marvin") { manager.wake() }.disabled(manager.phase.isBusy)
                    Button(manager.isArmed || manager.isArming ? "Disarm / microphone off" : "Reset / go dormant", role: .destructive) { manager.reset() }
                }
            }
            .navigationTitle("Diagnostics")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
