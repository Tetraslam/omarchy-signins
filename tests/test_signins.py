import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("signins", Path(__file__).resolve().parents[1] / "signins.py")
signins = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signins)


class Details(unittest.TestCase):
    def test_gcloud_messages_are_readable(self):
        self.assertIn("sign in again", signins.gcloud_detail("ERROR: Reauthentication failed. cannot prompt"))
        self.assertEqual(signins.gcloud_detail("invalid_grant: Bad Request"), "Session expired")
        self.assertEqual(signins.gcloud_detail("\nERROR: something else\nmore"), "something else")

    def test_missing_tools_are_skipped(self):
        original = signins.shutil.which
        signins.shutil.which = lambda name: None
        try:
            self.assertEqual([c for check in signins.CHECKS for c in check()], [])
        finally:
            signins.shutil.which = original


if __name__ == "__main__":
    unittest.main()
