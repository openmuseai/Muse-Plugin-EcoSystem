#!/usr/bin/env python3
"""Check the full parity ledger. Schema validity is not product acceptance."""
import argparse
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT.parent / 'docs/smart-document/v1'
PLATFORMS = {'desktop', 'web', 'ios', 'android'}
EXPECTED = {f'SY-{i:02}' for i in range(1, 37)} | {f'CO-{i:02}' for i in range(1, 15)}
REFERENCE = 'd3af9d5782082b379d45a69eedf4ebcfe8ba6889'


def local_file(root, relative):
    if not isinstance(relative, str) or Path(relative).is_absolute():
        return None
    file = root / relative
    if not file.resolve().is_relative_to(root.resolve()) or file.is_symlink() or not file.is_file():
        return None
    return file


def validate(data, docs=DOCS, content_root=ROOT.parent):
    errors = []
    if data.get('reference', {}).get('commit') != REFERENCE or data.get('reference', {}).get('version') != '3.8.9':
        errors.append('Fixed SiYuan reference changed; review the baseline explicitly')
    requirements = data.get('requirements', [])
    if not isinstance(requirements, list):
        return ['requirements must be a list'], False
    ids = [r.get('id') for r in requirements if isinstance(r, dict)]
    if len(ids) != len(requirements) or len(ids) != len(set(ids)) or set(ids) != EXPECTED:
        errors.append('Require exactly SY-01..36 and CO-01..14 without duplicates')
    all_complete = len(requirements) == len(EXPECTED)
    for requirement in requirements:
        if not isinstance(requirement, dict):
            continue
        case = requirement.get('id', '?')
        fail = lambda message: errors.append(f'{case}: {message}')
        for field in ['name', 'acceptance']:
            if not isinstance(requirement.get(field), str) or not requirement[field].strip():
                fail('Missing ' + field)
        if not re.fullmatch(r'T(?:0[1-9]|1\d|2[0-4])', requirement.get('task', '')):
            fail('Invalid execution task')
        if not local_file(content_root, requirement.get('source')):
            fail('Missing or unsafe source')
        implementation = requirement.get('implementation')
        completion = requirement.get('completion')
        if implementation not in {'planned', 'partial', 'implemented'} or completion not in {'unrun', 'partial', 'passed'}:
            fail('Invalid implementation/completion state')
        required = requirement.get('requiredPlatforms', [])
        verification = requirement.get('verification', {})
        if not isinstance(required, list) or len(required) != 4 or set(required) != PLATFORMS:
            fail('Full multi-platform target must remain desktop/web/ios/android')
        if not isinstance(verification, dict) or set(verification) != PLATFORMS or any(v not in {'unrun', 'partial', 'passed', 'failed'} for v in verification.values()):
            fail('Invalid per-platform verification')
            verification = {}
        gaps = requirement.get('knownGaps')
        evidence = requirement.get('evidence')
        if not isinstance(gaps, list) or any(not isinstance(g, str) or not g.strip() for g in gaps):
            fail('Invalid known gaps')
        if not isinstance(evidence, list) or any(not isinstance(e, str) for e in evidence):
            fail('Invalid evidence list')
            evidence = []
        receipts = []
        for relative in evidence:
            file = local_file(docs, relative)
            if file is None:
                fail('Missing or unsafe evidence: ' + relative)
                continue
            if file.suffix == '.json':
                try:
                    record = json.loads(file.read_text())
                    if isinstance(record, dict):
                        receipts.extend(record.get('parityCases', []))
                except (ValueError, TypeError):
                    fail('Invalid JSON evidence: ' + relative)
        if completion == 'partial' and not evidence:
            fail('Partial progress requires traceable evidence')
        for platform, state in verification.items():
            if state == 'passed' and not any(
                isinstance(r, dict) and r.get('requirement') == case and r.get('platform') == platform
                and r.get('status') == 'passed' and isinstance(r.get('checks'), list) and r['checks']
                for r in receipts
            ):
                fail('No requirement-specific passed receipt for ' + platform)
        complete = implementation == 'implemented' and completion == 'passed' and not gaps and all(verification.get(p) == 'passed' for p in PLATFORMS)
        if completion == 'passed' and not complete:
            fail('Passed requires implementation, no gaps, and all platform receipts')
        all_complete = all_complete and complete
    if data.get('fullParityReady') is not all_complete:
        errors.append('fullParityReady must equal the actual complete requirements gate')
    return errors, all_complete and not errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--require-complete', action='store_true')
    args = parser.parse_args()
    data = json.loads((DOCS / 'siyuan-collaboration-parity.json').read_text())
    errors, complete = validate(data)
    if errors:
        sys.exit('\n'.join(errors))
    print('Parity ledger valid: 36 editing + 14 collaboration requirements; full product acceptance: ' + ('passed' if complete else 'NOT COMPLETE'))
    if args.require_complete and not complete:
        sys.exit('Full parity gate rejected: incomplete implementation/platform coverage; see each knownGaps entry')


if __name__ == '__main__':
    main()
