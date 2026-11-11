#!/usr/bin/env python3
"""
Mock config server: 실제 locationx_config_server.py를 경로만 %TEMP%로 돌려서 실행.
systemctl은 라즈베리파이에만 있으므로 restart 요청은 ok=false로 응답된다.

Usage: python mock_config_server.py
Then:  curl http://127.0.0.1:8080/api/status
"""
import os
import sys
import tempfile

BASE = os.path.join(tempfile.gettempdir(), "locationx_mock")
os.environ.setdefault("LOCATIONX_BASE_DIR", BASE)
os.environ.setdefault("LOCATIONX_DST_LOCATOR",
                      os.path.join(BASE, "service", "locator_config.json"))
os.environ.setdefault("LOCATIONX_DST_POSITIONING",
                      os.path.join(BASE, "service", "positioning_config.json"))

os.makedirs(os.path.join(BASE, "service"), exist_ok=True)

AGENT_DIR = os.path.normpath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..", "..", "..", "..",
    "Locator", "locationx_position_server_config", "files", "payload", "agents"))
sys.path.insert(0, AGENT_DIR)

import locationx_config_server  # noqa: E402

print(f"[MOCK] base dir : {BASE}")
print(f"[MOCK] agent dir: {AGENT_DIR}")
locationx_config_server.main()
