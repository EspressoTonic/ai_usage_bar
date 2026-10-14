# Architecture

One app process owns provider requests, system sampling, the session inventory and a versioned local bridge. SwiftUI displays cached state; opening a menu does not synchronously fetch providers or parse transcripts. Provider refreshes run independently and coalesce. Credentials stay in their adapter. The only external process used by this version is the optional tiny CLI client.

`ProviderClient → AppStore snapshot → native menu / Unix bridge → CLI → optional BTT widget`

System CPU is tick-delta utilization; memory used is active+wired+compressed pages, labeled accordingly. Memory pressure is an OS event signal. System sampling is every 2 seconds while a dashboard is visible, 10 seconds in the background and 30 seconds under Low Power. Turning it off performs no Mach sampling.

Session scanning examines at most 256 candidate filenames per day across seven recent directories and parses at most 32 files. Per file, read a 16 KiB head and 128 KiB tail; unchanged files reuse the cached model. Lifetime token usage is ignored. A reading's timestamp is retained, and missing values remain unknown. No prompts are retained in models/caches. Metadata observation never grants native compaction capability.

The Codex RPC adapter uses a user-selected existing loopback WebSocket endpoint. It never spawns an app-server or resumes an existing thread for monitoring. Main-actor operation gating serializes transport work. Native compaction checks the current loaded/idle status and the selected chat ID again. The response acknowledgement is not completion; a matching `contextCompaction` item-completed event is required.

Bridge requests are newline-delimited JSON v1. Each message is bounded; socket directory/file permissions are private; peer UID must match. The server owns its socket and rejects a second running collector. Same-user processes may use the bridge by design; it is not a security boundary against malicious software running as that user. Allowed actions are status, capabilities, refresh, select and compact. No shell/credential export action exists.

The BTT preset captures the rendered chat target and selection revision. Its action submits that captured request; a selection race is rejected. Physical BTT rendering/click timing still requires verification. The core and add-on have separate packaging paths; only the generic bridge client is included with the app.
