# AI Usage Bar (working name)

A native macOS menu-bar utility for coding-provider quota, per-chat context, and CPU/RAM monitoring. Touch Bar support is a separate optional BetterTouchTool add-on. The final name is undecided.

## Build and run

Requires macOS 13+ and a Swift 6 toolchain. No third-party Swift dependencies.

```sh
python3 script/check_secrets.py
./script/test.sh
./script/build_and_run.sh
```

For a safe UI preview without credential reads, local session scans, or provider network calls:

```sh
./script/build_and_run.sh --verify --demo --preview
```

On Command Line Tools-only Macs, `script/test.sh` first type-checks the original Swift Testing sources with the bundled macro plugin, then executes the same authored cases through a portable runner because the Testing runtime can be incomplete. It fails if the original macros cannot be checked. Full Xcode installations use `swift test`.

The app is intentionally menu-bar-only (no Dock icon). Click the chart icon to open the popover. Settings are available from its gear button. The packaged app is `dist/AIUsageBar.app`; its small CLI is `Contents/Helpers/usagebar`. The Codex Run action uses the same build/run script.

## Current implementation

| Feature | Status |
| --- | --- |
| Native menu-bar UI and settings | Implemented; live-provider connections start disabled |
| CPU/RAM and memory-pressure sampling | Implemented with slower background/Low Power sampling |
| Codex quota | Experimental CLI OAuth adapter; fixtures tested; live account validation pending |
| Antigravity quota | Native `agy -p /usage --output-format json`; separate groups/windows; live verified with agy 1.3.5 |
| Gemini CLI quota | Experimental OAuth adapter, model buckets and unsupported-tier state; live validation pending |
| Claude quota | Experimental `.credentials.json` OAuth adapter; Keychain-only sign-in not supported yet |
| Local Codex context | Opt-in, bounded recent rollout metadata; last-turn estimate, not an exact live working-set measurement |
| Desktop/CLI native compaction | Opt-in existing local WebSocket app-server connection; exact ID/revision and idle checks; completion event required |
| Touch Bar | Separate BTT preset and CLI bridge; physical hardware/import validation pending |

Session discovery is limited to recent local Codex rollout files. Client labels are preserved from source metadata; an unknown source is not guessed to be the desktop app. A new connection may not receive another client's token events. Local metadata does not enable compaction. The app never resumes a chat in another server to obtain state.

## Connect a provider

For **Antigravity**, enable its separate provider in Settings and select the `agy` executable (normally `~/.local/bin/agy`). It uses the CLI's existing login and structured `/usage` report; the app does not read or copy Antigravity tokens. Requires agy 1.1.11+, with 1.3.5 verified locally. Weekly/five-hour windows and Gemini/Claude+GPT groups remain separate. The source is the CLI's active login; reports do not identify the account, so those readings stay in memory and are not restored from disk. Automatic refresh is at least five minutes; one report subprocess group runs at a time and ends after each read. Timeout is 90 seconds; combined stdout/stderr collection is capped at 1 MiB. Sign in through `agy` in a terminal if needed. Refresh probes guard PATH-based browser launchers and never initiate an intentional login flow.

The **Gemini CLI** row is for Gemini CLI sign-in and quota. Installing Antigravity does not establish that source; it has its own provider.

For **Codex, Claude and Gemini CLI**, enable the provider in Settings after reviewing its credential path. These adapters read the existing CLI OAuth token and call only the provider's fixed usage endpoints. Providers are independent; disabling one cancels its refresh and clears its visible/cache state. Tokens are not stored in the app's settings, snapshots, CLI output or logs. Expired tokens must be renewed by their owning CLI; the app does not overwrite shared credential files. Sign-in files must be regular files owned by your user, with owner-only permissions (normally `0600`), and the selected file must not be a symlink. Unsafe permissions produce an error; the app never changes them automatically. Provider response bodies are streamed with a 1 MiB collection limit and cancelled on rejection.

Subscription quota, per-chat context and API spending are different. This release tracks subscription quota and context estimates; it does not claim to track API billing.

Google currently has conflicting documentation about consumer Gemini CLI Google-login access. The adapter reports unsupported/missing quota honestly. Check your actual tier and CLI version; no Antigravity data is silently relabeled as Gemini CLI quota. See [Google's notice](https://developers.google.com/gemini-code-assist/docs/deprecations/code-assist-individuals).

## Native compaction

In Settings, enter the WebSocket endpoint of the **existing local app-server that owns the chat**, with a bearer token if required. The token stays in memory. Connecting lists visible threads without starting/resuming one. Only confirmed loaded idle threads can expose Compact. The RPC client rechecks state before invoking `thread/compact/start`, and waits for its `contextCompaction` completion event. Availability depends on your client/server version; this does not promise universal access to desktop chats. No UI keystrokes, blind focus targeting or transcript replay are used.

## Optional Touch Bar download

```sh
./script/package_touchbar.sh
```

Produces `dist/AIUsageBar-TouchBar.zip` separately from the main app. See [the add-on guide](addons/TouchBar/README.md). BetterTouchTool is an external prerequisite only for this add-on.

## Local bridge

```sh
dist/AIUsageBar.app/Contents/Helpers/usagebar doctor
dist/AIUsageBar.app/Contents/Helpers/usagebar status
```

The app owns one collector. The CLI and Touch Bar do not fetch credentials or provider usage. The bridge is a private same-user Unix socket with bounded messages, a versioned protocol, allowlisted commands, and target/revision checks. Default snapshots omit chats and redact account fingerprints. External chat access and compaction require a Settings permission that resets each launch. While enabled, any process running as your user can use that chat bridge. Treat its output and display labels as private.

Preferences and a quota-only cache are AES-GCM encrypted under `~/Library/Application Support/AIUsageBar/`, with a separate app-owned macOS Keychain key. Chat metadata and operations stay in memory. Old app-owned plaintext files migrate only after successful encryption. No plaintext fallback is used. The temporary bridge directory is `/private/tmp/ai-usage-bar-<uid>/` with owner-only permissions; captured action targets expire after 30 seconds and are consumed before use. See [security and privacy rules](SECURITY.md) for Git exclusions, Keychain limitations and release gates.

## Package and checks

```sh
AI_USAGE_BAR_CONFIGURATION=release ./script/build_and_run.sh --verify
python3 script/verify_package.py dist/AIUsageBar.app
./script/package_touchbar.sh
```

Local builds are ad-hoc signed for development, not distribution-ready or notarized. Public binaries require separate Developer ID signing/notarization. CI builds/tests and inspects the core bundle for accidental add-on assets. Measure core-only and add-on/BTT costs separately; no performance or 24-hour stability claims are made before measurement.

## Development

- Core data/contracts: `Sources/UsageCore/`
- Native UI/services: `Sources/AIUsageBar/`
- Thin client: `Sources/UsageBarCLI/`
- Optional display resources: `addons/TouchBar/`
- Meaningful boundary tests: `Tests/UsageCoreTests/`

See [architecture](docs/architecture.md) and [implementation status](docs/status.md).

MIT licensed. All code in this initial implementation is original; CodexBar documentation was used as integration research, not copied source. The APIs of experimental adapters can change.
