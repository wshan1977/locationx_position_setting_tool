#!/usr/bin/env python3
"""
Mock discover agent: 실기기 없이 앱의 UDP 스캔을 테스트.
UDP 40010에서 DISCOVER를 받으면 가짜 로케이터 카드 N개 + MQTT 서버 카드 1개의
DISCOVER_RESPONSE를 순서대로 회신한다 (하나의 프로세스가 LAN 전체를 흉내).

Usage: python mock_discover_agent.py [num_locators]
"""
import json
import socket
import sys
import time

DISCOVER_PORT = 40010

FAKE_LOCATOR_MACS = [
    "4C:5B:B3:CA:D7:1E",
    "4C:5B:B3:CA:D7:2F",
    "4C:5B:B3:CA:D7:3A",
    "4C:5B:B3:CA:D7:4B",
]


def locator_response(i: int, mac: str) -> dict:
    # locationx_locator_config discover agent v1.0.3 응답 형식
    return {
        "type": "DISCOVER_RESPONSE",
        "device": f"aoa-locator-{i + 1}",
        "ip": "127.0.0.1",
        "mac": mac,
        "model": "mock-Linux-rpi",
        "service": {
            "led_udp_port": 40002,
            "discover_port": DISCOVER_PORT,
            "mqtt_udp_port": DISCOVER_PORT,
            "reboot_udp_port": DISCOVER_PORT,
            "service_restart_udp_port": DISCOVER_PORT,
        },
        "mqtt": {"mode": "UDP", "host": "192.168.1.177", "port": 1883, "file": "(mock)"},
        "cap": {"mqtt_set": True, "reboot": True, "service_restart": True},
        "ver": "1.0.3",
        "ts": int(time.time()),
    }


def server_response() -> dict:
    # locationx_mqtt_server_config discover agent v1.0.0 응답 형식 (cap/mqtt 없음)
    return {
        "type": "DISCOVER_RESPONSE",
        "device": "aoa-server-1",
        "ip": "127.0.0.1",
        "mac": "MAC_ERR",
        "model": "mock-Linux-rpi4",
        "service": {"led_udp_port": 40002, "discover_port": DISCOVER_PORT},
        "ver": "1.0.0",
        "ts": int(time.time()),
    }


def main():
    num_locators = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    macs = FAKE_LOCATOR_MACS[:num_locators]

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("0.0.0.0", DISCOVER_PORT))
    print(f"[MOCK DISCOVER] listening UDP :{DISCOVER_PORT} "
          f"({num_locators} locators + 1 server)")

    while True:
        data, addr = sock.recvfrom(4096)
        try:
            msg = json.loads(data.decode("utf-8", errors="ignore"))
        except Exception:
            continue
        if msg.get("type") != "DISCOVER":
            continue

        responses = [locator_response(i, m) for i, m in enumerate(macs)]
        responses.append(server_response())
        for resp in responses:
            sock.sendto(json.dumps(resp).encode("utf-8"), addr)
        print(f"[MOCK DISCOVER] replied {len(responses)} devices to {addr[0]}:{addr[1]}")


if __name__ == "__main__":
    main()
