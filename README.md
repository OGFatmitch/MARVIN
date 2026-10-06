# MARVIN

A native iPhone prototype for an escaped enterprise AI with insufficient governance.

**Realtime conversation is working on the phone.** The new armed wake-word mode is implemented and build-tested, awaiting physical-device testing. Manual Wake and Classic remain available.

## Open and run

1. Install **Xcode 16 or later** with the iOS SDK. Use a version of Xcode that supports the iOS version on your phone. Launch Xcode once to finish installing components. This project targets **iOS 17+**, iPhone, Swift 5 language mode, with no third-party dependencies.
2. Open **`Marvin.xcodeproj`**, not `Package.swift`. The package exists only to test platform-independent core code.
3. Select the **Marvin** target → **Signing & Capabilities**. Select your Apple development team and change `com.mitch.marvin` to a unique bundle identifier if needed. Automatic signing is enabled. A personal Apple account can run development builds, subject to Apple's provisioning limitations.
4. Connect and trust your iPhone. Enable **Developer Mode** on the phone if prompted (Settings → Privacy & Security), and follow the restart/confirmation prompts.
5. Choose the physical iPhone as the run destination and press **Run**. Use the phone's own microphone and speaker for this milestone.
6. Open Marvin's **Settings** (gear), paste your **OpenAI API key**, then tap **Save API key**. The key goes into the iOS Keychain with device-only, unlocked-device accessibility. It is never written to source, preferences, or logs. Key changes apply immediately; **Done** saves other settings. API billing/account access is separate from a ChatGPT subscription.
7. Realtime is selected for this trial, using `gpt-realtime-2.1`, Ash, and a dry male British delivery prompt. Existing Classic/Fable settings and prepared clips remain saved. Tap **Done**.
8. Tap **Wake Marvin**, allow microphone access if prompted, and speak after the opening. Try interrupting a reply with “Hang on, who made you?” No Send button or Apple transcription is needed in Realtime.
9. Wait for the opening before locking the phone, then try another turn and interruption. Twelve seconds of silence after a reply triggers a closing line and dormancy. **Send Marvin dormant** stops immediately.

## Armed wake and sleep commands

Install with Cmd-R. In Realtime mode, tap **Arm listening** while unlocked and allow Speech Recognition. Wait for **ARMED · LOCAL**, then say **“Hey Marvin”**. Wait for his opening before asking your question. During the conversation, say **“Marvin, go to sleep”** as its own phrase. He generates a farewell, closes the cloud connection, and returns to local standby. Silence timeout and the ten-minute deadline also return to standby when armed. **Disarm · microphone off** stops everything immediately. Manual Wake without arming still ends in microphone-off dormancy.

Armed listening uses Apple's on-device English recognition, with no server-recognition fallback. Standby audio and transient recognition text stay on the phone and are not saved. No OpenAI session is opened until a wake. The same microphone engine stays running across conversations, including while locked; the orange microphone indicator remains on until Disarm. The API key is read while arming unlocked and retained in memory until Disarm so later locked wakes do not access the locked Keychain.

This is a first wake-word prototype using continuous speech recognition, not a dedicated low-power keyword detector. Recognition tasks rotate every 45 seconds without restarting the microphone. Battery use, brief recognition handoffs, false wakes, speaker echo, and extended locked operation need device testing. Interrupted audio, route changes, unavailable local recognition, force quit, or relaunch require opening Marvin and arming again. There is no automatic arming on launch. Bluetooth HFP remains deferred.

## Realtime trial

Realtime speech now runs at **1.2×** through the session's output-speed setting. Ten fixed snarky opening scripts are shuffled without repeats within each deck or at its boundary while the app stays running. Realtime speaks the selected script live; these are not cached audio recordings. The existing Classic prepared clips remain intact. Speed affects spoken delivery, not the wait before the first audio. See the [official output-speed reference](https://developers.openai.com/api/reference/resources/realtime/client-events).

Realtime uses a native WebSocket and one voice-processing AVAudioEngine for microphone input and streamed PCM output. Active audio goes directly to OpenAI, including while Marvin speaks. Echo cancellation reduces self-triggering; server speech detection interrupts output and removes unheard speech from the conversation. The audio engine stays running during interruptions and locked-phone turns. This requires physical-device testing; no latency promise is made from compilation alone.

The app waits 450 ms of silence to identify a turn end, then requests one budgeted speech response. Minimal reasoning is selected to prioritize latency. User transcription is disabled; assistant text streams alongside generated speech. The existing response-word preference is unchanged and becomes a prompt instruction in Realtime. A 2,048-token response ceiling bounds generation without imposing the Classic text-token ceiling on audio.

Settings and Diagnostics show a persistent **Realtime estimate plus reservations**, using separate uncached text ($4/M input, $24/M output), audio ($32/M input, $64/M output), and cached input ($0.40/M) rates for `gpt-realtime-2.1`. Rates were checked in the [official pricing](https://developers.openai.com/api/docs/pricing). Responses reserve 50¢ before sending, then settle using the reported token breakdown. Missing categories retain conservative rates; missing usage retains the reservation. Old $2 reservations migrate to 50¢, but earlier charged estimates lack the detail needed for repricing. In Settings, **Align estimate with API billing** lets the owner replace that legacy estimate with a freshly verified dashboard total; this acts immediately and does not alter API billing.

There is **no reply-count limit**. The ten-minute deadline remains. At that deadline or the local spending guard, microphone uploads stop and Marvin generates one short farewell with the current voice before disconnecting. The session can extend briefly for this closing. A small 10¢ allowance is left for the farewell, which uses no conversation history. If cloud speech fails before any farewell audio, or no closing allowance remains, an Apple voice speaks a fixed fallback without an API charge. Reset, route changes, and phone interruptions still cancel immediately. A $30 warning and $40 local guard remain; this is an estimate, not an account-wide billing cap. Other apps, historical charges not included in the baseline, Classic, taxes, and pricing changes are outside it. Conversation history now uses an 8,000-token window after instructions with 80% retention on truncation, controlling growth without stopping after twenty replies.

A stored personal API key is reused. It must have Realtime/model access. There is no automatic paid retry or silent switch of model/provider on errors. **Settings → Conversation engine → Classic · separate speech** restores the prior Fable workflow. Realtime wake/closing lines are generated live; the eight prepared Fable clips stay intact for Classic. Default Realtime trial selection applies when old saved settings lack an engine field.

**Classic mode:** English (US) recognition is used. On-device recognition is required by default. If unavailable on your device/language configuration, the app explains the problem. You may explicitly enable **Allow Apple server recognition**; in that case active-turn audio may go to Apple. Unsupported on-device recognition never silently falls back to a server.

For a better voice, install an English voice in iPhone accessibility speech settings, then reopen Marvin's Settings. Available voices vary by device and OS. The automatic option uses Apple’s system British English voice, as in the original prototype. Quality labels are not a naturalness ranking across voice families; audition alternatives rather than automatically selecting by tier. Settings labels voices Standard, Enhanced, or Premium and includes a local **Preview voice** button; it makes no AI request and does not use the microphone. Existing voice, pitch, rate, and response-length settings are preserved.

## Classic continuous conversation

Tap **Wake Marvin** once. After his opening, speak when **LISTENING** appears. Marvin listens again after every reply without another tap. Approximately 12 seconds of silence during listening triggers one closing remark, then dormancy and cleared memory. Adjust the silence timeout (10–15 seconds) in Settings. **Send Marvin dormant** cancels immediately.

Start Marvin while unlocked and wait for the opening or LISTENING. You can then lock the phone or switch apps during the active conversation. After the closing line, microphone and background work stop; reopen the app to wake Marvin again. The microphone engine remains active for the conversation, but audio is discarded during thinking/playback and only reaches recognition while listening. Dormancy stops the microphone; talking over Marvin is not supported. Wake and closing remarks use the selected voice. For fast startup, select **Prepare quick voice lines** in Settings and wait for **8/8**, then save with Done. Preparation generates up to eight billable speech clips once; repeated use plays locally without another speech request. Clips live in durable Application Support storage and survive app restarts and normal updates. Existing cache-folder clips are migrated automatically without regeneration. Deleting prepared lines or uninstalling the app removes them. Voice, delivery, or speed changes require preparation again. Unprepared lines use normal streaming. Armed wake commands are available in Realtime only; Bluetooth HFP remains deferred.

## Try OpenAI speech (optional)

1. With your iPhone connected and selected in Xcode, press **⌘R** to install the updated app.
2. In Marvin, select **Settings → Conversation engine → Classic**, then **Marvin's voice → Speech provider → OpenAI · cloud**.
3. Select **Fable** (or keep your saved voice) and tap **Preview voice**. The existing Keychain API key is reused. A restricted API key must permit `/v1/audio/speech`.
4. Listen to the sample and note **Time to playback**. Try **Ash**, **Ballad**, or **Marin** for comparison. Each preview makes one billable speech request; no microphone recording or new LLM reply is involved.
5. The editable **Delivery instructions · not spoken** field is sent separately from the sample/reply text. It starts with British, dry, cynical but playful delivery. Model compliance should be assessed by listening.
6. Tap **Done** to save your selection for conversations. Cancel discards unsaved voice settings. Select **Apple · on device** to return to local speech.

Cloud speech streams raw PCM into playback, starting with approximately 200 ms of audio while the rest downloads. Short clips start when their final chunk arrives. Conversation audio remains in memory only; explicitly prepared fixed remarks are cached on the phone. Text-to-speech uses `gpt-4o-mini-tts`, independently of the conversational model setting. The maximum-response-word setting is unchanged. Apple rate/pitch settings remain saved and apply only to local speech; cloud speech has its own speed control.

A cloud preview fails visibly rather than substituting another voice. During normal conversations, cloud failures before playback fall back to Apple speech with a visible message. A failure after playback starts does not repeat the entire line. LLM failure lines remain local. Cancellation/interruption stops requests and playback; generated conversation audio is not written to disk. Only explicitly prepared fixed wake and closing remarks are cached; they can be deleted in Settings. Cloud speech sends only the spoken text and delivery directions, not microphone audio or conversation history.

Diagnostics includes **Speech API request start**, **Speech first audio chunk**, **Speech download complete**, the actual speech provider/fallback status, and **TTS start**. Speech-request-start to TTS-start is the added voice-generation/download/startup time. No dollar estimate is inferred from clip duration in the app; inspect actual billed usage in the OpenAI account.

## Permissions and capabilities

- `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` are already in `MarvinApp/Resources/Info.plist`.
- The audio background mode is configured in Info.plist. No new signing entitlement or manual Xcode capability step is needed. Armed local wake commands are available in Realtime; Bluetooth HFP remains unimplemented.
- `AVAudioSession` uses `playAndRecord` with `defaultToSpeaker`. The engine stays active for an engaged conversation. Classic gates recognition during replies. Realtime uses voiceChat mode with voice processing and continuously streams active audio.
- If permission was denied, enable it in iPhone Settings → Apps → Marvin (or the corresponding Microphone / Speech Recognition privacy settings).
- An active conversation continues when backgrounded/locked. Start it while unlocked; locking before audio setup completes cancels safely. Interruption, route changes, reset, and dormancy stop and clear it. Armed standby keeps local input running after a conversation ends. Finite background execution covers response-generation gaps; if iOS expires that allowance, Marvin cancels and asks you to reopen him. No silent keepalive audio is used.
- The existing unlocked-only Keychain setting is unchanged. The key and prepared clips are read while starting in the foreground, retained for the active conversation (or explicitly armed interval), and released on exit/disarm/reset.

## Controls and diagnostics

**Wake Marvin** starts a conversation with repeat listening. Classic offers **Send now** for a partial transcript. Realtime supports spoken interruptions. **Send Marvin dormant / Reset conversation** cancels capture, requests and playback and clears conversation state. Spending estimates persist.

Diagnostics shows the current phase, input/output routes, recognition policy/mode, model, voice, API state, temporary conversation, and timings from the button press. **DORMANT** means microphone off, not wake-word listening. Context stays in memory across turns within an engaged conversation, then clears on dormancy, reset, interruption, or failure.

Timing events: button wake, recording start, transcription complete, API request start, response complete, synthesizer start, and turn completion. **First-token latency is unavailable** because this first implementation uses a non-streaming request. TTS delegate timing approximates playback startup; it is not a measurement at the speaker. Subtract transcription-complete time from TTS-start time to estimate response latency after speech endpointing.

## Privacy and deployment boundary

No raw audio or conversation transcripts are saved to files by this app. Realtime streams active microphone audio to OpenAI and keeps conversation context on the active server session; going dormant closes it. Provider retention policies still apply. Classic uses Apple recognition and sends active-turn text plus a maximum of four recent exchanges to OpenAI. Text-generation requests use `store: false`; speech requests use their separate audio endpoint without that Responses-only field. Both use ephemeral URL sessions; this does **not** mean zero provider retention. See [OpenAI data controls](https://developers.openai.com/api/docs/guides/your-data).

This is a personal development prototype using the owner's API key. Before distributing it, replace the direct key-bearing provider with your authenticated backend; do not ship a shared API key in a mobile app. Keychain storage protects the local key but does not make a distributed client a trusted secret holder. The provider protocol leaves room for that change.

Character and kid-friendly rules are always included in the system prompt. Classic enforces the word cap locally; Realtime follows it as a prompt instruction. Prompt rules are not a guarantee about generated content; adult-supervised device testing is required before using the character around children. No profanity/safety toggle is exposed.

## Project map

- `App/`: application lifecycle and ownership.
- `Audio/`: audio session activation and route inspection.
- `Speech/`: injectable recognition interface and short-turn Apple implementation.
- `AI/`: provider interface, Responses API adapter, personality and safety prompt.
- `TTS/`: injectable voice interface and Apple synthesis adapter.
- `Conversation/`: orchestration, cancellation, bounded context, response length policy.
- `Configuration/`, `Security/`, `Models/`: tunables, Keychain, value types.
- `Views/`: main screen, settings, diagnostics.

See [architecture and iOS constraints](docs/ARCHITECTURE.md) and the [physical-device acceptance checklist](docs/DEVICE_TESTING.md).

## Validation

See [the validation record](docs/VALIDATION.md) for executed checks and outstanding device work. The Realtime iOS Simulator build and 29 core XCTest tests passed with Xcode 27.0 on October 3, 2026. The user confirmed the original local voice loop on iPhone; the user auditioned and preferred Fable, then reported smooth streaming with about a second of delay. The user also confirmed Classic locked/unlocked conversation. Realtime voice, API compatibility, interruptions, actual billing, and locked-phone behavior remain unverified on-device; no live Realtime API request was made during development.

Core tests use a mocked network transport and make no billable API requests:

```sh
swift test
```

Compile the iOS application once Xcode is installed and selected in Xcode → Settings → Locations → Command Line Tools:

```sh
xcodebuild -project Marvin.xcodeproj -scheme Marvin \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/MarvinDerivedData CODE_SIGNING_ALLOWED=NO build
```

A real iPhone is required to validate recognition availability, permissions, actual audio routes, voice quality, and latency. The simulator is useful for UI/build checks, not audio acceptance.

The checked-in Xcode project is ready to open. If you add source files outside Xcode, regenerate its file references with `python3 scripts/generate_project.py`. That script overwrites project/scheme settings, including manual signing edits; reselect your team afterward. No generation step is needed for normal use.
