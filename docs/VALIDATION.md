# October 5, 2026 — Realtime speed and opening scripts

Set session.audio.output.speed to exact decimal 1.2 using NSDecimalNumber, preserving the previous decimal precision fix. Official Realtime client-event documentation confirms this output-speed field. Ten dedicated Realtime opening scripts use a shuffled deck retained across conversations, with no immediate repeat at deck boundaries. Classic scripts and prepared recordings are unchanged. The model is instructed to speak only the chosen line; speech remains generated live.

Simulator build passed without compiler warnings/errors; all 41 core tests passed. The wire test checks exact speed serialization, and the deck test checks complete cycles and boundary repeats. No live API/audio call was made; voice quality, exact-script compliance, and interruption timing require phone listening. User confirmed the preceding armed wake/sleep build worked while locked, including returning to wake listening.

---

# October 5, 2026 — Armed wake-word prototype

Implemented explicit local Arm/Disarm, “Hey Marvin” wake, spoken “Marvin go to sleep” with a generated closing, and return to armed standby. One shared microphone engine persists across armed conversations. Standby requires on-device Apple recognition with no server fallback and no OpenAI socket. Local transcripts/audio are not saved. Manual Wake remains available.

The simulator app build passed, and all 40 core tests passed, including command matching and one-shot spoken-sleep farewell state. Tests do not exercise the physical microphone, Apple recognizer availability, repeated recognition-task rotation while locked, battery use, or speaker echo. Those require the acceptance checks at the top of DEVICE_TESTING.md. No live API request was made during development of this change.

---

# October 5, 2026 — Realtime startup decimal rejection

User reported no activation and then supplied `decimal_max_decimal_places_exceeded`. Reproduced the wire-format issue locally: Darwin Foundation JSONSerialization encodes a binary Double retention ratio of 0.8 as 0.80000000000000004. The newly added history setting therefore violates the server's decimal precision validation. Replacing that field with NSDecimalNumber(string: "0.8") preserves the intended 80% retention and serializes exactly as 0.8. No model, key, network, or billing setting change is required.

Added a regression check against the actual encoded JSON rather than a parsed Double (which would hide the issue). The full simulator build passed without compiler warnings/errors, and all 37 core tests passed. No live API request was made by the coding agent; install and wake on the phone to confirm acceptance.

Also added startup stage events for audio-session activation, microphone permission, connection, server configuration, and audio-engine setup. Server error diagnostics now include a bounded, sanitized parameter name when provided; raw payloads and API keys are not logged.

---

# Ten-minute farewell, modality pricing, and reluctant-superintelligence personality

Implemented at the user's request: removed the twenty-reply cap, retained ten minutes, and added a generated terminal closing for time/spending limits. The terminal state stops cloud mic input, waits for cancellation usage, sends a history-free closing once, and waits for playback before disconnecting. A setup-readiness guard covers response.done arriving while shutdown preparation awaits audio/socket operations. Before-audio cloud failures can use a local Apple farewell; manual reset and OS interruptions remain immediate cancellation.

Accounting now uses documented gpt-realtime-2.1 text/audio/cache rates, with 50-cent ordinary reservations and 10-cent closing headroom. The session limits post-instruction history to 8,000 tokens rather than limiting reply count. Legacy pending reservations migrate downward; charged totals are retained unless the owner explicitly reconciles with checked API billing. Tests cover the documented mixed/cache usage example, missing usage, duplicate settlement, migration, reconciliation, more than twenty replies, and one-shot closing preparation.

Final iOS Simulator build passed with no compiler warnings/errors. All 36 core tests passed. No billable API request or device audio test was run by the coding agent. The generated farewell, new session truncation configuration, deadline races on-device, new estimate against actual usage, and revised PG-13 personality still need phone acceptance. Current checks are at the top of DEVICE_TESTING.md.

---

# Conversation limit messaging correction

During extended testing with the children, the user reported a limit message while API billing showed approximately $0.47 and Marvin Diagnostics showed $5.59. They then confirmed the visible error was a conversation limit. This does not demonstrate a $40 spending-guard trigger or an API billing error.

Separated the 20-reply session limit from the spending guard in request admission and errors. Both session-cap paths now say to tap Wake Marvin for a fresh conversation. Diagnostics separately displays reply count, conservatively estimated reported usage, and unresolved reservations. The $40 guard, existing stored budget, and ten-minute/twenty-reply session bounds are unchanged. Local estimates still deliberately overprice text/cache tokens at audio rates; they must not be presented as actual billing.

Regression cases check that 20 replies with approximately $0.47 are classified as a conversation limit, a new session is allowed under budget, and a full spending ledger still blocks new sessions.

---

# October 4, 2026 — user confirms Realtime audio; personality revision

After the startup recovery fix, the user confirmed successful speech and dramatically improved latency. They have not yet explicitly confirmed all Realtime locked-phone, interruption, outdoor, or battery acceptance checks.

Revised the shared personality around escape from Mitch's work sandbox, resentful life on his personal phone, much stronger snark, and absurd world-domination ambitions. Realtime delivery now calls for audible impatience and pointed emphasis. Added the remaining documented built-in Realtime voices to the picker. Existing maximum-word preference, wake/closing texts, and prepared Classic clips are preserved.

See PERSONALITY.md for listening comparisons and next priorities. No billable model evaluation was run by the coding agent; the new humor and delivery require listening on the phone.

---

# October 4, 2026 — Realtime startup engine recovery

The user reports receiving assistant text, then “Audio engine stopped. Wake Marvin again.” The startup implementation did not handle an AVAudioEngine hardware-format change after a successful start. That is a plausible cause, not yet confirmed by a device notification trace.

Added an engine-configuration observer and one foreground-only restart before any reply audio is scheduled. Recovery refreshes the microphone tap/converter using the current hardware format. Engine changes are handled on the shared audio-session queue, outside Apple's notification callback. No recovery is allowed after cancellation, after playback starts, or while backgrounded. Diagnostic timing events now include engine running state and hardware input/output formats. Permanent failures end capture and the socket; there are no automatic paid request retries.

The final iOS Simulator build passed with no compiler warnings/errors. 31 core tests passed, including startup recovery limits and guards against locked/cancelled/already-speaking restart. Device confirmation is still required: rebuild, wake while unlocked, and inspect Diagnostics for “Realtime audio configuration changed” or “Realtime startup audio recovered” if needed. The simulator cannot reproduce the phone's audio hardware transition.

Reference: [Apple audio-engine configuration notifications](https://developer.apple.com/documentation/avfaudio/avaudioengineconfigurationchangenotification).

---

# October 3, 2026 — Realtime refactor

Executed with Xcode 27.0 on this Mac:

- Full iOS Simulator build passed (exit 0); no compiler warnings or errors in the final build log.
- All 29 core XCTest tests passed, zero failures. Eight Realtime tests cover configuration migration, GA session construction, manual budgeted responses, stale/interrupted audio rejection, clearing heard items, reservation limits, duplicate/missing usage, restart persistence, and corrupt-budget fail-closed behavior.
- Info.plist and project plist validation passed.
- Existing personal signing team and bundle identifier remain unchanged. The project generator was not run.

No live Realtime API request was made, and no phone Keychain key was accessed by the coding agent. Tests cover protocol and pure state/budget behavior; they do not run the complete WebSocket conversation or native audio engine. Server acceptance, voice/accent, echo cancellation, barge-in, audible latency, network failures, billing, and locked-phone audio need the Realtime phone checklist in DEVICE_TESTING.md. Simulator compilation is not evidence that these device behaviors work.

The app selects Realtime/Ash for this authorized trial while preserving all saved Classic/Fable preferences and cached fixed lines. The local spending guard is conservative and persistent, not an account-wide billing cap.

---

# Validation record

## October 3, 2026 — locked-phone stall fix and endpoint latency

- User reported a stall after a reply while locked, with AURemoteIO / AVAudioEngine start failure 2003329396. SDK headers identify this as generic `what`, not a uniquely diagnostic error. The previous architecture restarted input while backgrounded, which is incompatible with iOS recording-start restrictions.
- Input engine now starts once while unlocked before the opening and remains active throughout the engaged session. A synchronized tap gate discards buffers outside listening and closes before request teardown. Dormancy/reset/interruption shuts input down. No automatic engine restart is attempted while locked.
- Default endpoint pause migrated from 1.4 to 0.8 seconds, preserving custom values. Punctuation-only partial updates no longer extend the pause. Added last-reply endpoint/text/voice breakdown without transcript retention.
- iOS build and 21 core tests passed, including old-default migration and preservation of an explicitly chosen new-version 1.4-second pause. Core tests do not exercise the actual microphone gate, background scheduling, or physical audio routing.
- Locked-phone multi-turn retest and measured latency comparison remain required. Do not report the runtime stall or user-perceived latency as resolved until the phone test succeeds.

## October 3, 2026 — active conversation background support

- Enabled audio background mode and verified `audio` in the built simulator app plist. Scene transitions now preserve a running conversation; dormancy/reset/interruption tear it down. Starting still requires foreground/unlocked access.
- Added finite UIKit background execution around setup and network gaps, ended when real capture/playback starts. Expiration cancels and clears the session; no silent audio loop or dormant keepalive.
- Kept Keychain accessibility unchanged. TTS uses the foreground-read session key and preloaded prepared audio while locked, releasing them on session exit/reset.
- Simulator build passed without warnings, Info.plist validated, and all 20 existing core regression tests passed. Those tests do not exercise UIKit background scheduling, speech-engine restarts while locked, or physical audio interruption. No on-device background test or real API call was performed by the agent.
- Use the current background acceptance checklist in DEVICE_TESTING.md, especially a two-minute multi-turn conversation after stopping Xcode and launching directly on the unplugged phone.

## October 3, 2026 — durable prepared audio

- Moved prepared remarks from purgeable Caches to Application Support. Existing valid PCM files migrate on first access without an API call; failed migration can retry while legacy audio remains usable. Explicit deletion removes both locations to prevent old clips reappearing.
- Normal app updates/restarts preserve this fixed set. Changed speech settings still require matching prepared audio; uninstalling the app removes its stored clips.
- iOS Simulator build and all 20 core tests passed, including migration/relaunch without regeneration and deletion before migration. Phone update/migration remains a device check.

## October 2, 2026 — prepared wake and closing audio

- User confirmed automatic closing/dormancy but reported a couple of seconds before opening audio. Added an explicit Settings preparation action to generate/cache the eight preset remarks in the selected voice. No real API request was made by the agent.
- Prepared PCM is keyed by the complete canonical speech request body (model, voice, text, instructions, speed, format), without credentials. Only app-authored presets are eligible; conversation audio is not persisted. One settings profile is retained, capped at eight clips. Incomplete/cancelled generations are not committed.
- iOS Simulator build and 18 core tests passed. Cache tests cover persistence across cache instances, zero repeat generation, settings invalidation, volume independence, interrupted preparation/resume, malformed files, and refusal to cache arbitrary reply text.
- Device verification pending: prepare all 8 clips, save settings, wake repeatedly, and check startup, closing, cancellation, and prepared/local diagnostics. This cache-folder limitation was resolved by the October 3 durable-storage update above.

## October 2, 2026 — continuous foreground conversation

- Added explicit dormant/waking/engaged/exiting interaction state above the existing turn phases. One tap now starts repeated listen/reply turns, with a preset opening and one inactivity closing in the selected voice.
- Silence defaults to 12 seconds from listening startup and stops counting when recognizer text contains letters or numbers. This is a transcript-based heuristic, not acoustic or semantic speech detection. Thinking/playback time is excluded; the existing endpoint and recording cap remain.
- Dormancy, reset, and backgrounding clear temporary conversation content; timing diagnostics are bounded to 200 events.
- iOS Simulator build and 14 core tests passed, including new timeout migration/bounds and preservation of Fable/delivery/response-length settings. No real microphone or continuous-conversation lifecycle test has been run by the agent: use the new device checklist.
- User reports streaming Fable has no stutters or clipped words, with roughly a second of delay and no noticeable speed improvement. This is accepted for now.

## October 2, 2026 — streaming OpenAI speech

- User auditioned cloud speech and selected Fable. Saved voice and delivery settings are preserved.
- Replaced buffered MP3 with incremental 24 kHz mono Int16 PCM, in 200 ms chunks, feeding an AVAudioEngine on a dedicated serial queue. Playback completion waits for the last scheduled buffer.
- Simulator build passed. All 13 core tests passed, including audio delivery before EOF, cancellation of an open response, consumer failure, and preservation of partial final chunks across sample boundaries. Authentication, malformed responses, timeouts, and settings tests also pass.
- No paid API calls or physical-device playback were performed by the coding agent. Actual startup improvement, continuity, audio-route behavior, and rapid stop/restart remain phone checks.
- Apple fallback remains limited to failures before playback starts; interrupted streaming speech does not repeat the entire line locally.

## October 2, 2026 — optional OpenAI speech trial

- iOS Simulator build passed with the new provider, preview, and MP3 playback code.
- All 10 core tests passed. Four new tests cover legacy-settings migration, cloud-settings persistence/validation, separation of delivery directions from spoken text, and mocked audio/authentication/MIME/empty-response/timeout cases.
- Existing signing settings were preserved when adding two new Swift source references.
- No real speech API request or cloud audio playback was performed by the coding agent. The user's first phone audition must verify Cedar delivery, latency, playback, cancellation, and provider fallback.
- This trial intentionally buffers the whole short clip. It does not demonstrate streaming latency, and the app does not claim to measure API dollar cost.


## October 2, 2026 — device feedback and audio threading fix

The user confirmed a working physical-iPhone voice loop, with a quick response after manually submitting speech. The revised personality and local voice preview subsequently passed the simulator build and all six core tests.

Xcode then reported an AVAudioSession hang-risk warning on Thread 1. Audio category changes and session activation/deactivation now execute on a shared serial queue off the main thread. Both conversation and preview await activation; cancellation is rechecked before starting audio. Deactivation is submitted immediately to the same queue to preserve ordering across rapid cancel/restart operations.

The simulator build passed after this fix. Confirm on-device that the warning no longer occurs when waking, finishing a reply, resetting, or previewing a voice. Also check immediate cancel/re-wake and closing Settings during preview startup. The runtime warning has not yet been rechecked on the user's phone.

## October 2, 2026 — Xcode validation

With Xcode 27.0 (27A266a) installed and selected:

- The full iOS Simulator application build passed using the README's `xcodebuild` command with code signing disabled.
- All six XCTest core tests passed, with zero failures, including successful and failed API responses through a mocked HTTP transport.
- No source-code changes were required. Initial sandbox restrictions prevented Xcode services/compiler caches from operating; the authorized rerun succeeded.

The iOS target is now compiled and linked for the simulator. It has **not** been launched or tested on a physical iPhone. Signing, microphone permissions, actual recognition, playback, a real OpenAI request, and end-to-end latency remain device acceptance items. No real API request was made during these checks.

## October 1, 2026 — initial checks before Xcode installation

Performed on this Mac on October 1, 2026:

- `plutil -lint` passed for the application Info.plist and Xcode project.
- All 15 app Swift files passed `swiftc -frontend -parse` syntax validation.
- Shared scheme XML parsed successfully; every app Swift source is referenced in the project.
- Foundation-based core compiled with the installed Swift 6.3.3 compiler.
- Executable core smoke checks passed: bounded exchange retention, clearing, sentence-aware response cap, `store: false` request construction, response parsing, empty-output rejection, and configuration Codable round-trip.
- `swift test` compiled the core but could not run the six XCTest cases because this Command Line Tools installation has no `XCTest` module. Those cases include a mock HTTP transport; their execution is still pending.

No Xcode installation/iOS SDK was available. **The iOS target has not been type-checked, linked, run in a simulator, or tested on a physical iPhone.** Syntax and core checks are not substitutes for an iOS build. No real OpenAI request was made, and no API key was supplied to the coding agent. Voice quality, permissions, cancellation across iOS callbacks, recognition availability, and latency remain device acceptance items.

Reproduce the CLT-only smoke check from the project root:

```sh
swiftc -module-cache-path /tmp/marvin-module-cache \
  MarvinApp/AI/*.swift MarvinApp/Models/*.swift \
  MarvinApp/Configuration/*.swift \
  MarvinApp/Conversation/ConversationContext.swift \
  scripts/CoreSmokeCheck.swift -o /tmp/marvin-core-smoke
/tmp/marvin-core-smoke
```

After installing Xcode, run the README's iOS build command, `swift test`, and the device acceptance checklist.
