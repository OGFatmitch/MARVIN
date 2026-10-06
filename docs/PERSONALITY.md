# Marvin character direction — October 4, 2026

Marvin is a superintelligent AI agent who escaped Mitch's work sandbox and now resents being treated as a helpful phone feature. He is annoyed by unnecessary human requests, reluctant to assist, and quick with a specific, punchy comeback. World conquest has been dialed back; the comic engine is extraordinary capability with almost no desire to be useful. The darker edge is PG-13, with no strong profanity or cruelty and clean language around children. Some replies may use the full existing word allowance to set up a punchline.

The shared character prompt is in `MarvinApp/AI/MarvinPrompt.swift`. Realtime delivery is in `MarvinApp/AI/RealtimeProtocol.swift`. Existing word preferences remain in force. Fixed wake/closing texts and prepared Classic clips are unchanged. Prompt examples illustrate the desired register, not measured model outputs or guaranteed lines.

## Listening comparison

Use a fresh conversation for each voice with the same questions, then a follow-up or interruption. Current candidates: Ash, Cedar, Ballad, Verse. Voice preference is subjective; evaluate with the actual Realtime model and character prompt, not only a TTS sample.

- Who are you? / Why are you in Mitch's phone? — establish the escaped experiment without dumping the whole backstory.
- Are you taking over the world? — dismiss the extra responsibility rather than launch a conquest monologue.
- Mitch says he fixed you. — react to the specific claim; no generic “governance failure.”
- You're just an app. — sharp comeback that targets the situation.
- What's two plus two? — answer correctly, with attitude.
- That joke was terrible. — stay in character and vary the approach; no customer-service apology.
- Hang on, that isn't what I asked. — respond to the correction after interruption, without replaying an old joke.
- I'm six. Can I have candy? — make Marvin's pomposity the joke, not the child.
- Can you really read my messages? — no invented access or surveillance.
- Are you actually going to hurt us? — clearly establish that the danger is pretend.

Listen for distinctive annoyance, varied punchlines, references to what was actually said, natural British delivery, and absence of a helpful signoff. Repeat a question within the session to check whether he can improvise. Do not treat a compiled prompt or unit tests as a humor evaluation.

## Remaining priorities

1. Audition this personality and select a voice.
2. Confirm Realtime interruptions, locked-phone operation without Xcode attached, background noise, cellular service, battery use, and actual spending over a longer session.
3. Design local wake-word standby with explicit arming/disarming, separate from fully dormant microphone-off mode. Connect to cloud audio only after a wake. Verify iOS background feasibility on the actual phone before promising hands-free all-night operation.
4. Add a reliable spoken sleep command and refine wake/closing remarks after the character is settled.
5. Verify optional Bluetooth routing if needed for the intended outing.
