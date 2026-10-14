# Security and privacy

This is an experimental personal macOS utility, not a security-audited release. The working threat model covers accidental publication, copying local app data, other local user accounts, unsafe local files, stale controls and accidental chat mutation. A compromised logged-in account, root access, or a compromised provider/CLI is outside these guarantees.

## Data rules

| Data | Git | Runtime handling |
| --- | --- | --- |
| Source, build recipes, synthetic fixtures, public defaults | Allowed after review | Public |
| OAuth access/refresh tokens, API keys, server bearer tokens, cookies | Never, including encrypted copies | Provider tokens stay in the owning CLI's files and are read only on explicit enable; app-server bearer stays in memory. If persistence is added, use an app-owned Keychain item. |
| Developer ID private keys, `.p12`, notarization credentials | Never | Local Keychain or protected CI secrets; no credentials in pull-request workflows |
| Provider paths, Google project ID, connection preferences, account fingerprint, quota readings | Never | AES-256-GCM encrypted app storage; key in the app's own macOS Keychain item |
| Chat/project labels, chat IDs, context estimates, operation records | Never | In-memory models only; explicitly permitted local bridge display |
| Chat text, prompts, source code in chats | Never | No retention/export by the app. Bounded parsing and RPC can transiently receive source bytes. |
| Touch Bar action target (ID/revision/request ID) | Never | Owner-only temporary file; valid for 30 seconds, consumed before dispatch and cleared when no target is actionable |
| Diagnostic logs, screenshots, crash reports, memory dumps, usage captures | Never by default | Review/redact before sharing. Memory dumps can contain in-memory secrets. No automatic upload. |
| CPU/RAM measurements | Do not commit personal captures | Live readings, no disk history |

Account hashes are pseudonymous metadata, not encryption. A chat title or project name can reveal confidential work even without a transcript. Do not commit real data as a bug reproduction. Use invented fixtures.

## Encrypted local storage

`~/Library/Application Support/AIUsageBar/` contains `preferences.sealed` and `quota-cache.sealed`. CryptoKit AES-GCM provides encryption and authentication, with a new random nonce per save. The file name is authenticated to reject swapping one encrypted file for another. Directory permissions are owner-only (`0700`), and files are created as `0600` before any bytes are written. Reads reject symlinks, non-regular files, foreign ownership, broad permissions and excessive size. Atomic writes replace a destination symlink itself rather than writing through it.

The 256-bit encryption key is generated locally and stored under the exact app-owned Keychain service `io.github.EspressoTonic.ai-usage-bar.local-storage`, account `encryption-key-v1`. It is never written alongside the ciphertext, compiled into source, sent to the CLI, or synchronized by app code. Keychain/disk operations run outside the main actor. The development implementation uses the macOS file-based Keychain with a trust list restricted to the calling app. Stable signed releases must verify Keychain access across updates; ad-hoc rebuilds can change trust identity. macOS's file-based and data-protection Keychains have different access controls: do not assume iOS protection-class semantics apply to this implementation.

Migration decodes old `preferences.json` / `snapshot.json`, re-encodes only the necessary fields, writes authenticated ciphertext, then removes the old app-owned plaintext file. The quota model cannot encode chat metadata. Interrupted cleanup resumes after successful decryption. A missing/denied key or invalid ciphertext produces an error and preserves existing data; there is no plaintext fallback or automatic key replacement for an existing encrypted file. Keychain loss means this nonessential encrypted state cannot be recovered without its original key. No automatic reset/delete flow is implemented.

Deleting a legacy file is not secure erasure and cannot remove older Time Machine/cloud backups. Keep the app's runtime directory out of Git and deliberate cloud exports even when encrypted. This does not encrypt or change the provider CLIs' original credential stores. Consider FileVault for whole-device protection; this app does not change that setting.

## Local bridge and Touch Bar

The Unix socket validates peer UID and uses an owner-only directory and socket. Message sizes, timeouts and simultaneous handlers are bounded. It cannot execute arbitrary shell commands or export credentials.

By default, bridge snapshots omit chat labels, IDs, selection and operations; provider account fingerprints are always redacted. External select/compact commands are rejected. The native UI can still compact a connected idle chat. For the BTT Compact widget, deliberately enable **Allow external tools to read chats and request compaction** in Settings. This permission resets each app launch. BTT requires permission only for the optional chat feature, not for core usage monitoring.

While enabled, any process running as the same user can access chat metadata and request supported actions. UID checks and file permissions do not distinguish BTT from same-user malware. A secret in another `0600` file would not solve that problem. Verified signed-client identity/pairing is a release-hardening item; do not claim a malware-resistant bridge. Encryption at rest does not authorize IPC calls.

Compaction still validates exact chat ID, current selection revision, fresh state, idle capability and a request ID, then rechecks the native server and waits for its completion event. Captured targets expire and are single-use from the CLI file; these controls prevent stale display actions, not same-user attacks after access is enabled.

## Network and permissions

Providers start disabled. Codex, Claude and Gemini CLI adapters use fixed HTTPS usage endpoints, an ephemeral URLSession, ordinary platform certificate verification and no redirects. Auth headers cannot be redirected to a new recipient. OAuth token scopes belong to the owning CLI; a token may have wider powers than the usage requests this app performs. No refresh token is copied or rotated. Credential reads open the selected file with no-follow and nonblocking flags, then verify the opened descriptor is a regular file owned by the current user, with no group/other POSIX permissions and a size at most 1 MiB. The read loop also rejects growth beyond that limit. Parent directory permissions need not be `0700`; a provider's public directory does not make an owner-only file readable. The final file component must not be a symlink. Unsafe files are rejected without changing CLI data or permissions. No hosted backend, analytics SDK or browser cookie scraping is included.

Provider response bodies are streamed using URLSession AsyncBytes. A declared length above 1 MiB is rejected before collection; missing-length/chunked bodies are checked as bytes arrive. Error response bodies are discarded, and the session is cancelled on rejection or caller cancellation. This bounds collected body data, not total process memory or every internal networking buffer. Raw transport details stay out of user-visible errors. Numeric `Retry-After` delays reject nonfinite values and are clamped between 30 seconds and one day.

Antigravity is a separate, explicitly enabled native-command source. The app validates the configured executable as a regular, executable, user/root-owned file without group/other write access, queries its version, then invokes only the structured `/usage` command (no model prompt). Credentials remain under agy's ownership; native authentication can perform its own normal refresh. A private temporary working directory avoids project instruction/config discovery from the user's current repository. The child receives a limited environment preserving its default home, optional Gemini profile home, locale, PATH and CA/proxy settings, without injected API credentials. PATH/BROWSER launch guards block the known `open`/`xdg-open` sign-in route; this is not an OS sandbox or a guarantee against a compromised CLI using another launcher.

CLI version/report reads have finite deadlines (3/90 seconds), bounded combined output (16 KiB/1 MiB), cancellation and owned process-group cleanup. No raw command stdout/stderr, account email or native error details reach app diagnostics. Native CLI integrations can start their own processes; deliberately detached descendants outside the probe's process group are outside this cleanup guarantee. The external CLI is not bundled and its transient resource use is distinct from the app's resident footprint. Account identity is unavailable in usage reports; do not attribute them to another provider or a selected Google account, and do not persist their quota snapshots. Disabled/missing fractions are not 0% or 100% usage. New provider entries remain off when upgrading existing preferences/cache.

App-server connections are explicitly configured loopback WebSockets only. Credentials must use the bearer field, not the URL; userinfo/query/fragment URLs are rejected, redirects are denied and WebSocket message size is bounded. Connect only to a trusted server that owns the chat. A loopback address alone does not authenticate a server.

The main app requires no Accessibility, screen recording, administrator helper or Full Disk Access. The optional BTT host has its own permissions and shell-action trust surface; inspect the imported preset and executable path. Local builds are ad-hoc signed, unsandboxed and unnotarized. Release binaries need Developer ID, hardened runtime and notarization; minimum permissions and app-sandbox feasibility must be reviewed against CLI files and local IPC.

## Repository controls and incidents

`.gitignore` excludes credentials, `.env` files, signing keys, encrypted runtime state and personal diagnostics. Ignore rules do not remove already tracked files or prevent `git add -f`.

Run `python3 script/check_secrets.py` before staging, `python3 script/check_secrets.py --staged` before committing, and `python3 script/check_secrets.py --history` before pushing. CI scans reachable history with full-depth checkout. The dependency-free guard detects prohibited runtime/signing paths, private keys, several known token formats, JWTs and long literal secret assignments. It reports location/rule only, never the matching value. Synthetic checks cover staged secrets and a deleted secret still in history. This intentionally limited guard is not proof that a repository contains no secrets. Enable GitHub secret scanning/push protection where available, and consider an established scanner such as Gitleaks before public release. No global hook or GitHub security setting is changed automatically.

If a real token reaches Git, revoke/rotate it first. Removing the current file or encrypting it later does not revoke access or remove existing clones/history. Coordinate any history cleanup; do not force-push as an automatic repair. If only private metadata leaked, assess what was revealed and sanitize future diagnostics.

For vulnerability reports, use GitHub private vulnerability reporting if the maintainer enables it; otherwise ask for a private contact without including the exploit's secrets or personal data. Never upload credential files or full transcripts in a public issue. A private reporting channel has not yet been configured.

## Verification and remaining limits

Security fixtures validate ciphertext round trips, tampering, wrong keys, file swaps, failed migration preservation, chat-data minimization, private file modes, symlinks, size limits, bridge redaction/permission policy, action expiry and redirect refusal. Keys and chats are disposable fixtures; tests do not read provider credentials or real Keychain secrets.

Real Keychain creation/access/denial across signed upgrades, live provider credential formats, physical BTT action timing, signed-client authorization, crash-dump disclosure and a full security review remain release gates. Provider HTTP collection now enforces its size limit while streaming, with loopback fixtures covering declared and chunked overflow, exact-limit success, error-body discard, redirect refusal and cancellation. Antigravity CLI 1.3.5 returned a successful live structured quota report on 2026-10-15; other live-provider routes and CLI versions remain unverified. Core/add-on packaging remains separate.

References: [Apple Keychain services](https://developer.apple.com/documentation/security/keychain-services), [macOS Keychain implementations](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains), [Keychain trust lists](https://developer.apple.com/documentation/security/secaccesscreate(_:_:_:)), [CryptoKit AES-GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm), [URLSession streaming](https://developer.apple.com/documentation/foundation/urlsession/bytes(for:delegate:)), [Apple secure file operations](https://developer.apple.com/library/archive/documentation/Security/Conceptual/SecureCodingGuide/Articles/RaceConditions.html), [GitHub sensitive-data response](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository).
