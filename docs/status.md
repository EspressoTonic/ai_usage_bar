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
- Startup-at-login UI and user-facing Keychain recovery/reset management; neither is implemented yet. App-owned encryption-key storage is implemented in the security checkpoint below, with live validation pending.

## Security hardening — 2026-10-14

Added AES-GCM local storage with an app-specific Keychain key, a quota-only disk model, successful-encryption-before-removal migration, no plaintext fallback, owner-only atomic files and unsafe-file rejection. Chat metadata and system history are no longer persisted. External chat access/compaction are opt-in per launch; bridge account fingerprints are redacted. Captured Touch Bar actions expire in 30 seconds and are consumed before dispatch. Provider/RPC redirects are denied; RPC URLs reject embedded secrets and enforce a WebSocket size limit. Bridge asynchronous handlers are bounded.

Expanded `.gitignore` and added a redacted, limited secret guard with full-history CI scanning. All 21 Swift boundary cases pass, plus synthetic secret-guard cases including a deleted secret remaining in Git history. No covered secret patterns were found in the initial published commit or current sources. This is not a comprehensive secret scan or security audit.

Storage tests inject disposable keys. Real Keychain access, upgrade identity and denial behavior have not yet been exercised. The development Keychain uses macOS file-based access controls; signed distribution must review the data-protection Keychain route and validate migrations. Other release gates above remain open. See [SECURITY.md](../SECURITY.md).

The hardened ARM64 optimized core builds and passes bundle separation checks. Its current file payload is **2,304,259 bytes** (about 2.20 MiB); the separately packaged Touch Bar ZIP is **2,578 bytes**. These supersede the earlier size measurements for this revision. No new resident-memory measurement or normal-mode Keychain launch was performed for this checkpoint.

## Credential and HTTP boundaries — 2026-10-14

Replaced credential path-attribute/unbounded reads with descriptor-based no-follow/nonblocking reads. Validates regular-file type, current-user ownership, owner-only POSIX file permissions and a 1 MiB read limit; rejects pipes and unsafe files without changing them. Parent directories may keep their normal provider permissions. Replaced full-response downloads with a streamed 1 MiB body collection limit, declared-length checks and explicit cancellation. Non-success HTTP bodies are discarded, raw transport details remain redacted and numeric retry delays are finite/bounded.

All **30 authored boundary cases** pass. The nine added cases cover credential file handling, malformed retry headers, and seven loopback HTTP modes: small/exact-limit success, declared/chunked overflow, redirect refusal, error-body discard and stalled-download cancellation. HTTP fixtures serve one bounded connection and close; the cancellation case waits for a server signal confirming that the response body has started. These are synthetic files and local servers, with no real provider credentials or chat mutation. Prior Keychain, live-provider and distribution gates remain open.

The updated optimized ARM64 bundle passes core/add-on separation checks. Its current core file payload is **2,323,075 bytes** (about 2.22 MiB), an increase of 18,816 bytes over the previous security build. This supersedes that core size for this revision; no new memory or live Keychain measurements were taken.

## Swift Testing compilation correction — 2026-10-14

GitHub's full-Xcode runs for the security commits failed while compiling two `#require` expressions: their inner file-load calls could throw, but only the outer assertion was marked `try`. Local portable execution had stripped the macros, so its passing counts did not establish native macro compilation. Fixed the tests by evaluating throwing loads first and asserting their optional results separately.

The CLT fallback now type-checks every original test source with Apple's bundled Swift Testing macro plugin before generating its runtime harness. It fails if that check cannot run or if any source fails to compile. The exact original CI error was reproduced with that compiler/plugin; the corrected sources type-check and all 30 authored cases pass locally. Full-Xcode test execution and packaging results are reported by the GitHub workflow. No production app behavior changes in this correction.

Full-Xcode execution then exposed fixture executor starvation: parallel tests performed blocking process startup, pipe reads and process waits on Swift workers, delaying network callbacks until fixture timeouts. Shared fixture lifecycle helpers now dispatch every blocking operation to a GCD queue and await completion, keeping native parallel coverage enabled. Fixture cleanup is awaited on both success and failure. These are test-infrastructure changes, not relaxed network assertions or production timeout changes.
