"""Diff against captured pre-edit files (production files are untracked)."""
from pathlib import Path
import difflib
import json

here = Path(__file__).resolve().parent
root = here.parents[1]
patches = []
results = []
for name in ['p2p_signal_client.gd', 'p2p_signal_server.gd', 'p2p_invite.gd']:
    old = (here / 'before' / (name + '.txt')).read_text(encoding='utf-8').splitlines(True)
    new = (root / 'scripts/net/p2p' / name).read_text(encoding='utf-8').splitlines(True)
    diff = list(difflib.unified_diff(old, new, fromfile='before/' + name, tofile='scripts/net/p2p/' + name))
    additions = [line[1:] for line in diff if line.startswith('+') and not line.startswith('+++')]
    removals = [line for line in diff if line.startswith('-') and not line.startswith('---')]
    assert diff, 'Expected changed source: ' + name
    assert all(line.rstrip('\r\n') == line.rstrip() for line in additions), 'Trailing whitespace: ' + name
    patches.extend(diff)
    results.append({'file': name, 'added_lines': len(additions), 'removed_lines': len(removals), 'added_line_whitespace_clean': True})
(here / 'changes.patch').write_text(''.join(patches), encoding='utf-8')
(here / 'diff-results.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
print(json.dumps(results, indent=2))
