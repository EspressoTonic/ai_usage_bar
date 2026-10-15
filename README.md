# AI Usage Bar

[![macOS checks](https://github.com/EspressoTonic/ai_usage_bar/actions/workflows/ci.yml/badge.svg)](https://github.com/EspressoTonic/ai_usage_bar/actions/workflows/ci.yml)
[MIT licensed](LICENSE) · macOS 13+ · Swift 6 · Working name

A native macOS menu-bar app for AI coding quotas, Codex chat context and CPU/RAM monitoring. Click the chart icon to see how much quota remains and when each limit resets.

Touch Bar support is a **separate optional add-on**. The main app works on Macs without a Touch Bar and contains no BTT preset, Touch Bar assets or BetterTouchTool dependency.

## What it does

- Displays separate Codex, Claude, Gemini CLI and Antigravity quota windows with remaining-percentage gauges and day/hour reset countdowns.
- Shows account/plan details, credit balances and **display-only banked resets** when reported. The app cannot consume or redeem banked resets.
- Supports named local or SSH Codex account homes for personal/work monitoring.
- Offers a selected quota percentage in the menu bar, optional pace estimates, encrypted quota history and low/reset notifications.
- Estimates per-chat Codex context and can request native compaction when connected to the existing server that owns an idle chat.
- Samples CPU, RAM, memory pressure and the app's resident memory, with slower background and Low Power sampling.

The core uses SwiftUI and direct usage requests. It has no embedded browser or website JavaScript. Optional native CLI reads run as bounded subprocesses. This describes the architecture; it is not a guarantee of zero CPU spikes or long-term memory stability.

## Build and open

The app targets macOS 13 or later. Building requires a Mac with a Swift 6 toolchain (full Xcode or Command Line Tools), plus Python 3 for development scripts. No third-party Swift packages are required.

```sh
git clone https://github.com/EspressoTonic/ai_usage_bar.git
cd ai_usage_bar
python3 script/check_secrets.py
./script/test.sh
./script/build_and_run.sh
```

This builds and opens `dist/AIUsageBar.app`. It lives in the **menu bar**, with no Dock icon. Click its chart icon, then the gear button to open Settings. The Codex app's Run action uses the same build/run script.

Builds are currently ad-hoc signed for local development. A notarized public binary release has not been published.

### Preview with sample data

```sh
./script/build_and_run.sh --verify --demo --preview
# Preview the exact menu-bar quota content in a standalone window:
./script/build_and_run.sh --verify --demo --preview-quota
```

Demo mode uses invented accounts and quotas without provider credential reads, provider requests or local session scans.

## Connect your accounts

1. Sign in using the provider's own CLI.
2. Open Settings, review the selected sign-in file or executable, then enable that provider.
3. After a successful reading, choose a source/window under **Menu bar percentage** if you want a percentage next to the icon.

All providers start disabled. New named sources, quota history and notifications also start off. Installing Antigravity does not establish a Gemini CLI connection; they are separate sources.

| Source | How it reads quota | Current coverage |
| --- | --- | --- |
| Codex OAuth | Fixed usage and banked-inventory HTTPS GET requests | Live reads verified; experimental endpoints |
| Named Codex sources | Short-lived native app-server read for a selected local/SSH `CODEX_HOME` | Synthetic protocol coverage; native local/SSH login validation pending |
| Antigravity | Existing `agy -p /usage --output-format json` report | Live verified with agy 1.3.5; requires 1.1.11+ |
| Gemini CLI | Existing Google CLI OAuth sign-in and model quota buckets | Experimental; live validation pending; account/tier dependent |
| Claude | Existing `.credentials.json` OAuth sign-in | Experimental; live validation pending; Keychain-only sign-in unsupported |

**Banked resets stay display-only.** Missing counts show unavailable rather than zero. There is no Use/Redeem button, automatic redemption or reset-spending request route.

Read the [usage guide](docs/usage.md) for provider paths, named accounts, pace/history/alerts, context, compaction and CLI commands. For explicit Codex CLI account switching, see the separate [codex-account-switcher](https://github.com/EspressoTonic/codex-account-switcher) project; Usage Bar monitors the selected homes.

## Optional Touch Bar add-on

```sh
./script/package_touchbar.sh
```

Builds `dist/AIUsageBar-TouchBar.zip` independently of the main app. The experimental widget displays selected-chat context and requests compaction of its captured target. It requires a Touch Bar Mac and a separately installed, [separately licensed BetterTouchTool](https://folivora.ai/buy/).

Follow the [add-on guide](addons/TouchBar/README.md) and inspect the preset before importing. External chat access must be explicitly enabled for each app launch. Import and physical Touch Bar behavior still need hardware validation.

## Privacy and security

Provider tokens stay in their owning CLI stores. Enabled OAuth adapters read them transiently; native CLI sources delegate authentication to the CLI. The app does not save provider tokens or initiate sign-in flows. Renew expired sign-ins using the owning CLI.

Preferences, the quota-only cache and optional history are encrypted with AES-GCM and an app-owned Keychain key. History is limited to seven days and 1,000 changed quota points. Chat metadata and operations remain in memory; transcripts are not retained in app models or exported. The local bridge omits chats by default and always removes account identities and named-profile details.

The core needs no Accessibility, screen recording, administrator helper or Full Disk Access permission. External tools such as BetterTouchTool have their own permissions. Provider access, local context, external chat controls and notifications each have explicit enablement. Read [SECURITY.md](SECURITY.md) before enabling external chat controls or sharing diagnostics.

## Current limits

This is an early implementation. Experimental provider endpoints and CLI protocols can change. Unknown quota/context stays unknown, and pace is an estimate based on the reported window, not a promise of remaining work. Subscription quota, context and API billing are different; API billing/token-cost analytics are not implemented.

Native source authentication, actual notification delivery, physical Touch Bar behavior, Intel/oldest-macOS runtime coverage, 24-hour performance/soak testing and signed-release upgrades remain validation gates. Cached readings can be stale. This is not a security-audited or notarized public release. See the dated [implementation status](docs/status.md) for evidence and limitations.

## Contributing

Bug reports, provider fixtures, documentation and platform testing are welcome. Use invented fixtures and never attach credentials, real chat data or unredacted usage captures to an issue or pull request.

Read [CONTRIBUTING.md](CONTRIBUTING.md) for setup, validation and integration constraints, and [architecture](docs/architecture.md) for the collector/bridge design. The current core suite contains 67 authored boundary cases; hosted CI runs the full Xcode test path.

## License and acknowledgments

The app, core library, CLI, scripts, documentation and optional preset are [MIT licensed](LICENSE), copyright © 2026 EspressoTonic. Keep the copyright and permission notice when redistributing copies or substantial portions.

[Third-party notices](THIRD_PARTY_NOTICES.md) explain platform components, external tools and provider terms. The standalone Touch Bar archive includes its own license copy and notices. BetterTouchTool and provider services are not included or relicensed by this project.

Inspired by [CodexBar](https://github.com/steipete/CodexBar) and the idea of keeping useful status in the menu bar. CodexBar integration documentation/source was consulted as research; its code and assets are not vendored here. This is an independent project, not affiliated with or endorsed by OpenAI, Anthropic, Google, Apple, CodexBar or BetterTouchTool. Product names and marks belong to their respective owners. The final app name is undecided.
