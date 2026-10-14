# Touch Bar add-on (experimental)

This is a separate download. The main app does not bundle this preset or depend on BetterTouchTool.

1. Build/install the main app as `/Applications/AIUsageBar.app` (or edit the binary path in BTT).
2. Install BetterTouchTool separately on a Touch Bar Mac.
3. Import `AIUsageBar.bttpreset`. Inspect the imported Shell Script widget and its assigned action before enabling it.
4. Select a chat in the main app. The widget reads cached context every 15 seconds.
5. Tapping the widget requests compaction of the target captured when its label was rendered. The core validates its ID/revision and native capability. A selection change causes rejection. Read operation completion/failure in the main app.

The CLI bridge and identity checks are tested. Preset import and physical Touch Bar interaction still require hardware/BTT verification; they are not advertised as production-supported yet. Missing/unsupported context disables the action at the core even if BTT shows the widget.

If you already have other BTT presets, import only these items; never replace your whole configuration. To remove the add-on, delete its own widget/preset. Nothing is installed into the main app, and provider connections remain intact.

Developer fallback: create a BTT **Shell Script widget**, run the bundled `usagebar render --capture touchbar` command, set a 15-second interval, and assign **Execute Shell Script / Task** to `usagebar compact-captured touchbar`. Full executable paths are required. No Node, Python, jq or provider credentials are needed by the widget at runtime.

References: [widgets](https://docs.folivora.ai/docs/touch-bar/widgets/), [trigger definitions](https://docs.folivora.ai/docs/json/trigger-definitions/), [shell actions](https://docs.folivora.ai/docs/actions/action-definitions/).
