# Initial implementation status

Implementation is under way, with a runnable native shell, real OS sampling, provider HTTP adapters, bounded local-session parsing, a private CLI bridge and an experimental separate BTT preset.

## Verified 2026-10-14

- ARM64 debug and optimized builds compile and launch as a real menu-bar app bundle. An Intel `x86_64-apple-macosx13.0` cross-build also compiles; Intel runtime behavior has not been tested.
- All 15 authored boundary cases pass through `script/test.sh`: quota decoding, missing/invalid values, last-turn vs lifetime tokens, stale context, exact-chat/revision guards, private socket ownership and round-trip, bounded recent discovery, and local WebSocket native-compaction fixtures (completion before/after acknowledgement and busy-session rejection).
- Native UI inspection covered demo quota cards, chat selection, disabled demo compaction, live CPU/RAM readings, settings, and disabling/re-enabling sampling. Provider and local-session access were off during live UI verification.
- Optimized installed core file payload: **2,108,323 bytes** (about 2.01 MiB); separate Touch Bar ZIP: **2,428 bytes**. Filesystem allocation and downloads with different signing/architectures can differ. Packaging the add-on leaves the core executable hash unchanged; the core bundle verifier finds no Touch Bar presets/assets/BTT frameworks.
- One optimized-app resident-memory sample was **69.3 MiB** with the preview dashboard visible. An earlier debug snapshot was about 79.1 MiB, and the debug UI readout reached about 117 MB after opening Settings. These are point samples, not an idle average, leak test, 24-hour stability result, or a controlled CodexBar comparison.
- Local builds are ad-hoc signed. They are not a notarized public release.

No real provider credentials were read for these checks and no existing chat was compacted. Source and documentation remain a local implementation checkpoint, not owner-reviewed release evidence.

Remaining release gates:

- Authorized live quota validation against Codex/Gemini accounts and a Claude tester.
- Validate current native app-server access for desktop and CLI independently, including token-event subscriptions and real compaction completion.
- Verify BTT preset import, captured-target behavior and layout on physical Touch Bar hardware.
- Intel runtime coverage and oldest supported macOS.
- Credential rotation, overnight sleep/wake and a measured 24-hour soak.
- Public signing/notarization, release upgrade/rollback and final name.
- Startup-at-login UI and own-Keychain management if needed; neither is implemented yet.
