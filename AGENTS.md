# AI Usage Bar

Native macOS Swift package. The product name remains provisional.

- Read README.md and docs/status.md before changing integration claims.
- Use `./script/test.sh` for core boundaries; use `./script/build_and_run.sh` for GUI launch.
- Keep provider/session data unknown when unavailable. No demo data in a live reading.
- Providers require explicit enablement. Do not test using real credentials or mutate a live chat without owner authorization.
- One collector owns all fetching; the CLI and optional Touch Bar adapter only consume the bridge.
- Keep `addons/` out of the main app dependency graph and bundle. Run the packaging verifier.
- Recheck exact chat identity, selection revision, idle state and capability before compaction; acknowledgement is not completion.
- No credentials, transcript text or bearer tokens in output/logs/test fixtures. Sanitize fixtures.
- Never conflate cumulative tokens, current context and subscription quota.
- Preserve user changes. Do not publish releases or replace installed provider credentials as part of local verification.
