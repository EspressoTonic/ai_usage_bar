# Usage guide

Start with the [README](../README.md) to build and open the menu-bar app. All provider connections and additional data access are opt-in.

## Connect a provider

For **Antigravity**, enable its separate provider in Settings and select the `agy` executable (normally `~/.local/bin/agy`). It uses the CLI's existing login and structured `/usage` report; the app does not read or copy Antigravity tokens. Requires agy 1.1.11+, with 1.3.5 verified locally. Weekly/five-hour windows and Gemini/Claude+GPT groups remain separate. The source is the CLI's active login; reports do not identify the account, so those readings stay in memory and are not restored from disk. Automatic refresh is at least five minutes; one report subprocess group runs at a time and ends after each read. Timeout is 90 seconds; combined stdout/stderr collection is capped at 1 MiB. Sign in through `agy` in a terminal if needed. Refresh probes guard PATH-based browser launchers and never initiate an intentional login flow.

The **Gemini CLI** row is for Gemini CLI sign-in and quota. Installing Antigravity does not establish that source; it has its own provider.

For **Codex, Claude and Gemini CLI**, enable the provider in Settings after reviewing its credential path. These adapters read the existing CLI OAuth token and call only the provider's fixed usage endpoints. Providers are independent; disabling one cancels its refresh and clears its visible/cache state. Tokens are not stored in the app's settings, snapshots, CLI output or logs. Expired tokens must be renewed by their owning CLI; the app does not overwrite shared credential files. Sign-in files must be regular files owned by your user, with owner-only permissions (normally `0600`), and the selected file must not be a symlink. Unsafe permissions produce an error; the app never changes them automatically. Provider response bodies are streamed with a 1 MiB collection limit and cancelled on rejection.

Subscription quota, per-chat context and API spending are different. This release tracks subscription quota and context estimates; it does not claim to track API billing.

Gemini CLI availability depends on Google's current account tiers and CLI support. The adapter reports unsupported or missing quota as unavailable. Check your tier and CLI version; Antigravity data is never relabeled as Gemini CLI quota. See [Google's compatibility notice](https://developers.google.com/gemini-code-assist/docs/deprecations/code-assist-individuals).

## Named Codex accounts and quota details

In Settings, **Add Codex source…** to label a personal/work account home. Choose **This Mac** with absolute CODEX_HOME and Codex executable paths, or **SSH server** with an existing SSH config alias and absolute paths on that server. Up to eight sources are supported and each starts disabled. Enable a source after reviewing its configuration. Existing `codex-account` profiles can supply their account-home paths; this app does not switch or log in to those accounts.

The native reader starts a temporary stdio app-server, initializes it, reads account → rate limits → account, then stops its owned process group. It sends no thread, login/logout or credit-redemption commands. Codex handles its own authentication/keyring and normal native refresh. Sources poll serially, at least every two minutes, with a 30-second read deadline and 1 MiB combined output cap. SSH is noninteractive: pre-existing authentication and a known host key are required; no password prompt or automatic host-key acceptance. SSH forwarding, local commands and connection multiplexing are disabled for these reads. Local home/executable permissions are checked; remote path ownership and behavior still require live validation. Native integrations that deliberately detach are outside local process-group cleanup.

Reset countdowns use days and hours for intervals of at least one day (for example, `Resets in 3d 4h`). Account email, plan, workspace name, balances and banked-reset counts appear only when returned. Codex's OAuth row also reads the banked-reset inventory with a fixed GET request. Banked resets are **display-only**: the app has no consume/redeem action or request route. Missing inventory displays unavailable rather than zero. An alias such as “Work” is your label, not verified workspace metadata. Some Codex versions omit the quota account ID; these sources show identity unavailable and skip account-dependent history/alerts. The before/after account check detects reported identity changes; it cannot prove a workspace stayed constant when the native account response omits it. Native local/SSH compatibility has synthetic coverage; live validation is pending.

After a successful reading, **Menu bar percentage** lets you select one source and one limit. `C`, `Cl`, `G`, `A` identify Codex, Claude, Gemini CLI and Antigravity; hover reveals the selected source/window. Stale, failed, disabled or missing readings show a dash. **Show window-average pace estimates** projects usage linearly from the provider's explicit duration/reset; estimates are hidden for stale, invalid or very early windows. Future activity can change the result.

**Keep encrypted quota history** is off by default. It retains at most 1,000 changed quota points across sources for seven days, pruning on load and while running; disabling clears saved history. Dashboard charts show only the current account/reset window. No transcripts, token/cost analytics or raw CLI reports are stored. Antigravity reports lack stable account identity and remain excluded. History and new account/profile metadata are excluded from the CLI/Touch Bar bridge.

Notifications are off by default. Enabling them in Settings requests macOS permission. The first successful poll establishes a silent baseline; later threshold crossings and optional observed resets can notify. Notifications omit account emails, source labels and quota values. They depend on successful polling and are not instant/offline reset alarms. Actual OS delivery remains a live validation gate.

Native protocol reference: [OpenAI app-server account and rate-limit APIs](https://learn.chatgpt.com/docs/app-server).

## Chat context and native compaction

Session discovery is limited to recent local Codex rollout files. Client labels are preserved from source metadata; an unknown source is not guessed to be the desktop app. The displayed context is a last-turn estimate, not an exact live working-set measurement. Lifetime tokens, context size and subscription quota remain separate. A new connection may not receive another client's token events. Local metadata does not enable compaction, and the app never resumes a chat in another server to obtain state.


In Settings, enter the WebSocket endpoint of the **existing local app-server that owns the chat**, with a bearer token if required. The token stays in memory. Connecting lists visible threads without starting/resuming one. Only confirmed loaded idle threads can expose Compact. The RPC client rechecks state before invoking `thread/compact/start`, and waits for its `contextCompaction` completion event. Availability depends on your client/server version; this does not promise universal access to desktop chats. No UI keystrokes, blind focus targeting or transcript replay are used.

## Optional Touch Bar download

```sh
./script/package_touchbar.sh
```

Produces `dist/AIUsageBar-TouchBar.zip` separately from the main app. See [the add-on guide](../addons/TouchBar/README.md). BetterTouchTool is an external prerequisite only for this add-on.

## Local bridge

```sh
dist/AIUsageBar.app/Contents/Helpers/usagebar doctor
dist/AIUsageBar.app/Contents/Helpers/usagebar status
```

The app owns one collector. The CLI and Touch Bar do not fetch credentials or provider usage. The bridge is a private same-user Unix socket with bounded messages, a versioned protocol, allowlisted commands, and target/revision checks. Default snapshots omit chats and redact account fingerprints. External chat access and compaction require a Settings permission that resets each launch. While enabled, any process running as your user can use that chat bridge. Treat its output and display labels as private.

Preferences, a quota-only cache and optional quota history are AES-GCM encrypted under `~/Library/Application Support/AIUsageBar/`, with a separate app-owned macOS Keychain key. Chat metadata and operations stay in memory. Old app-owned plaintext files migrate only after successful encryption. No plaintext fallback is used. The temporary bridge directory is `/private/tmp/ai-usage-bar-<uid>/` with owner-only permissions; captured action targets expire after 30 seconds and are consumed before use. See [security and privacy rules](../SECURITY.md) for Git exclusions, Keychain limitations and release gates.
