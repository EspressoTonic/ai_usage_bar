#!/usr/bin/env python3
from pathlib import Path
import plistlib
import sys

bundle = Path(sys.argv[1])
for item in bundle.rglob('*'):
    if any(word in item.name.lower() for word in ('touchbar', 'btt', 'preset')):
        raise SystemExit(f'Unexpected add-on content in core: {item}')
    if item.suffix in {'.swift', '.jsonl'} or item.name in {'Tests', '.build'}:
        raise SystemExit(f'Unexpected source/test content in core: {item}')
with (bundle / 'Contents/Info.plist').open('rb') as stream:
    info = plistlib.load(stream)
assert info['CFBundlePackageType'] == 'APPL'
assert info['LSUIElement'] is True
assert (bundle / 'Contents/MacOS/AIUsageBar').is_file()
assert (bundle / 'Contents/Helpers/usagebar').is_file()
root = Path(__file__).resolve().parent.parent
for name in ('LICENSE', 'THIRD_PARTY_NOTICES.md'):
    notice = bundle / 'Contents/Resources' / name
    assert notice.is_file(), f'Missing packaged notice: {name}'
    assert notice.read_bytes() == (root / name).read_bytes(), f'Packaged notice differs from source: {name}'
print('Core bundle verified: no Touch Bar presets/assets/frameworks; license/notices included.')
