#!/usr/bin/env python3
"""Small, dependency-free guard; never prints matching values. Not a comprehensive secret detector.

Default: tracked and non-ignored working files. --staged: Git index. --history: all reachable blobs.
No home-directory credential files or network services are read.
"""
import argparse
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
FORBIDDEN_NAMES = {'.env', 'auth.json', '.credentials.json', 'oauth_creds.json',
                   'application_default_credentials.json', 'credentials.json',
                   'preferences.json', 'snapshot.json'}
FORBIDDEN_SUFFIXES = {'.key', '.pem', '.p12', '.pfx', '.keychain', '.keychain-db',
                      '.mobileprovision', '.provisionprofile', '.sealed', '.memgraph', '.crash', '.ips', '.log'}
RULES = [
    ('private key', re.compile(rb'-----BEGIN (?:[A-Z0-9]+ )?PRIVATE KEY-----')),
    ('provider token', re.compile(rb'\b(?:sk-(?:proj-|ant-)?[A-Za-z0-9_-]{20,}|AIza[A-Za-z0-9_-]{30,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b')),
    ('JWT', re.compile(rb'\beyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}\b')),
    ('assigned secret', re.compile(rb'''(?i)["']?(?:access[_-]?token|refresh[_-]?token|api[_-]?key|client[_-]?secret|bearer)["']?\s*[:=]\s*["'][A-Za-z0-9_./+=-]{24,}["']''')),
]

def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)

def inspect(name, data):
    path = Path(name)
    forbidden = path.name in FORBIDDEN_NAMES or path.suffix in FORBIDDEN_SUFFIXES
    forbidden |= path.name.startswith('.env.') and path.name not in {'.env.example', '.env.sample'}
    forbidden |= path.name.startswith('captured-') and path.suffix == '.json'
    forbidden |= any(part in {'local-data', 'diagnostics', 'captures'} for part in path.parts)
    findings = [(name, 'private runtime/signing file')] if forbidden else []
    for label, pattern in RULES:
        match = pattern.search(data)
        if match:
            line = data[:match.start()].count(b'\n') + 1
            findings.append((f'{name}:{line}', label))
    return findings

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--staged', action='store_true')
    modes.add_argument('--history', action='store_true')
    args = parser.parse_args()
    candidates = []
    if args.history:
        for entry in git('rev-list', '--objects', '--all').decode().splitlines():
            parts = entry.split(' ', 1)
            if len(parts) == 2 and git('cat-file', '-t', parts[0]).strip() == b'blob':
                candidates.append((parts[1], git('cat-file', 'blob', parts[0])))
    else:
        command = ['ls-files', '-z'] if args.staged else ['ls-files', '--cached', '--others', '--exclude-standard', '-z']
        for name in sorted(set(git(*command).decode().split('\0')) - {''}):
            if args.staged:
                candidates.append((name, git('show', ':' + name)))
            elif (ROOT/name).is_file():
                candidates.append((name, (ROOT/name).read_bytes()))
    findings = sorted(set(item for name, data in candidates for item in inspect(name, data)))
    for location, rule in findings:
        print(f'BLOCKED: {location} ({rule}; value redacted)', file=sys.stderr)
    if findings:
        print('Remove private data before commit. Rotate an exposed real secret; deletion does not revoke it.', file=sys.stderr)
        return 1
    print(f'Secret guard: no covered patterns in {len(candidates)} files/blobs. Manual review is still required.')
    return 0

if __name__ == '__main__':
    sys.exit(main())
