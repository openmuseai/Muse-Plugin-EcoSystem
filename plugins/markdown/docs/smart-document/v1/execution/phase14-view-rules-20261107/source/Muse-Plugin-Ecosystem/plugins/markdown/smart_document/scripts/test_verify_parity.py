"""Prevent a green ledger check from becoming a false release acceptance."""
import copy
import json
import tempfile
import unittest
from pathlib import Path
from verify_parity import DOCS, validate


class ParityGateTest(unittest.TestCase):
    def setUp(self):
        self.data = json.loads((DOCS / 'siyuan-collaboration-parity.json').read_text())

    def test_false_full_acceptance_is_rejected(self):
        self.data['fullParityReady'] = True
        errors, complete = validate(self.data)
        self.assertFalse(complete)
        self.assertTrue(any('fullParityReady' in e for e in errors))

    def test_missing_and_duplicate_requirements_are_rejected(self):
        self.data['requirements'][-1] = copy.deepcopy(self.data['requirements'][0])
        errors, complete = validate(self.data)
        self.assertFalse(complete)
        self.assertTrue(any('without duplicates' in e for e in errors))

    def test_aggregate_slice_pass_is_not_specific_case_evidence(self):
        case = self.data['requirements'][0]
        case.update(implementation='implemented', completion='passed', knownGaps=[], verification={p: 'passed' for p in case['requiredPlatforms']})
        with tempfile.TemporaryDirectory() as directory:
            docs = Path(directory)
            (docs / 'aggregate.json').write_text(json.dumps({'status': 'passed-cloud-slice'}))
            case['evidence'] = ['aggregate.json']
            errors, complete = validate(self.data, docs=docs)
        self.assertFalse(complete)
        self.assertEqual(len([e for e in errors if e.startswith('SY-01: No requirement-specific')]), 4)


if __name__ == '__main__':
    unittest.main()
