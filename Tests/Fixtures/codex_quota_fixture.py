#!/usr/bin/python3
"""Invented account/quota protocol peer. No credentials, network or chat methods."""
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import time

mode = Path(sys.argv[0]).name.removeprefix('codex-')
root = Path(sys.argv[0]).parent
assert sys.argv[1:] == ['app-server']
assert Path(os.environ['CODEX_HOME']).resolve() == (root / 'home').resolve()
assert not any(os.environ.get(k) for k in ['OPENAI_API_KEY', 'OPENAI_BASE_URL', 'LD_PRELOAD'])

def read(method, ident=None):
    obj = json.loads(sys.stdin.readline())
    assert obj['method'] == method
    if ident is not None:
        assert obj['id'] == ident
    return obj

def send(ident, result):
    print(json.dumps({'id': ident, 'result': result}), flush=True)

read('initialize', 1)
if select.select([sys.stdin], [], [], 0)[0]:
    raise SystemExit(31)
if mode in ['cancel', 'timeout']:
    (root / 'ready').write_text('ready')
    time.sleep(10)
if mode == 'overflow':
    print('SYNTHETIC-PRIVATE' * 80000, file=sys.stderr, flush=True)
    time.sleep(10)
if mode == 'group':
    subprocess.Popen([sys.executable, '-c',
        'import time,pathlib,sys; p=pathlib.Path(sys.argv[1]);\nwhile True: p.write_text(str(time.monotonic_ns())); time.sleep(0.02)', str(root / 'heartbeat')],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.monotonic() + 2
    while not (root / 'heartbeat').exists() and time.monotonic() < deadline:
        time.sleep(0.01)
if mode == 'bad-json':
    print('SYNTHETIC-PRIVATE malformed message', flush=True)
    time.sleep(10)
if mode == 'error':
    print(json.dumps({'id': 1, 'error': {'code': -1, 'message': 'SYNTHETIC-PRIVATE'}}), flush=True)
    time.sleep(10)
if mode == 'wrong-id':
    send(3, {})
    time.sleep(10)
send(1, {'userAgent': 'fixture'})
read('initialized')
assert read('account/read', 2)['params']['refreshToken'] is False
account = {'type': 'chatgpt', 'email': 'person@example.test', 'planType': 'pro'}
send(2, {'account': None if mode == 'signed-out' else account})
read('account/rateLimits/read', 3)
limits = {'accountId': 'synthetic-workspace', 'rateLimitsByLimitId': {'codex': {
    'limitId': 'codex', 'primary': {'usedPercent': 27, 'windowDurationMins': 300, 'resetsAt': int(time.time()) + 7200},
    'credits': {'balance': '12.5', 'unlimited': False, 'hasCredits': True}}}}
limits['rateLimitResetCredits'] = {'availableCount': 2, 'credits': [{'id': 'synthetic-reset-do-not-redeem'}]}
if mode == 'missing-identity':
    limits.pop('accountId')
send(3, limits)
assert read('account/read', 4)['params']['refreshToken'] is False
if mode == 'rotation':
    account['email'] = 'different@example.test'
send(4, {'account': account})
# The reader must stop its owned group after collecting the final result.
time.sleep(10)
