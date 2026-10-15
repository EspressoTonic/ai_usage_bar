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


## Antigravity source — 2026-10-15

Added a separately enabled Antigravity provider using its existing native agy login and structured `/usage` report. The previous Gemini provider is now explicitly labeled Gemini CLI. The new source uses no copied credentials, TUI scraping or persistent language-server/browser worker. It has private working directories, limited child environment, PATH-based browser-launch guards, bounded output/time and cancellation/process-group cleanup. Automatic refresh is at least five minutes. Native detached integrations remain outside process-group cleanup guarantees; CLI resource costs require separate profiling.

Reports preserve Gemini versus Claude/GPT and weekly versus five-hour limits. Missing/disabled fractions remain unavailable. CLI reports do not supply an account identity: the card says so, transport failures clear the reading, and disk cache excludes these snapshots. Old preferences/cache reconcile new providers without enabling them.

All **42 authored boundary cases** pass locally with original Swift Testing macro type-checking, including 12 new Antigravity report, upgrade and subprocess cases. At the owner's request, a read-only live probe through the installed agy **1.3.5** successfully returned four measured group/window entries. Raw native output, credentials, account metadata and exact personal quota/reset values are not committed. Native Keychain/provider upgrade, broader CLI versions, performance/soak and physical Touch Bar gates remain separate.


## Menu bar quota view — 2026-10-15

Clicking the chart status item now presents a dedicated quota view, independent of the full dashboard's selected Usage/Chats/System tab. It shows enabled providers, a remaining-percent ring for each reported limit, reset times, source/reading age, refresh/error states and links to Settings and the dashboard. The view sizes to its cards and scrolls beyond 500 points. Existing provider cards reuse the same accessible quota row. No cross-window/provider aggregate is invented; the existing collector supplies the initial readings immediately.

All 42 existing boundary cases passed locally, including original Swift Testing macro compilation. The optimized ARM64 app builds, launches and passes core/add-on bundle separation and secret checks. Native accessibility/screenshot inspection of the exact view through `--demo --preview-quota` confirmed separate Codex and Antigravity windows and readable percentages/reset labels. Direct automation of the macOS status-item click timed out; that click remains a manual interaction check. The preview does not access provider credentials. The normal app was restored afterward with the existing enabled providers and successful readings; no raw quota report, credentials or personal percentages/reset times were committed.


## Account-aware quota details — 2026-10-15

Implemented the owner-authorized follow-up to the CodexBar comparison: up to eight named local/SSH Codex account homes, returned account/plan/workspace details and credits, a selected source/window menu percentage, optional window-average pace/estimated exhaustion, opt-in encrypted quota history and low/reset notifications. Existing provider choices remain intact; new native sources, history and notifications default off. Token/cost analytics, broad provider expansion and web extras remain outside this slice. The Touch Bar add-on remains separately packaged and excluded from the core bundle.

A short-lived native stdio reader uses initialize/initialized and account → rate limits → account only, with a 30-second deadline, 1 MiB collection bound, serial source scheduling and owned process-group cleanup. Native authentication/keyring stays with Codex. Local homes/executables/parents are checked; SSH uses a validated alias, quoted absolute paths, existing host trust and noninteractive authentication, with forwarding/local commands/multiplexing disabled. No new live account has been enabled for verification. Before/after identity checks can detect only returned account fields; native versions without quota account IDs pause history/alerts. Work aliases do not assert a verified workspace name.

Pace requires fresh valid explicit duration/reset information and suppresses very early windows. History retains at most 1,000 changed points for seven days and requires stable source/account and a reported reset cycle. It prunes while running and on restore, encrypts in a separate file and clears on disable. Dashboard charts display the current reading's reset window; the quota popover keeps the concise cards. New account/profile metadata and history stay outside the bridge even with external chat access. Notifications request OS permission only on an explicit Settings action; fresh successful polls establish a silent baseline, then deduplicate threshold/reset transitions. Notification content omits personal labels and values.

All **62 authored boundary cases** pass locally, including original Swift Testing macro type-checking. New coverage exercises read-only ordering, signed-out/rotating accounts, malformed/error/unexpected protocol responses, output/deadline/cancellation bounds, child cleanup, quoted remote shell syntax, unsafe local paths, missing identity, multi-bucket/credit decoding, old snapshot compatibility, bridge redaction, history identity/cycle/retention bounds, menu freshness and alert transitions. Parallel subprocess fixtures wait for explicit readiness before cancellation; their bounded startup allowance was increased for the larger concurrent suite. Production deadlines were retained.

Native demo accessibility/screenshot review verified personal/work cards, account/plan/workspace and credits, pace, history rendering, scrolling and per-source/window Settings selection. It caught and fixed redundant credential-field binding updates clearing a reading; demo credential editing is now ignored and identical paths leave live readings intact. The optimized ARM64 app builds/launches and core/add-on checks pass. New native local/SSH authentication, actual OS notification delivery, physical Touch Bar interaction, oldest macOS/Intel and performance/soak remain live validation gates. No new RAM benchmark or public distribution claim is made.

Optimized ARM64 core file payload for this slice is **3,790,675 bytes** (about 3.62 MiB), superseding prior core-size checkpoints. This is on-disk payload, not a RAM measurement; system Swift Charts is not bundled as a third-party framework. Separate Touch Bar packaging and the core bundle verifier pass.


The first hosted run for this slice exposed aggregate fixture load: native account tests passed, while two existing Antigravity fixtures exceeded the unchanged three-second version-probe deadline when all fake CLIs started together. Added a shared two-process permit around native fixtures, matching the app's maximum one named Codex plus one Antigravity probe. HTTP/RPC cases remain parallel, and production deadlines/assertions are retained. Hosted revalidation follows this test-only correction.


## Reset countdowns and display-only banked resets — 2026-10-15

At the owner's explicit request, reset countdowns of at least 24 hours now use days/hours. Codex cards label the earned-reset inventory **Banked resets · Display only**. The existing native account source already parsed the count; the default OAuth source now also performs a fixed GET-only inventory read. A missing/unsupported inventory shows unavailable, without replacing successful quota windows with an error or guessing zero. Only the authoritative available count enters the model; inventory IDs/details are discarded.

The owner expressly prohibits using banked resets. Added that requirement to AGENTS.md, kept the UI text-only, and made the Codex quota HTTP/RPC request builders typed allowlists with no spending/redemption route. New synthetic checks assert GET-only endpoint/method sets, count-only retention, valid zero versus unknown/invalid values, one inventory GET without sending IDs, optional-read failure and cancellation. Native protocol fixtures also return an invented banked count and continue rejecting any unexpected method. No live reset is consumed during implementation or verification.

All **67 authored boundary cases** pass locally, including original Swift Testing macro compilation. Optimized ARM64 packaging/launch and native demo accessibility/screenshot review confirm day/hour countdowns, the available banked count, the unavailable state and the display-only label. These UI samples use invented accounts/counts. The core bundle verifier still excludes Touch Bar assets.


## Public documentation and license packaging — 2026-10-15

Reworked the README as an entry point for building, setup, current provider coverage, optional Touch Bar support, privacy, limitations and contributions. Detailed provider/context/bridge instructions moved into docs/usage.md with relative links corrected. Added CONTRIBUTING.md and THIRD_PARTY_NOTICES.md. The existing MIT grant/copyright was preserved; external provider tools/services and BetterTouchTool retain their own terms. The standalone preset includes a matching MIT license copy and its own NOTICE.md.

The app package now ships LICENSE and THIRD_PARTY_NOTICES.md in Contents/Resources; the package verifier requires their bytes to match the canonical files while retaining core/add-on separation. Touch Bar packaging checks that its license matches the root grant. Verified 21 local documentation links, the optimized app build/normal launch, exact license/notice contents in both artifacts and rejection of a disposable bundle missing its license. This change does not alter provider collection or banked-reset behavior; local full-core tests were not repeated for documentation/notice packaging alone. Hosted CI still runs the complete suite. No binary release was published.
