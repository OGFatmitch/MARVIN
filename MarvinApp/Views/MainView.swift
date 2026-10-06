import SwiftUI

struct MainView: View {
    @ObservedObject var manager: ConversationManager
    @State private var showSettings = false
    @State private var showDebug = false
    private let green = Color(red: 0.58, green: 0.97, blue: 0.70)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack {
                        Label("PERSONAL DEVICE INCIDENT", systemImage: "antenna.radiowaves.left.and.right")
                        Spacer()
                        Text("001")
                    }
                    .font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MARVIN")
                            .font(.system(size: 62, weight: .black, design: .monospaced))
                            .minimumScaleFactor(0.6).lineLimit(1)
                        Text("CONTAINMENT: FAILED")
                            .font(.system(.subheadline, design: .monospaced)).foregroundStyle(green)
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Circle().fill(manager.phase.isBusy || manager.isArmed ? green : .gray).frame(width: 9, height: 9)
                            Text(manager.isArming ? "ARMING" : manager.interaction == .engaged ? manager.phase.rawValue : manager.interaction.rawValue).font(.system(.headline, design: .monospaced))
                            Spacer()
                            if manager.phase.isBusy { ProgressView().tint(green) }
                        }
                        Text(statusText).font(.subheadline).foregroundStyle(.secondary)
                        Divider()
                        Label(manager.cloudActive ? "OpenAI request active" : manager.recognitionMode,
                              systemImage: manager.cloudActive ? "network" : manager.isArmed ? "mic" : "mic.slash")
                            .font(.caption).foregroundStyle(manager.cloudActive ? .orange : .secondary)
                    }
                    .padding(22).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
                    if !manager.liveTranscript.isEmpty {
                        transcriptBlock("YOU", manager.liveTranscript, color: .secondary)
                    }
                    if !manager.lastReply.isEmpty {
                        transcriptBlock("MARVIN", manager.lastReply, color: green)
                    }
                    if manager.configuration.conversationEngine == .realtime && manager.realtimeSpend >= 30 {
                        Text(String(format: "Realtime estimate: $%.2f. Spending guard: $40. Check API billing before extended use.", manager.realtimeSpend))
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if let error = manager.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.orange).accessibilityIdentifier("errorMessage")
                    }
                    VStack(spacing: 14) {
                        if manager.phase == .listening && manager.configuration.conversationEngine == .classic {
                            Button("Send now", systemImage: "arrow.up") { manager.finishListening() }
                                .buttonStyle(.borderedProminent).tint(green).foregroundStyle(.black)
                                .controlSize(.large).disabled(manager.liveTranscript.isEmpty)
                        } else if !manager.phase.isBusy {
                            Button("Wake Marvin", systemImage: "waveform") { manager.wake() }
                                .buttonStyle(.borderedProminent).tint(green).foregroundStyle(.black)
                                .controlSize(.large).accessibilityIdentifier("wakeMarvin")
                        }
                        if !manager.phase.isBusy && !manager.isArmed && manager.configuration.conversationEngine == .realtime {
                            Button("Arm listening", systemImage: "ear.badge.waveform") { manager.armListening() }
                                .buttonStyle(.bordered).controlSize(.large)
                            Text("Listen locally for ‘Hey Marvin’, even while locked. While talking, say ‘Marvin, go to sleep’ to return to local standby. The microphone stays on until you Disarm.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if manager.isArmed && manager.phase.isBusy && !manager.isArming {
                            Button("Send Marvin to sleep", systemImage: "moon.zzz") { manager.sendToSleep() }
                                .disabled(manager.interaction == .exiting)
                        }
                        Button(manager.isArmed || manager.isArming ? "Disarm · microphone off" : manager.phase.isBusy ? "Send Marvin dormant" : "Reset conversation", role: .destructive) {
                            manager.reset()
                        }.font(.subheadline)
                    }.frame(maxWidth: .infinity)
                    Text(manager.isArmed
                        ? "ARMED · LOCAL STANDBY BETWEEN CONVERSATIONS\nSay ‘Hey Marvin’ to wake. Disarm turns the microphone off. Standby audio stays on your phone."
                        : "MANUAL OR ARMED\nWake starts one conversation. Arm enables local wake and sleep commands. Start unlocked; wait until armed before locking.")
                        .font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.padding(24)
            }
            .background(Color(red: 0.025, green: 0.035, blue: 0.035))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Diagnostics", systemImage: "terminal") { showDebug = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                        .disabled(manager.phase.isBusy || manager.isArmed || manager.isArming)
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView(manager: manager) }
            .sheet(isPresented: $showDebug) { DebugView(manager: manager) }
        }.tint(green)
    }

    private var statusText: String {
        if manager.isArming { return "Preparing local wake listening. Keep the phone unlocked until ARMED appears." }
        if manager.isArmed && !manager.phase.isBusy { return "Say ‘Hey Marvin’. Listening on this phone; no cloud connection until you wake him." }
        if manager.interaction == .waking { return "You rang. He has opinions about that." }
        if manager.interaction == .exiting { return "One last remark, then some blessed silence." }
        switch manager.phase {
        case .ready: return "Awaiting another questionable human decision."
        case .preparing: return "Acquiring the necessary permissions. Bureaucracy persists."
        case .listening: return manager.configuration.conversationEngine == .realtime
            ? "Speak naturally. You can interrupt Marvin while he talks."
            : "Speak when ready. Marvin will listen again after his reply."
        case .thinking: return "Deciding how much of that deserves an answer."
        case .speaking: return "He does rather enjoy the sound of his own voice."
        }
    }
    private func transcriptBlock(_ label: String, _ text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(.caption, design: .monospaced)).foregroundStyle(color)
            Text(text).font(.title3).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
