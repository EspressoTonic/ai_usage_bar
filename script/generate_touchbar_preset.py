#!/usr/bin/env python3
from pathlib import Path
import json

root = Path(__file__).resolve().parent.parent
binary = '/Applications/AIUsageBar.app/Contents/Helpers/usagebar'
trigger = {
    'BTTUUID': '92A79C5C-B87B-4B57-B044-41D886CB38CB',
    'BTTTriggerType': 642,
    'BTTTriggerClass': 'BTTTriggerTypeTouchBar',
    'BTTEnabled': 1,
    'BTTTouchBarButtonName': 'AI Usage Bar',
    'BTTTriggerConfig': {
        'BTTTouchBarScriptUpdateInterval': 15,
        'BTTTouchBarShellScriptString': f'"{binary}" render --capture touchbar',
        'BTTTouchBarButtonFontSize': 13,
        'BTTTouchBarItemSFSymbolDefaultIcon': 'arrow.down.right.and.arrow.up.left',
    },
    'BTTActionsToExecute': [{
        'BTTPredefinedActionType': 206,
        'BTTShellTaskActionScript': f'"{binary}" compact-captured touchbar',
        'BTTShellTaskActionConfig': '/bin/bash:::-c:::-:::',
    }],
}
preset = {
    'BTTPresetName': 'AI Usage Bar — Touch Bar (experimental)',
    'BTTPresetUUID': '74443210-77CE-47C1-92BB-4A399877F4BD',
    'BTTPresetContent': [{'BTTAppBundleIdentifier': 'BT.G', 'BTTAppName': 'Global', 'BTTTriggers': [trigger]}],
}
(root / 'addons/TouchBar/AIUsageBar.bttpreset').write_text(json.dumps(preset, indent=2) + '\n')
print('Generated separate Touch Bar preset.')
