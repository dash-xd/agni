#!/usr/bin/env python3
"""Protocol regression tests without Redis or a VM."""
import importlib.util
import io
import pathlib
import sys
import unittest

source = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("agni_integration_probe", source)
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

class FakeSocket:
    def __init__(self, response):
        self.response = response
        self.sent = b""
    def sendall(self, data):
        self.sent += data
    def makefile(self, mode):
        assert mode == "rb"
        return io.BytesIO(self.response)

class RespContract(unittest.TestCase):
    def test_auth_framing_and_simple_reply(self):
        conn = FakeSocket(b"+OK\r\n")
        self.assertEqual(probe.resp(conn, "AUTH", "probot_state", "secret"), ("ok", "OK"))
        self.assertEqual(conn.sent, b"*3\r\n$4\r\nAUTH\r\n$12\r\nprobot_state\r\n$6\r\nsecret\r\n")
    def test_denied_reply_is_noperm_only(self):
        probe.denied(("error", "NOPERM denied"), "denied")
        with self.assertRaises(RuntimeError):
            probe.denied(("error", "WRONGPASS"), "denied")
        with self.assertRaises(RuntimeError):
            probe.denied(("null", None), "denied")
    def test_null_and_integer(self):
        self.assertEqual(probe.resp(FakeSocket(b"$-1\r\n"), "GET", "key"), ("null", None))
        self.assertEqual(probe.resp(FakeSocket(b":0\r\n"), "PUBLISH", "topic", "msg"), ("integer", 0))
    def test_truncated_response_rejected(self):
        with self.assertRaises(RuntimeError):
            probe.resp(FakeSocket(b"$4\r\nab"), "GET", "key")

if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]])
