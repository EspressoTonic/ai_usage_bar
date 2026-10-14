#!/usr/bin/env python3
"""Synthetic checks, including a deleted secret remaining in Git history; no real tokens."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile

module_path = Path(__file__).with_name('check_secrets.py')
spec = importlib.util.spec_from_file_location('guard', module_path)
guard = importlib.util.module_from_spec(spec); spec.loader.exec_module(guard)
token = 'sk' + '-' + 'SYNTHETIC' * 6
assert guard.inspect('source.swift', token.encode())
assert guard.inspect('nested/auth.json', b'{}')
assert guard.inspect('nested/.env.production', b'')
assert guard.inspect('signing/private.p12', b'')
assert not guard.inspect('.env.example', b'API_KEY=replace-me')
assert not guard.inspect('.codex/environments/environment.toml', b'name="Run"')
with tempfile.TemporaryDirectory(prefix='aiub-secret-guard-', dir='/private/tmp') as scratch:
    root = Path(scratch); (root/'script').mkdir()
    (root/'script/check_secrets.py').write_bytes(module_path.read_bytes())
    def git(*args):
        subprocess.run(['git', *args], cwd=root, check=True, capture_output=True)
    git('init')
    (root/'example.txt').write_text(token)
    git('add', 'example.txt')
    result = subprocess.run(['python3', 'script/check_secrets.py', '--staged'], cwd=root, capture_output=True, text=True)
    assert result.returncode == 1 and token not in result.stderr
    git('-c', 'user.name=Synthetic Test', '-c', 'user.email=test@example.invalid', 'commit', '-m', 'Synthetic fixture')
    (root/'example.txt').unlink(); git('add', '-u')
    git('-c', 'user.name=Synthetic Test', '-c', 'user.email=test@example.invalid', 'commit', '-m', 'Remove fixture')
    result = subprocess.run(['python3', 'script/check_secrets.py', '--history'], cwd=root, capture_output=True, text=True)
    assert result.returncode == 1 and token not in result.stderr
print('Secret guard synthetic cases passed, including staged data and deleted history.')
