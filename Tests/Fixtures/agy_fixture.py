#!/usr/bin/python3
"""Invented native-command fixture; no auth, network or real account state."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

mode = Path(sys.argv[0]).name.removeprefix('agy-')
if sys.argv[1:] == ['--version']:
    print('1.0.0' if mode == 'old' else '1.3.5')
    raise SystemExit(0)
if sys.argv[1:] != ['-p', '/usage', '--output-format', 'json']:
    raise SystemExit(19)
if mode == 'old':
    (Path(sys.argv[0]).parent / 'unexpected-usage').write_text('must not start on an old version')
    raise SystemExit(20)
if mode == 'signin':
    print('not signed in: SYNTHETIC-PRIVATE-ACCOUNT', file=sys.stderr)
    raise SystemExit(1)
if mode == 'overflow':
    print('SYNTHETIC-PRIVATE-OUTPUT' * 10000, file=sys.stderr, flush=True)
    time.sleep(10)
if mode in ['timeout', 'cancel']:
    Path('ready').write_text('ready')
    time.sleep(10)
if mode == 'group':
    child = subprocess.Popen([sys.executable, '-c',
        'import time,pathlib; p=pathlib.Path("heartbeat");\nwhile True: p.write_text(str(time.monotonic_ns())); time.sleep(0.02)'],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.monotonic() + 2
    while not Path('heartbeat').exists() and time.monotonic() < deadline:
        time.sleep(0.01)
    print('{}')
    raise SystemExit(0)
if mode == 'bad-report':
    print(json.dumps({'status': 'SUCCESS', 'response': 'SYNTHETIC-MODEL-REPLY'}))
    raise SystemExit(0)
if mode == 'environment':
    browser = Path(os.environ.get('BROWSER', '/invalid'))
    if browser.parent.resolve() != Path.cwd().resolve() or not browser.is_file():
        raise SystemExit(21)
    if any(os.environ.get(key) for key in ['OPENAI_API_KEY', 'GEMINI_API_KEY', 'GOOGLE_API_KEY']):
        raise SystemExit(22)
    if subprocess.call([str(browser)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) != 1:
        raise SystemExit(23)
print(json.dumps({'status': 'SUCCESS', 'command': {'name': 'usage', 'data': {'groups': [
    {'display_name': 'Gemini Models', 'buckets': [
        {'bucket_id': 'gemini-week', 'display_name': 'Weekly', 'remaining_fraction': 0.7,
         'reset_time': '2026-10-19T12:00:00Z', 'window': 'WEEKLY'},
        {'bucket_id': 'gemini-session', 'display_name': '5 hours', 'remaining_fraction': 0.9, 'window': 'FIVE_HOUR'}]},
    {'display_name': 'Claude and GPT models', 'buckets': [
        {'bucket_id': 'other-week', 'display_name': 'Weekly', 'remaining': {'case': 'remainingFraction', 'value': 0.6}}]}
]}}}))
