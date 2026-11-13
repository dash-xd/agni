#!/usr/bin/env python3
import unittest
from pathlib import Path
from unittest.mock import patch
import service_relay


class RelayTests(unittest.TestCase):
    def test_endpoint_rejects_invalid(self):
        with patch.dict("os.environ", {"SHOAL_FARCASTER_SERVICE_PORT": "0"}):
            with self.assertRaisesRegex(ValueError, "port"):
                service_relay.endpoint()
        with patch.dict("os.environ", {"SHOAL_SERVICE_PATH": "http://example.com/"}):
            with self.assertRaisesRegex(ValueError, "path"):
                service_relay.endpoint()

    def test_ssh_relay_is_pinned_and_disposable(self):
        code = (Path(__file__).parent / "service_relay.py").read_text()
        for item in ("StrictHostKeyChecking=yes", "ExitOnForwardFailure=yes",
                     "127.0.0.1:18080", "stop(second)", "stop(first)",
                     "AGNI_SHOAL_DIRECT_NETWORK=not-assessed"):
            self.assertIn(item, code)
        self.assertNotIn("podman stop", code)
        self.assertNotIn("AGNI_SHOAL_FATLINE=passed", code)


if __name__ == "__main__":
    unittest.main()
