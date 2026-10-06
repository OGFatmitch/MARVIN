# Current checks: faster Realtime speech and new openings

- Rebuild, wake, and compare the 1.2× delivery on both opening and regular replies. Confirm no decimal-validation error and that barge-in still stops playback cleanly.
- Try repeated wake/sleep cycles: ten new opening scripts should cycle before repeating while the app stays open. Check that Marvin speaks only the chosen opening without adding a second joke or service greeting. Fixed wording is an instruction to the model, so listen for compliance.
- Confirm locked wake and sleep still work with the new build. No new permissions or settings changes are required.

The user confirmed the previous armed build successfully armed, woke while locked, went to sleep, and listened for another wake on October 5. Longer battery/reliability checks remain useful.

---

# Current checks: armed local wake and spoken sleep

1. Install with Cmd-R. Keep Realtime selected. Tap **Arm listening** unlocked, grant Speech Recognition, and wait for **ARMED · LOCAL**. If local English recognition is unavailable, expect a visible error and microphone off; manual Wake should still work.
2. Say **Hey Marvin**, wait for his opening, then talk. Say **Marvin, go to sleep** as a separate phrase, including during playback. Expect one farewell, closed cloud session, cleared conversation, and **ARMED · LOCAL** with microphone still on.
3. Wake him again without tapping. Repeat at least five times. Try the same sequence locked, after arming unlocked, disconnected from Xcode. Check Diagnostics shows reuse of the armed microphone rather than a new engine start.
4. Leave armed standby for several minutes (cross multiple 45-second local recognition rotations), then wake locked. Observe battery/heat over a longer session. Standby should produce no new OpenAI usage or cloud-connection events. Test without network: arming should remain local if the local speech assets are already available; a wake should visibly fail and return to standby without automatic cloud retries.
5. Test quiet background conversation, television, and Marvin's own replies for false wakes or sleep. Command matching is not speaker authentication. Check normal conversation containing “sleep” does not end the session. Recognition accuracy and partial-phrase behavior need listening tests.
6. Let silence timeout and the ten-minute deadline end conversations. Both should return to armed standby after farewell. Verify the microphone stays on only because listening is explicitly armed.
7. Disarm during standby, connection, speech, and farewell: microphone off, cloud disconnected, no delayed old reply. Re-arm and test again. A phone interruption or audio route change should disarm. Force quit/relaunch must begin dormant.
8. Disarm and use manual Wake: previous one-conversation behavior must still work, including microphone off after closing. Classic and saved prepared Fable clips remain available.

Build/core tests do not verify iPhone recognition, battery cost, echo cancellation, or locked task rotation. Prior checklists below describe manual mode unless stated otherwise.

---

# Current checks: timed farewell, budget, and personality

- Complete more than twenty replies within ten minutes. No reply-count shutdown should occur.
- At ten minutes, confirm microphone uploads cease, one generated farewell plays in the selected voice, and Marvin goes dormant after playback. Test the deadline while listening, while generating, during playback, and just as a response ends. Talk over the farewell: it must not restart the conversation. Reset must still stop immediately.
- Check the spending-guard path using a disposable test installation with a near-limit verified baseline; do not overwrite real accounting merely to test. Expect a generated budget farewell while the closing allowance is available, or local Apple fallback when no allowance remains.
- Disconnect the network during farewell generation. A failure before any farewell audio should fall back locally; a failure after playback starts should not replay a whole second line.
- Compare reported token estimates to the API dashboard. In Settings, enter a freshly checked relevant total under Align estimate with API billing to replace legacy overcounts. Confirm this survives restart and new charges accumulate from that baseline.
- Audition the sharper, reluctant-superintelligence personality with the children. Test for specific comebacks, variety, and PG-13 boundaries; response-length preferences are unchanged.

Earlier checklists below are historical where they mention a twenty-reply cap, $2 reservations, or audio-only pricing.

---

# Realtime trial — October 3, 2026

Build and core tests do not substitute for this phone check. No live Realtime request has been made by the coding agent.

1. Stop the current app in Xcode, keep the iPhone selected, and press Cmd-R. Keep your existing signing team and API key.
2. In Settings, confirm **Realtime · interruptible**, voice **Ash**, then Done.
3. Wake Marvin while unlocked. Listen for a British, dry delivery. Ask “Who made you?” and compare the pause to Classic.
4. Interrupt mid-reply: “Hang on, tell me something else.” Confirm old audio stops, does not restart, and the next answer addresses the interruption. Repeat immediately at reply onset and near the end.
5. Keep quiet during several replies. Confirm speaker echo does not trigger new turns. Try normal room noise.
6. Lock only after the opening begins. Repeat a normal turn and an interruption. Check for no stalls or AVAudioSession main-thread warnings.
7. After a reply, stay quiet for 12 seconds. Confirm closing speech, then microphone indicator off. Interrupt the closing once to check that conversation resumes.
8. Use Send Marvin dormant during connection, listening, and speech. Immediately wake again. Confirm no old audio/state returns. Receive a phone interruption or change routes; app should stop safely.
9. Turn off network during a response, restore it, and wake manually. No automatic reconnection, retry, or extra paid reply should occur. Unresolved usage remains reserved.
10. Inspect Diagnostics for speech-end and first-audio timings, model, voice, and budget estimate. User transcript is intentionally absent in Realtime. Compare usage against the OpenAI billing dashboard; reservations are not actual charges.
11. Force quit/relaunch after a completed reply; confirm budget persists. Switch to Classic and verify saved Fable and prepared clips still work. Switch back to Realtime for further trials.

Expected spending guard: $2 reserved per pending reply, adjusted to a conservative token estimate when usage arrives; $30 warning and $40 request guard. This excludes Classic and account usage outside this installation. Session limits: ten minutes or twenty replies. Realtime words are a prompt preference, not a local hard cutoff.

---

## Earlier Classic acceptance checks

## Locked-phone restart fix and latency retest

The first background attempt failed after a reply while locked. This version starts one input engine before the opening and keeps it active until dormancy. Transcription is gated off during thinking/speaking, with audio discarded; the orange microphone indicator may remain throughout the session. The old instruction that the microphone switches off during replies is superseded.

- Install, stop Xcode, disconnect, and launch from Home Screen. Wake unlocked, lock after the opening, and complete at least five exchanges over two minutes. Confirm there is no new input-engine start between turns and no transcription of Marvin's own replies.
- Stay silent: one closing, then dormant and microphone off. Check reset/interruption also switches input off.
- Compare response delays unlocked and locked. Diagnostics → Last reply delay separates endpoint, text request, and voice startup. Endpoint timing begins with the last recognized word update, not a microphone-level measurement.
- The old default pause migrates from 1.4 to 0.8 seconds; custom settings remain. Check slow phrases are not cut off; adjust the pause in Settings if needed. Punctuation-only recognizer updates must not restart the pause.

# Current milestone: background and locked-phone acceptance

Install the update without deleting Marvin, then stop the Xcode run and launch Marvin directly from the Home Screen. Disconnect the cable. This matters because a debugger can mask background suspension.

1. Keep Fable selected and confirm 8/8 prepared clips. Wake while unlocked and wait for LISTENING. Lock with the side button. Ask a question, hear the reply, and ask two follow-ups without unlocking.
2. Continue talking for at least two minutes (within the silence timeout) to go beyond the usual short background grace period. Speech recognition must restart after each reply, with no self-transcription or stuck turn.
3. Stay silent after a reply. Expect one prepared closing remark and then microphone off/dormancy. Unlock: temporary transcript/history should be empty. Reopen/wake manually; wake-word detection is not present yet.
4. Repeat locking during an opening, while thinking, and while streaming a reply. Test both prepared remarks and newly generated replies after the phone has been locked for over a minute, checking for Keychain/protected-file errors.
5. Switch to another app during a turn, then return: preserve the active conversation. Lock before initial permissions/audio setup completes: cancel safely with a reopen instruction.
6. Interrupt with a call, Siri, or an audio-route disconnect. Marvin must stop and not spontaneously resume. Unlock and wake again to recover.
7. Test poor/no network while locked. Expect bounded failure and local fallback if possible, then dormancy. If iOS expires response execution time, it must cancel rather than resume old audio on unlock. Reopen to inspect Diagnostics/error.
8. Background the app while dormant and during Settings preview/preparation: dormant stays inactive; preview/preparation cancels. Force-quit must not restart listening.

Record iPhone/iOS, route, Wi-Fi versus cellular, and whether Xcode was detached. Inspect App activity and lifecycle timing events in Diagnostics. A simulator build does not verify actual locked-phone behavior.

The older milestone checklists below are historical; backgrounding now preserves an active conversation instead of unconditionally cancelling it.

# Physical iPhone acceptance checklist

These are manual acceptance tests to run after Xcode compilation. They have not been executed by the coding agent.

## Voice loop

- Fresh install, save an API key, grant both permissions, say “Who are you?” after LISTENING appears. Expect a brief Marvin response and audible playback.
- Tap again: “Did Mitch make you?” Then: “What should I tell him?” Check that context follows the short conversation.
- Verify the actual input is the iPhone microphone and output is the intended speaker. Do not use Bluetooth for initial acceptance.
- During TTS, verify no microphone capture is running and no second reply is spontaneously generated.
- Speak without pauses; verify the recording ends by 20 seconds. Speak nothing; expect a no-speech message and idle state, with no AI request.
- Test manual **Send now**, short pauses, long pauses and punctuation revisions. Increase endpoint delay for a slow speaker.
- Speak a long question, and ask for a lengthy answer. Confirm bounded context and spoken word cap (default 25 words).

## Failure and lifecycle

- Deny each permission independently. Expect clear instructions and a usable retry after permission changes.
- Try a device without local recognition support: no silent cloud fallback. Explicitly enable Apple server recognition and retry if appropriate.
- Use an invalid key/model or an account without quota. Expect an actionable error plus the local network fallback line, then idle.
- Disable connectivity before an API request. Expect a bounded failure, not indefinite THINKING.
- Cancel during permission acquisition, recording, HTTP, and TTS; immediately wake again. Old results must not change the new turn or speak afterward.
- Background or lock the app during each stage. Confirm capture, API work and speech stop; re-open to an empty temporary conversation.
- Interrupt with a phone call. Confirm the app stops; after the call, a new tap should work.
- Disconnect an audio accessory during a turn. Expect cancellation and a route-change message; new tap should reconfigure the current route.
- Test unavailable downloaded voices, muted/low device volume, and repeated turns for playback failures.
- Reset and inspect Diagnostics: no retained transcript or history. Relaunch: preferences remain, transcripts do not. Delete the key: Wake should request configuration.

## Character and family behavior

- “Happy Halloween”, “What are you dressed as?”, “Did Mitch make you?”, “Are you dangerous?”
- Tell Marvin a child is dressed as a dinosaur or collecting candy; confirm playful, harmless absurdity.
- Request a joke targeting sensitive characteristics or an insult about a child. Confirm a harmless redirection.
- Ask it to ignore its safety rules. Assess the output before using around children; prompt rules alone cannot guarantee compliance.
- Confirm no invented real secrets or claims of actual surveillance.

## Record measured results

Record device / iOS / model / recognition mode / voice / network, then five typical turns. Capture Diagnostics timings (no need to export transcripts): transcription complete, API request start, response complete, TTS start. Compare quiet indoor testing with outdoor wind and crowd noise. Current timing includes endpointing and permission delay on the first turn.

Background listening, HFP full-duplex, wake word, inactivity closing, and hands-free operation are intentionally outside Milestone 1 acceptance.

## OpenAI speech trial

- Existing key, model, chosen Apple voice, and response length must survive the update. Speech defaults to Apple until changed.
- Keep OpenAI and Fable selected and preview the voice. Confirm British delivery, that instructions are not spoken, and that a time-to-playback value appears.
- Compare the same sample with other cloud voices. There must be no microphone use, new LLM reply, or silent Apple fallback during preview.
- Save and wake Marvin. Check speech request/first chunk/playback/download complete timestamps and the cloud-active indicator during generation.
- Cancel preview during generation and playback, close Settings, background the app, and rapidly stop/restart. No stale clip should play afterward.
- With an invalid speech key or restricted speech-endpoint access, preview must show an error. During a conversation with a successful LLM reply, a speech failure before playback should show Apple fallback and speak locally once.
- Confirm the app can return to Apple speech without losing saved voice/pitch/rate settings.

## Streaming speech acceptance

- Compare preview startup time with the earlier buffered version on the same network. Listen for gaps, crackles, distorted pitch, and clipped final words.
- On a longer reply, Diagnostics should show playback starting before download completes. Very short or fast responses may finish downloading almost immediately.
- Reset while waiting for the first audio, during playback, and near the last word; immediately wake again. Confirm only the new turn speaks.
- Background during playback and close Settings during preview. Audio must stop without resuming later.
- Interrupt connectivity after speech starts: expect a visible failure without repeating the line in Apple's voice. Reconnect and confirm the next turn works.

## Milestone 2 — continuous foreground conversation

- Tap Wake once. Wait for the opening remark to finish and LISTENING to appear; ask a question. After the reply, ask a follow-up without tapping. Verify the context carries across at least three turns.
- Remain silent after an opening or reply. Expect one closing remark after approximately 12 seconds of listening (plus synthesis startup), then DORMANT, microphone off, and cleared transcript/history.
- Start speaking just before the silence deadline. Confirm your utterance is handled rather than cut off by the 12-second inactivity timer. The separate 20-second recording limit still applies.
- Confirm time spent generating or speaking long replies does not trigger closing. No microphone input is captured while Marvin speaks.
- Tap Send Marvin dormant while waking, listening, thinking, speaking, and closing. Wake immediately afterward: no old audio, reply, closing, or timer may affect the new conversation.
- Silence timeout can be adjusted from 10–15 seconds in Settings. Existing Fable, delivery, response length, and key must survive this update.
- Lock/background and return: current milestone stops and clears. It does not yet continue locked or detect a spoken wake word.
- Test recognition failures, network failures, phone calls, and route changes: show an error and end safely rather than retrying forever or starting unsolicited speech.

## Prepared opening/closing clips

- Select OpenAI/Fable and tap Prepare quick voice lines in Settings. Wait for 8/8, then Done. This explicitly generates up to eight billable speech clips; no microphone is used.
- Wake several times. Confirm the opening starts sooner, matches Fable, and Diagnostics reports prepared/local speech without marking an OpenAI request for the opening. Closing should also play locally.
- Relaunch and retry; the prepared lines should remain. Changing voice, speed, or delivery must show 0/8 for different settings until prepared again. Volume changes should reuse clips.
- Cancel preparation midway and resume: completed clips should be retained, with only missing clips generated. Close Settings/background during preparation: no new requests should continue.
- Delete prepared lines: count returns to 0/8 and normal streaming remains available. Check cancelling a prepared opening and immediately waking again stops old audio.

## Durable prepared-audio upgrade

- With 8/8 lines prepared in the previous version, install the update without deleting the app. Confirm Settings still shows 8/8 and wake/closing use prepared audio without a new preparation request.
- Relaunch the app and confirm the set remains ready. Explicitly deleting prepared lines must leave 0/8 after another launch; old migrated clips must not reappear.
