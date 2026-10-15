# Third-party notices

This notice describes the repository and its current packaging. It does not change the license of another project, tool, service or platform component.

## Project license

AI Usage Bar source, scripts, documentation, the `UsageCore` library, the `usagebar` CLI and the project-authored BetterTouchTool preset are distributed under the [MIT license](https://github.com/EspressoTonic/ai_usage_bar/blob/codex/initial-native-app/LICENSE).

Copyright © 2026 EspressoTonic. The complete license is included as `LICENSE` in the repository, in the app's `Contents/Resources/`, and in the standalone Touch Bar archive. The preset's MIT license covers the preset and its project-authored documentation, not BetterTouchTool itself.

## Bundled dependencies and assets

The current [Swift package](https://github.com/EspressoTonic/ai_usage_bar/blob/codex/initial-native-app/Package.swift) declares no third-party package dependencies. The packaging scripts include the two project executables, metadata and license/notice files; they do not bundle provider CLIs, BetterTouchTool, browser engines, fonts or third-party artwork.

Apple's system frameworks and the Swift toolchain/runtime remain covered by their respective terms. SwiftUI/AppKit/Charts/Foundation/CryptoKit/Security and system symbol names are used through platform APIs; their source, frameworks and SF Symbols artwork are not copied into this repository or the project-created package. This notice does not relicense those components.

## External tools and services

These are independently obtained components or services. They are not included in this project's MIT grant:

| Integration | Boundary | Official source / terms |
| --- | --- | --- |
| OpenAI Codex / ChatGPT | Existing CLI or authenticated quota service; account access required | [Codex](https://github.com/openai/codex), [OpenAI terms](https://openai.com/policies/terms-of-use/) |
| Claude | Existing CLI sign-in and authenticated quota service | [Claude Code](https://code.claude.com/docs/en/overview), [Anthropic terms](https://www.anthropic.com/legal) |
| Gemini CLI / Antigravity | Existing Google sign-in, external CLI or quota service | [Gemini CLI](https://github.com/google-gemini/gemini-cli), [Antigravity](https://antigravity.google/), [Google terms](https://policies.google.com/terms) |
| BetterTouchTool | Optional external host for the separate preset; requires its own applicable license | [Vendor licensing terms](https://folivora.ai/buy/) |
| OpenSSH / macOS | System-provided SSH executable and operating-system APIs | [OpenSSH](https://www.openssh.com/), [Apple software licenses](https://www.apple.com/legal/sla/) |

Use each external component under its own applicable license, account agreement and service terms. Installing this project does not include an account, subscription, paid tool license or permission to bypass a provider's access controls. Experimental integrations do not imply vendor endorsement or guaranteed API access.

## Research acknowledgment

[CodexBar](https://github.com/steipete/CodexBar) inspired the project and informed integration research. CodexBar source/assets are not vendored or distributed in this repository or these packages; this is not a fork or an official CodexBar add-on. Any future inclusion of upstream material must preserve its actual license and attribution.

## Redistribution checklist

Keep the MIT copyright/permission notice with copies or substantial portions of the project. Ship this notice with the app and retain the standalone preset's `LICENSE`/`NOTICE.md`. Review dependencies and update notices before adding or bundling third-party code, assets, frameworks or executables; the absence of bundled dependencies today is not a license determination for future additions.

Product names, trademarks and logos belong to their respective owners. This independent project is not affiliated with or endorsed by the listed vendors.
