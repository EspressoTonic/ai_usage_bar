# Quota details implementation slice

Owner-authorized follow-up to the CodexBar comparison, 2026-10-15.

- Keep the existing enabled providers and separate optional Touch Bar package.
- Add up to eight named, explicitly enabled Codex sources. Each selects a local CODEX_HOME and executable, or an existing SSH alias plus absolute remote paths. Read only account and quota via a short-lived native stdio app-server; never log in, switch accounts, load a thread or compact through this reader. SSH uses existing host trust and noninteractive authentication.
- Show returned account/plan/workspace metadata and credits without inferring missing fields. Native identity is checked before and after the quota request. Unknown workspace identity disables account-dependent history and alerts.
- Offer a selected source/window percentage in the status item. Never aggregate unrelated limits. A stale, disabled or missing selection displays unavailable.
- Explain pace only for fresh readings with explicit valid duration/reset information. A linear projection is an estimate, not a promise of remaining work.
- Optional notifications require an explicit Settings action and OS permission. Baseline restored/initial readings silently; notify on threshold crossing or an observed new reset cycle. Deduplicate by source/account/window and omit personal labels from notification text.
- Optional seven-day quota history is encrypted locally, bounded to 1,000 points, identity-scoped and excluded from the bridge. No transcripts, raw native reports, tokens, token accounting or API billing analytics.

## Contracts and verification

Additive optional Codable fields preserve old settings, cache and CLI consumers. The bridge always removes new account/profile metadata. Profiles start disabled, are fetched serially, and use the existing collector. A profile reader has a 30-second deadline and 1 MiB combined output cap; only allowlisted JSON-RPC requests are sent after initialization. Local processes run in private directories with a limited environment and owned process-group cleanup. Remote EOF cleanup depends on SSH/native behavior and needs live validation.

Synthetic tests cover protocol ordering, identity changes, missing fields, injection resistance, output/time/cancellation limits, privacy, pace validity, bounded history and notification transitions. Build/package/secret checks and native demo UI review complete the slice. Live new account/SSH access, actual notifications, old macOS/Intel and overnight performance remain separate validation gates.
