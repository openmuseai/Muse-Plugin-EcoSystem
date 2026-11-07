"""Regression for a live Cloud process whose Docker dependencies have stopped."""
import tempfile
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import dev_stack


class DependencyRecoveryTest(unittest.TestCase):
    def test_live_cloud_still_reconciles_its_stopped_dependencies(self):
        with tempfile.TemporaryDirectory() as temporary:
            state = Path(temporary)
            (state / 'cloud.pid').write_text('123')
            calls = []
            def run(command, **kwargs):
                calls.append(command)
                return SimpleNamespace(stdout=str(dev_stack.CLOUD / 'target/debug/appflowy_cloud'), returncode=0)
            with patch.object(dev_stack, 'STATE', state), patch('sys.argv', ['dev_stack.py', 'start']), \
                 patch.object(dev_stack, 'ready', return_value=True), \
                 patch.object(dev_stack, 'health', return_value=dict.fromkeys(['auth','postgres','redis','storage'], True)), \
                 patch.object(dev_stack.subprocess, 'run', side_effect=run), \
                 patch.object(dev_stack.subprocess, 'Popen') as spawn:
                dev_stack.main()
            self.assertIn(dev_stack.COMPOSE + ['up', '-d'], calls)
            spawn.assert_not_called()

    def test_untracked_listener_is_rejected_before_any_container_change(self):
        with tempfile.TemporaryDirectory() as temporary:
            with patch.object(dev_stack, 'STATE', Path(temporary)), patch('sys.argv', ['dev_stack.py', 'start']), \
                 patch.object(dev_stack, 'ready', return_value=True), \
                 patch.object(dev_stack.subprocess, 'run') as run:
                with self.assertRaisesRegex(SystemExit, 'untracked service'):
                    dev_stack.main()
                run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
