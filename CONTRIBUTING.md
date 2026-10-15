# Contributing

AI Usage Bar is an early native macOS project. The name is provisional. Read the [README](README.md), [architecture](docs/architecture.md), current [verification status](docs/status.md) and [security rules](SECURITY.md) before changing integration claims.

## Development

Use macOS 13+, Swift 6 and Python 3. `Package.swift` has no third-party package dependencies.

```sh
python3 script/check_secrets.py
./script/test.sh
./script/build_and_run.sh --verify --demo --preview
```

Full Xcode uses `swift test`. On Command Line Tools-only Macs, the test script first type-checks the original Swift Testing macros, then runs the same authored cases through a portable harness. Original macro compilation must pass; the fallback is not a replacement for hosted full-Xcode coverage. When adding a case, keep the portable runner's case list/count in sync.

Use `script/build_and_run.sh` for GUI builds and launches. Demo mode is the default for UI verification. Normal mode uses existing explicitly enabled connections; do not read a contributor's real credentials or mutate a live chat to test a change without authorization.

## Integration boundaries

- One collector owns fetching. Views, the CLI and BTT consume cached state; a popover must not start another collector.
- New providers/sources start disabled. Preserve unknown, expired, unsupported and stale states rather than assuming zero/full quota.
- Codex banked resets are display-only. Never add a consume/redeem control or request, and never spend a real reset during verification.
- Keep account/source identity separate. Never combine work/personal quotas, unrelated reset windows, cumulative tokens, current context or API billing.
- Native compaction requires an exact selected chat/revision, fresh idle state, a supported existing owner server and a matching completion event. Acknowledgement alone is not completion.
- Bound network/process/file work, redact errors, coalesce refreshes, cancel disabled sources and clean up owned process groups.
- Preserve encrypted local storage and bridge privacy. Do not add tokens, real account data, private paths, chat text or diagnostic captures to fixtures or Git.
- Keep `addons/` outside the main dependency graph/bundle. BetterTouchTool remains an optional external host.

## Validate a change

Run the tests appropriate to the changed boundary, then use these checks before submission:

```sh
python3 script/check_secrets.py
./script/test.sh
./script/package_app.sh release
./script/package_touchbar.sh
python3 script/verify_package.py dist/AIUsageBar.app
```

For a documentation-only change, check factual claims and relative links. Changes to packaging must verify the built artifacts, license/notice inclusion and core/add-on separation. Do not invent tests for prose or repeat a full suite without a relevant change.

Before committing/pushing, run the secret guard against staged data and reachable history:

```sh
python3 script/check_secrets.py --staged
python3 script/check_secrets.py --history
```

The limited guard supplements manual review; it does not prove a repository is secret-free. Never upload credentials or full transcripts in a bug report. Follow [SECURITY.md](SECURITY.md) for sensitive reports.

## Pull requests

Describe the problem, resulting behavior and relevant validation. Distinguish synthetic tests, demo UI review and live-provider verification. Include platform/CLI versions when relevant, with personal metadata removed. Update integration status and documentation when behavior or evidence changes.

Submit contributions under the project's [MIT license](LICENSE). Preserve existing notices and identify the source/license of any proposed third-party code or assets. Do not copy upstream code or assets without checking their terms and adding the required attribution/notices. Adding a dependency requires updating [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and the notices shipped in each affected artifact. External provider/tool names do not imply affiliation.
