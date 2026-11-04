import os
import subprocess
import sys
import unittest
from unittest.mock import patch

import hello_world


class TestHelloWorld(unittest.TestCase):
    def test_default_version(self) -> None:
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(hello_world.get_version(), "0.1.0-dev")

    def test_custom_app_version(self) -> None:
        with patch.dict(os.environ, {"APP_VERSION": "2.4.6"}, clear=True):
            self.assertEqual(hello_world.get_version(), "2.4.6")

    def test_cli_version_output(self) -> None:
        env = os.environ.copy()
        env["APP_VERSION"] = "1.2.3"
        result = subprocess.run(
            [sys.executable, "hello_world.py", "--version"],
            env=env,
            capture_output=True,
            text=True,
            check=True,
        )
        self.assertIn("App version: 1.2.3", result.stdout)


if __name__ == "__main__":
    unittest.main()
