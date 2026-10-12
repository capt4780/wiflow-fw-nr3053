"""Bootstrap failure reasons must reach syslog (LuCI System Log), not only /tmp."""
from pathlib import Path
import unittest

SRC = (Path(__file__).resolve().parents[1] /
       "package/wiflow-setup/files/usr/lib/wiflow/bootstrap").read_text()


class BootstrapSyslogTests(unittest.TestCase):
    def test_log_also_writes_syslog(self):
        line = [l for l in SRC.splitlines() if l.startswith("log(){")][0]
        self.assertIn("logger -t wiflow-bootstrap", line)
        self.assertIn('>> "$LOG"', line)


if __name__ == "__main__":
    unittest.main()
