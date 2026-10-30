"""Refresh hashes for EXPLICITLY reviewed paths only. Does not discover new files.
Run only after reviewing the source, templates and approved-paths.json for secrets.
No subprocesses, network, or imports from the project.
"""
from pathlib import Path
import hashlib
import json
import sys

root = Path(__file__).resolve().parent.parent
approved = json.loads((root / 'release/approved-paths.json').read_text(encoding='utf-8'))
entries = []
seen = set()
for item in approved['files']:
    source, destination = item['source'], item['destination']
    for name in (source, destination):
        path = Path(name)
        if path.is_absolute() or '..' in path.parts or ':' in name or '\\' in name:
            sys.exit('release/approved-paths.json | unsafe-path')
    if destination.casefold() in seen:
        sys.exit('release/approved-paths.json | duplicate-destination')
    seen.add(destination.casefold())
    path = root / source
    if path.is_symlink() or not path.is_file():
        sys.exit(source + ' | missing-file-or-link')
    entries.append(dict(item, sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
manifest = {'format': 1, 'release': '0.1.0-rc1', 'files': entries}
(root / 'release/files.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f'Reviewed manifest refreshed: {len(entries)} explicit entries')
