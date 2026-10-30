"""Offline static release checks. Never imports project modules or runs project commands.
Output is restricted to relative paths, problem categories, and aggregate counts.
"""
from pathlib import Path, PurePosixPath
import argparse
import configparser
import hashlib
import json
import re
import sys

SECRET = re.compile(r'(?:sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----)')
PRIVATE_PATH = re.compile(r'(?i)\b[a-z]:[\\/]users[\\/](?!public\b|default\b)[^\\/\s]+')
CREDENTIAL_URL = re.compile(r'''https?://[^/\s"'<>]*@|https?://[^\s"'<>]*[?&](?:token|key|password|secret)=''', re.I)
ASSIGNMENT = re.compile(r'''(?im)^\s*["']?(?:api[_-]?key|access[_-]?token|refresh[_-]?token|password|secret)["']?[ \t]*[:=][ \t]*["']?([A-Za-z0-9_./+=$!:-]{8,})''')
DATA_DIRS = {'sessions', 'cache', 'logs', 'reports', 'backups', 'records', '.git', 'test-output'}
DATA_SUFFIXES = {'.jsonl', '.log', '.reg', '.lnk', '.pfx', '.p12', '.pem', '.key', '.exe', '.zip', '.7z'}


def decode(data):
    try:
        return data.decode('utf-8-sig')
    except UnicodeError:
        return data.decode('gb18030')


def safe_relative(name):
    p = PurePosixPath(name.replace('\\', '/'))
    return bool(name) and not p.is_absolute() and '..' not in p.parts and ':' not in name


def check(root):
    issues = []
    def issue(path, kind):
        issues.append((str(path), kind))
    count = 0
    for p in sorted(root.rglob('*')):
        rel = p.relative_to(root)
        if p.is_symlink():
            issue(rel, 'link-prohibited')
            continue
        if not p.is_file():
            continue
        count += 1
        if (any(x.lower() in DATA_DIRS or x.lower().startswith('sync-backup') for x in rel.parts)
                or p.suffix.lower() in DATA_SUFFIXES or p.name in {'.env', '.npmrc', 'models-store.json', 'trust.json', 'archive.local.json', 'PRIVATE-DO-NOT-PUBLISH.txt'}):
            issue(rel, 'private-runtime-data-or-binary')
        try:
            text = decode(p.read_bytes())
        except UnicodeError:
            issue(rel, 'unreviewed-binary')
            continue
        for rx, kind in [(SECRET, 'secret-pattern'), (PRIVATE_PATH, 'personal-path'), (CREDENTIAL_URL, 'credential-url')]:
            if rx.search(text):
                issue(rel, kind)
        # Only config-like literal assignments: do not print the matching text.
        if p.suffix.lower() in {'.json', '.ini', '.env', '.yaml', '.yml', '.toml'}:
            for m in ASSIGNMENT.finditer(text):
                value = m.group(1)
                if not value.startswith('$') and value not in {'api_key', 'REPLACE_ME'}:
                    issue(rel, 'literal-secret-assignment')
            if p.suffix.lower() == '.json':
                try:
                    obj = json.loads(text)
                    if p.name == 'auth.json' and obj != {}:
                        issue(rel, 'nonempty-public-auth')
                except (ValueError, TypeError):
                    issue(rel, 'invalid-json')
        if p.suffix.lower() == '.py':
            try:
                compile(text, str(rel), 'exec')
            except SyntaxError:
                issue(rel, 'python-syntax')
        if p.suffix.lower() in {'.ps1', '.bat', '.cmd', '.vbs'} and 'third-party' not in rel.parts:
            pattern = r'''Join-Path \$Root ['"]([^'"\r\n]+\.(?:ps1|bat|cmd|vbs|md|txt|json|ini))['"]'''
            for target in re.findall(pattern, text):
                target = target.replace(chr(92), '/')
                if not (root / target).exists() and not target.startswith(('logs/', 'reports/', 'runtime/')) and target != 'archive.local.json':
                    issue(rel, 'missing-relative-reference')
    for name in ['config.ini', 'config.example.ini', 'release/defaults/config.ini']:
        p = root / name
        # Live config is ignored in Git source exports; defaults and example are mandatory.
        if not p.exists() and name == 'config.ini':
            continue
        try:
            cfg = configparser.ConfigParser()
            cfg.read_string(p.read_text(encoding='utf-8-sig'))
            if cfg['deepseek']['api_key'] or not cfg['deepseek']['base_url'] or not cfg['deepseek']['model']:
                issue(name, 'invalid-public-config')
        except (OSError, KeyError, configparser.Error):
            issue(name, 'invalid-ini-structure')
    try:
        manifest = json.loads((root / 'release/files.json').read_text(encoding='utf-8-sig'))
        destinations = set()
        for entry in manifest['files']:
            source, dest = entry['source'], entry['destination']
            if not safe_relative(source) or not safe_relative(dest) or dest.lower() in destinations:
                issue('release/files.json', 'unsafe-or-duplicate-path')
                continue
            destinations.add(dest.lower())
            actual = hashlib.sha256((root / source).read_bytes()).hexdigest()
            if actual != entry['sha256']:
                issue(source, 'reviewed-hash-mismatch')
        for target in ['config.ini', 'pi-home/agent/auth.json', 'pi-home/agent/settings.json']:
            entries = [e for e in manifest['files'] if e['destination'] == target]
            if len(entries) != 1 or entries[0]['source'] != 'release/defaults/' + target:
                issue('release/files.json', 'unsafe-default-mapping')
    except (OSError, KeyError, ValueError, TypeError):
        issue('release/files.json', 'invalid-or-missing-manifest')
    for path, kind in sorted(set(issues)):
        print(f'{path} | {kind}')
    print(f'Static release scan: {count} files; {len(set(issues))} issues')
    return not issues


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('root', nargs='?', type=Path, default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args()
    sys.exit(0 if check(args.root.resolve()) else 1)
