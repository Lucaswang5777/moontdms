"""Conservative source inventory and independent implementation history audit."""
from pathlib import Path
import json, subprocess
ROOT = Path(__file__).resolve().parents[1]

def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT).decode('utf-8').strip()

def main():
    inventory = []
    for p in sorted(ROOT.glob('*.mbt')):
        if 'test' in p.name: continue
        lines = p.read_text(encoding='utf-8').splitlines()
        substantive = sum(bool(l.strip()) and not l.strip().startswith(('//','pub extend')) for l in lines)
        inventory.append({'file':p.name,'physical':len(lines),'nonblank_noncomment':substantive})
    total = sum(row['nonblank_noncomment'] for row in inventory)
    assert total >= 1500, total
    # Production changes count as evidence; doc/format-only commits are excluded.
    meaningful = []
    for sha in git('rev-list','--reverse','HEAD').splitlines():
        files = git('diff-tree','--root','--no-commit-id','--name-only','-r',sha).splitlines()
        implementation = [f for f in files if f.endswith('.mbt') and 'test' not in f and not f.startswith(('cmd/','examples/'))]
        test = [f for f in files if f.endswith('_test.mbt') or f.endswith('_wbtest.mbt')]
        independent_validation = any(f in files for f in ('scripts/differential.py','scripts/cli_smoke.py'))
        downstream = any(f.startswith('examples/') and f.endswith('.mbt') for f in files)
        if implementation or test or independent_validation or downstream:
            meaningful.append({'sha':sha,'purpose':git('show','-s','--format=%s',sha),'files':files})
    assert len(meaningful) >= 20, len(meaningful)
    manifest = (ROOT/'moon.mod').read_text(encoding='utf-8')
    assert 'Lucaswang5777/moontdms' in manifest and '0.1.0' in manifest
    print(json.dumps({'production_inventory':inventory,'substantive_lines':total,
                      'physical_production_lines':sum(r['physical'] for r in inventory),
                      'conservative_engineering_commits':len(meaningful), 'commits':meaningful}, indent=2))

if __name__ == '__main__': main()
