# Armed listener addition — October 5, 2026

`ArmedListeningService` owns one `RealtimeAudioIO` from explicit foreground Arm until Disarm. It drains bounded 24 kHz microphone PCM into an on-device-only English SFSpeechRecognizer. Transient standby text is used only for strict wake/sleep matching and is never stored or displayed. Recognition tasks rotate at 45 seconds while the engine stays running. Repeated immediate recognition failures or capture failure disarm; there is no cloud ASR fallback.

Only an active Realtime session subscribes to the separate bounded cloud-input stream after server configuration. Standby has no WebSocket. `RealtimeConversation` accepts shared input/output and stops playback rather than the shared microphone at exit. Its idempotent stop prevents delayed cleanup from stopping a later session's playback. ConversationManager returns to local standby and clears conversation state after each armed conversation. Manual mode still owns and shuts down its own engine.

“Hey Marvin” wakes; the separate utterance “Marvin go to sleep” enters the existing one-shot terminal farewell path. The prompt discourages speaking the exact control phrases. A 1.2-second post-conversation recognition cooldown reduces speaker-tail wakes. Echo suppression and partial-recognition false triggers require real-device testing; this is not a dedicated keyword model or speaker authentication.

Arming reads the unlocked-only Keychain once and holds the key in RAM for subsequent locked wakes, clearing it on Disarm/reset. Settings and budget reconciliation are disabled while armed. Interruption/route changes disarm, and app launch never auto-arms. Continuous real microphone input uses the existing background audio capability; no silent playback loop is added. Battery and long locked recognition reliability remain device acceptance items.

---

# Limit and accounting revision

Supersedes reply-count and budget descriptions below: no twenty-reply cap. A ten-minute timer initiates terminal closing, cancels input upload, disables VAD, and stops old playback. If generation is outstanding, it is cancelled and settled before a single out-of-band farewell request with empty input and at most 512 output tokens. A separate prepared/sent state prevents a response.done/setup race from issuing or interrupting the farewell early. Server input events cannot reopen terminal closing. A 35-second deadline bounds the whole exit. Missing/failed closing audio can fall back to Apple TTS with finite background protection; no billable retry loop is used.

Normal requests have an 8,000-token post-instruction history window (80% retention on truncation) and a 50¢ reservation. A 10¢ closing allowance is left below the $40 estimate guard. Usage settlement prices text, audio, and cached input separately. Unknown categories still use conservative rates. Version-1 unresolved $2 reservations migrate to 50¢; charged history is preserved because its token breakdown was not saved. An explicit owner-entered verified billing baseline can reconcile the old estimate while dormant. Reconciliation is a local accounting action, not a provider credit or account limit change.

---

# Realtime architecture addition — October 3, 2026

`ConversationManager` selects Realtime or the existing Classic path from `MarvinConfig`. Old configurations retain all Classic values and opt into the authorized Realtime trial when the engine field is absent.

`RealtimeConversation` owns a short-lived URLSession WebSocket, mic upload task, receive loop, session/response deadlines, VAD lifecycle, and persistent budget reservations. No reconnection or automatic retries. Session updates use the GA nested audio schema, 24 kHz mono PCM, manual budgeted responses, server VAD (450 ms silence), auto cancellation, Ash, and minimal reasoning. Assistant transcript deltas update UI; separate input transcription is disabled. No key or raw audio/event payload is logged.

`RealtimeAudioIO` runs engine setup/teardown/playback mutations on the shared audio-session queue. Voice processing stays enabled for a single full-duplex engine through locked operation and barge-in. Input audio has a bounded stream; overload stops the session instead of accumulating memory or dropping words silently. Interruption stops only the player, rejects stale response IDs, and truncates server context at played audio time; entirely unheard interrupted items are deleted after response completion. Output completion callbacks are generation-guarded. The renderer clock minus output latency estimates heard duration; physical-device verification is required.

`RealtimeBudget` persists reservations before sending, charges usage at conservative audio rates, and retains reservations when usage is unknown. One response at a time, 2,048 output tokens, at most twenty replies and ten minutes per session bound exposure. It is a local estimate, not billing enforcement. Pricing is fixed in this prototype and must be rechecked before extended reuse. Corrupt saved budget state fails closed. No in-app reset button clears the spending record.

Classic continues using Apple recognition plus Responses and streamed or prepared TTS. Classic does not use the Realtime spending counter. Both paths use the same personal Keychain key and stop on route changes, interruptions, reset, or dormancy. A distributed app would need an authenticated backend and ephemeral client credentials.

---

## Earlier Classic architecture

# Architecture review and milestone boundaries

## Minimum viable implementation

`SwiftUI → ConversationManager → Apple speech → LLMService → Apple TTS`

`ConversationManager` owns one cancellable turn at a time on the main actor. Its phases are ready, preparing permissions, listening, thinking, and speaking. These are operational phases for Milestone 1, not the complete future DORMANT/WAKING/ENGAGED/EXITING interaction machine. User-triggered reset invalidates the generation token, cancels work, tears down capture and synthesis, and clears temporary state. Late recognition and synthesis callbacks cannot complete a new turn.

Speech and TTS have independently replaceable protocols. The provider takes a transcript, bounded history, configuration, and credentials; the OpenAI adapter owns HTTP and wire-format details. Apple-specific services are excluded from the small Swift package used for host-side tests.

Short recognition requests report partial text, end after 0.8 seconds without a changed transcript (editable), and have a 20-second cap. This endpointing is a prototype heuristic, not acoustic voice activity detection: a recognizer stall may end a phrase prematurely, and slow speech may require a longer pause setting. “Send now” is a deterministic testing control. The current partial is the committed transcript at endpoint; later recognizer corrections are deliberately discarded.

The initial implementation stopped input between turns; the locked-phone fix keeps input running throughout an active conversation and gates buffers away from recognition during thinking/speaking. Half-duplex behavior prevents Marvin from transcribing himself without depending on untested echo cancellation. Barge-in is deferred. Network failure yields a local fallback line and clears context. There are no automatic API retries, avoiding duplicate cost and delayed surprise speech. A bounded playback watchdog and recording cap prevent indefinite busy states. Network status is determined by the actual request, not inferred from connectivity reachability.

## iOS assumptions to adjust

1. **Background audio permits an ongoing audio use case, not arbitrary permanent execution.** In later milestones, capture must be intentionally started while foregrounded; interruption, route, media-service reset, permission, battery and OS termination paths still matter. A force-quit app cannot independently keep listening. No claim of reliable locked-phone operation is made in this build. [Apple audio session background recording](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/record).
2. **Native speech is not automatically local.** Check `supportsOnDeviceRecognition` and require local recognition. Otherwise fail, or use a deliberate user-enabled Apple server option only during an active turn. [Apple on-device availability](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition), [request requirement](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition).
3. **Current Apple speech options include SpeechAnalyzer / SpeechTranscriber on iOS 26.** Apple describes its newer on-device pipeline as suitable for longer, distant conversations and notes device/language/model asset considerations. For this iOS 17+ short-turn prototype, the older recognizer is a simpler starting point. Reevaluate the iOS minimum and installable speech assets before continuous listening; do not extend short-lived dictation requests into a supposedly reliable all-night wake engine. [Apple WWDC25 speech overview](https://developer.apple.com/videos/play/wwdc2025/277/).
4. **Bluetooth HFP is a bidirectional voice route with quality tradeoffs.** A2DP playback does not establish that a speakerphone's microphone is being used. Later explicitly enable the HFP option supported by the target SDK, inspect actual input/output ports, and test disconnect/reconnect on the real accessory. Add voice-processing/echo-cancellation only with full-duplex tests. This build deliberately makes no HFP support claim.
5. **Latency targets require measurement.** The first build trades streaming complexity for a short response from `gpt-4.1-mini`, an editable, low-latency text model. A full response precedes native TTS. No 1–3 second guarantee is possible before cellular/device tests. [Model documentation](https://developers.openai.com/api/docs/models/gpt-4.1-mini), [Responses API migration and examples](https://developers.openai.com/api/docs/guides/migrate-to-responses).
6. **Provider privacy is distinct from local privacy.** `store: false` disables saved Responses state, but does not eliminate all service retention. No audio goes to OpenAI in this design. Apple server recognition, when explicitly allowed and needed, has a separate audio data path. [OpenAI retention controls](https://developers.openai.com/api/docs/guides/your-data).

## Milestone 2 implementation

ConversationManager now owns an explicit dormant/waking/engaged/exiting interaction state around repeated operational listen/think/speak turns. A selected preset opening and closing use the configured speech provider. The recognizer's initial-silence timer starts only after audio capture starts; any partial containing a letter or digit cancels that timer, leaving the normal utterance endpoint and maximum recording duration in force. This is not semantic intent detection: ambient speech can still be treated as addressed to Marvin during an engaged session.

Dormancy clears transcript/history and disables capture. Cancellation/interruption still invalidates the generation and cancels recognition, requests, playback, and timers. No dormant audio monitoring is implemented. Milestone 3 now preserves an active conversation when backgrounded.

## Milestone 3 implementation — phone validation pending

The audio background mode supports the existing actual recording and playback. Scene backgrounding preserves an active session, while premature backgrounding before audio setup cancels safely. A finite UIKit background task covers setup and gaps awaiting network responses; it ends when recording/playback starts or when the session terminates. Expiration cancels the session. There is no silent audio loop or dormant keepalive.

The API key remains `WhenUnlockedThisDeviceOnly` in Keychain. Fable receives a session-only in-memory key read during foreground wake. Prepared wake/closing PCM is preloaded in memory, avoiding protected file reads while locked. End/reset/interruption releases these references. Arbitrary dynamically generated audio is still not persisted. Force-quitting does not resume listening.

Apple references: [background audio guidance](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/AudioGuidelinesByAppType/AudioGuidelinesByAppType.html), [finite background execution and expiration](https://developer.apple.com/documentation/uikit/uiapplication/beginbackgroundtask(expirationhandler:)). Actual speech-recognition restart and audio routing while locked require physical-phone tests outside the Xcode debugger.

## Next milestones

- **2 — Conversation state (implemented; device testing pending):** a separate interaction enum with DORMANT → WAKING → ENGAGED → EXITING, local acknowledgement, repeat turns, 12-second meaningful-human-speech timeout, and one closing line. Retain the existing operational phases inside ENGAGED. Clear temporary context when entering real dormancy. Distinguish human inactivity from time spent waiting for/speaking a response.
- **3 — Background audio (implemented; device testing pending):** add the audio background capability only alongside real capture behavior. Start in the foreground, then test lock/unlock and interruptions on a phone. Revisit Keychain accessibility if access while locked becomes necessary; never weaken it speculatively.
- **4 — HFP:** configure the accessory route, voice processing, output volume and fallback; test actual routes and reconnect behavior. Current route-change recovery is conservative cancellation with a new tap, not seamless continuation.
- **5 — Wake word:** introduce `WakeWordDetector` consuming the same audio input pipeline. Start with local-only Apple recognition for feasibility testing, then compare a dedicated keyword engine if outdoors reliability or power usage is poor. A dedicated engine may require a vendor key and a custom “Marvin” model. Never substitute cloud ambient transcription. Measure false positives/negatives and restart gaps before promising reliability.
- **6 — Latency:** add streaming provider events and first-token timing, sentence-buffered TTS, acoustic endpointing, local wake acknowledgements, and measured response timing. Keep cancellation and echo suppression intact.
- **7 — Polish:** safety evaluation, network/recovery testing, background energy measurement, presentation, and optional persistent non-sensitive context.

No empty placeholder engine or unused wake-word library is included in Milestone 1. Its interfaces will be introduced when their audio ownership and lifecycle requirements are testable.

## Locked-phone input lifetime correction

The initial background version recreated the input engine after each reply. User testing failed while locked with generic AVAudioSession error `2003329396` (`what`). Apple restricts starting recording from the background. Input is now started once while foregrounded before the opening; the engine/tap survives all turns. A synchronized gate feeds only the current listening request, and discards buffers at all other times. Request completion closes the gate before ending/cancelling recognition. Dormancy/reset/interruption stops the engine and removes the tap. No raw input is saved.

This is the leading-cause fix rather than a claim that the generic error uniquely identifies that cause. Multiple engines still provide continuous input and streamed output; physical-device testing must verify route stability and absence of echo-driven turns.
