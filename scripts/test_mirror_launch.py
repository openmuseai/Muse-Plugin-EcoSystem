import unittest
from mirror_approved_registry import select_launch_servers
class LaunchSelection(unittest.TestCase):
    def setUp(self):
        self.pin={'name':'example/slides','version':'1.0.0','sha256':'a'*64}
        self.record={'server':{'name':'example/slides','version':'1.0.0','packages':[{'registryType':'mcpb','fileSha256':'a'*64}]}}
    def test_only_pinned_approved_plugin_is_distributed(self):
        self.assertEqual(select_launch_servers([{'server':{'name':'example/other','version':'1.0.0'}},self.record],{'officialMcp':[self.pin]}),[self.record])
    def test_missing_version_or_wrong_digest_prevents_replacement(self):
        with self.assertRaises(ValueError):select_launch_servers([],{'officialMcp':[self.pin]})
        self.pin['sha256']='b'*64
        with self.assertRaises(ValueError):select_launch_servers([self.record],{'officialMcp':[self.pin]})
    def test_duplicate_pins_are_rejected(self):
        with self.assertRaises(ValueError):select_launch_servers([self.record],{'officialMcp':[self.pin,self.pin]})
if __name__=='__main__':unittest.main()
