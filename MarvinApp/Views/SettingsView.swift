import AVFoundation
import SwiftUI

struct SettingsView: View {
    @ObservedObject var manager: ConversationManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var preview = VoicePreview()
    @StateObject private var preparedLines = PreparedVoiceLines()
    @State private var config = MarvinConfig()
    @State private var newKey = ""
    @State private var verifiedSpend = ""
    @State private var hasKey = false
    @State private var status: String?
    private let keychain = KeychainStore()
    private var voices: [AVSpeechSynthesisVoice] {
        AppleVoiceSelection.englishVoices
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Wake and sleep commands") {
                    Text("On the main screen, Arm listening enables on-device English recognition for ‘Hey Marvin’. During an armed conversation, say ‘Marvin, go to sleep’. A closing line returns to local standby; Disarm turns the microphone off. Arm while unlocked and wait for ARMED before locking. This first version uses speech recognition, not a low-power keyword chip; battery life, noise, and recognition-task handoffs need device testing. No Apple server fallback is allowed for these commands.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Conversation engine") {
                    Picker("Mode", selection: $config.conversationEngine) {
                        ForEach(MarvinConfig.ConversationEngine.allCases, id: \.self) { engine in
                            Text(engine.title).tag(engine)
                        }
                    }
                    if config.conversationEngine == .realtime {
                        Picker("Realtime voice", selection: $config.realtimeVoice) {
                            ForEach(RealtimeProtocol.voices, id: \.self) { Text($0.capitalized).tag($0) }
                        }
                        Text("Ash starts with a dry, male British delivery prompt. Talk naturally and interrupt him whenever you like. Active microphone audio streams to OpenAI, including while he speaks. Manual dormancy turns the microphone off. Armed conversations return to local standby; Disarm turns the microphone off.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Realtime generates its own wake and closing audio. Your prepared Fable clips remain available in Classic mode.")
                            .font(.caption).foregroundStyle(.secondary)
                        LabeledContent("Volume", value: String(format: "%.0f%%", config.volume * 100))
                        Slider(value: $config.volume, in: 0...1)
                        Stepper("Maximum words: \(config.maximumResponseWords)", value: $config.maximumResponseWords, in: 10...60)
                    }
                }
                Section("Realtime spending guard") {
                    LabeledContent("Estimate + reservations", value: String(format: "$%.2f / $40", manager.realtimeSpend))
                    Text("Persists across restarts. Stops new Realtime replies before the $40 guard, leaving room below your $50 budget. Uses separate audio, text, and cached-token prices. Holds 50¢ per pending reply and leaves 10¢ for a closing remark. Missing usage keeps its reservation. Excludes previous charges, Classic speech, and other apps. This is not an account-wide billing cap; verify actual charges in OpenAI billing. Reinstalling the app can erase this counter.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Align estimate with API billing") {
                    TextField("Verified total in USD, e.g. 0.47", text: $verifiedSpend)
                        .keyboardType(.decimalPad)
                    Button("Use verified billing total") {
                        if let value = Double(verifiedSpend), manager.reconcileBudget(verifiedTotal: value) {
                            status = "Local estimate aligned. New usage will be added from here."
                            verifiedSpend = ""
                        } else { status = "Enter a valid non-negative dollar total while Marvin is dormant." }
                    }.disabled(verifiedSpend.isEmpty || manager.phase.isBusy)
                    Text("Check the relevant total in your API dashboard immediately before using this. Replaces the old local estimate and clears unresolved reservations. It does not change your API bill. Changes apply immediately. Old estimated charges cannot be recalculated because earlier versions did not save token details.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("OpenAI") {
                    Text(hasKey ? "API key saved in Keychain" : "No API key configured")
                    SecureField("Paste API key", text: $newKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save API key") {
                        do { try keychain.save(newKey); newKey = ""; hasKey = true; status = "API key saved." }
                        catch { status = error.localizedDescription }
                    }.disabled(newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Delete API key", role: .destructive) {
                        preparedLines.stop()
                        do { try keychain.delete(); hasKey = false; newKey = ""; status = "API key deleted." }
                        catch { status = error.localizedDescription }
                    }.disabled(!hasKey)
                    if config.conversationEngine == .classic {
                        TextField("Model", text: $config.model)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    } else { LabeledContent("Model", value: RealtimeProtocol.model) }
                    Text("Uses your API account, billed separately from ChatGPT. Realtime sends live microphone audio; Classic sends conversation text and optional speech requests.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if config.conversationEngine == .classic {
                Section("Speech recognition · English (US)") {
                    Toggle("Allow Apple server recognition", isOn: $config.allowAppleServerRecognition)
                    Text("Off by default. When enabled, spoken audio may be sent to Apple if on-device recognition is unavailable. During an active conversation, listening resumes after each reply. The microphone stays active through a conversation. Audio is discarded while Marvin speaks; transcription resumes afterward. Dormant turns the microphone off.")
                        .font(.caption).foregroundStyle(.secondary)
                    LabeledContent("End-of-speech pause", value: String(format: "%.1f s", config.endOfSpeechDelay))
                    Slider(value: $config.endOfSpeechDelay, in: 0.5...3, step: 0.1)
                }
                }
                Section("Conversation") {
                    LabeledContent("Silence before closing", value: "\(Int(config.conversationTimeout)) seconds")
                    Slider(value: $config.conversationTimeout, in: 10...15, step: 1)
                    Text("Silence countdown starts after each reply finishes. Realtime accepts interruptions during speech; Classic requires waiting for LISTENING. Start here before locking the phone. Reopen Marvin to wake him after dormancy. Realtime has no reply-count cap. At ten minutes or the spending guard, Marvin gives a final remark and goes dormant. A limit farewell briefly extends the session while it plays. Older conversation history may be trimmed to control cost.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if config.conversationEngine == .classic {
                Section("Marvin's voice") {
                    Picker("Speech provider", selection: $config.voiceProvider) {
                        ForEach(MarvinConfig.VoiceProvider.allCases, id: \.self) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    if config.voiceProvider == .openAI {
                        cloudVoiceControls
                    } else {
                        appleVoiceControls
                    }
                    if config.voiceProvider == .openAI {
                        LabeledContent("Prepared wake / closing lines", value: "\(preparedLines.readyCount)/\(PreparedSpeechCache.lines.count)")
                        Button(preparedLines.isPreparing ? "Stop preparing" : "Prepare quick voice lines") {
                            preview.stop()
                            if preparedLines.isPreparing { preparedLines.stop() }
                            else { preparedLines.prepare(configuration: config.validated()) }
                        }.disabled(!hasKey && !preparedLines.isPreparing)
                        Text("Generates up to eight short clips once using your current voice and delivery settings. Each missing clip incurs a speech-generation charge. These fixed remarks stay in app storage across restarts and normal app updates for quick local playback; conversation replies are never saved. Prepare again after changing voice, delivery, or speed.")
                            .font(.caption).foregroundStyle(.secondary)
                        if !preparedLines.message.isEmpty {
                            Text(preparedLines.message).font(.caption).foregroundStyle(.secondary)
                        }
                        Button("Delete prepared voice lines", role: .destructive) {
                            preparedLines.clear(configuration: config)
                        }.disabled(preparedLines.isPreparing)
                    }
                    Button(preview.isPlaying ? "Stop preview" : "Preview voice") {
                        if preview.isPlaying { preview.stop() }
                        else { preparedLines.stop(); preview.play(configuration: config) }
                    }.disabled(config.voiceProvider == .openAI && !hasKey && !preview.isPlaying)
                    if !preview.playbackStatus.isEmpty {
                        Text(preview.playbackStatus).font(.caption).foregroundStyle(.secondary)
                    }
                    if let elapsed = preview.startupMilliseconds {
                        Text(String(format: "Time to playback: %.2f seconds", Double(elapsed) / 1000))
                            .font(.caption).monospacedDigit()
                    }
                    if let error = preview.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    }
                    LabeledContent("Volume", value: String(format: "%.0f%%", config.volume * 100))
                    Slider(value: $config.volume, in: 0...1)
                    Stepper("Maximum words: \(config.maximumResponseWords)", value: $config.maximumResponseWords, in: 10...60)
                }
                }
                Section("Privacy & behavior") {
                    Text("PG-13 character with playful, non-cruel responses around children. This is an AI-generated voice. Microphone audio and conversation replies are never saved by this app. Explicitly armed standby uses only on-device recognition; active conversations send audio to OpenAI. Realtime sends active audio to OpenAI; provider retention policies apply. Only the fixed wake and closing clips you prepare are saved on this phone. Transcripts stay in memory until Marvin goes dormant, is reset, or is interrupted. An active conversation continues when you lock the phone or switch apps. Text-generation requests use store: false. Optional cloud speech sends reply text and delivery instructions to OpenAI; provider retention policies apply.")
                        .font(.caption)
                }
                if let status { Section { Text(status).font(.callout) } }
            }
            .navigationTitle("Configuration")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { manager.saveConfiguration(config); dismiss() }
                }
            }
            .onAppear {
                config = manager.configuration
                preparedLines.refresh(configuration: config)
                do { hasKey = !(try keychain.read()).isEmpty } catch { status = error.localizedDescription }
            }
            .onChange(of: config) { old, new in
                if old.voiceProvider != new.voiceProvider || old.cloudVoice != new.cloudVoice ||
                    old.cloudSpeed != new.cloudSpeed || old.deliveryInstructions != new.deliveryInstructions {
                    preparedLines.refresh(configuration: new)
                }
            }
            .onChange(of: config.conversationEngine) { _, _ in preview.stop(); preparedLines.stop() }
            .onChange(of: config.voiceProvider) { _, _ in preview.stop() }
            .onChange(of: config.cloudVoice) { _, _ in preview.stop() }
            .onChange(of: config.voiceIdentifier) { _, _ in preview.stop() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { preview.stop(); preparedLines.stop() }
            }
            .onDisappear { newKey = ""; preview.stop(); preparedLines.stop() }
        }
    }

    @ViewBuilder
    private var cloudVoiceControls: some View {
        Picker("OpenAI voice", selection: $config.cloudVoice) {
            ForEach(MarvinConfig.cloudVoices, id: \.self) { voice in
                Text(voice.capitalized).tag(voice)
            }
        }
        Text("Uses gpt-4o-mini-tts and your saved API key. Each preview sends this sample to OpenAI and incurs a speech-generation charge. No microphone recording or new AI reply is involved.")
            .font(.caption).foregroundStyle(.secondary)
        Text("Sample: Mitch has another idea. Do give me a moment to recover from the last one.")
            .font(.callout)
        Text("Delivery instructions · not spoken").font(.subheadline)
        TextEditor(text: $config.deliveryInstructions).frame(minHeight: 130)
        Button("Restore Marvin delivery") { config.deliveryInstructions = MarvinConfig.defaultDelivery }
        LabeledContent("Speed", value: String(format: "%.2f×", config.cloudSpeed))
        Slider(value: $config.cloudSpeed, in: 0.75...1.25, step: 0.05)
        Text("OpenAI speech starts playing after a short audio buffer arrives and continues downloading while it plays. Conversations fall back to Apple if cloud speech fails before playback; previews show an error instead so you know which voice you heard.")
            .font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var appleVoiceControls: some View {
        Picker("Voice", selection: $config.voiceIdentifier) {
            Text("Automatic · British English").tag("")
            ForEach(voices, id: \.identifier) { voice in
                Text(AppleVoiceSelection.label(voice)).tag(voice.identifier)
            }
        }
        if let voice = AppleVoiceSelection.resolve(config.voiceIdentifier) {
            Text("Using: " + AppleVoiceSelection.label(voice)).font(.caption).foregroundStyle(.secondary)
        }
        Text("Apple previews run locally without an API charge. Download additional English voices in iPhone accessibility speech settings, then reopen this screen.")
            .font(.caption).foregroundStyle(.secondary)
        LabeledContent("Rate", value: String(format: "%.2f", config.rate))
        Slider(value: $config.rate, in: 0.35...0.6)
        LabeledContent("Pitch", value: String(format: "%.2f", config.pitch))
        Slider(value: $config.pitch, in: 0.7...1.2)
    }

}
