#!/usr/bin/env python3
"""Fail when the Mac and repository firmware disagree on the BLE contract."""

import json
import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
UUID_PATTERN = re.compile(
    r"7f0d4e66-2ac2-4a71-bfbe-4ef61a0e5c0[1-4]", re.IGNORECASE
)
EXPECTED_UUIDS = {
    f"7f0d4e66-2ac2-4a71-bfbe-4ef61a0e5c0{suffix}" for suffix in range(1, 5)
}


def source_uuids(path):
    return {match.lower() for match in UUID_PATTERN.findall(path.read_text())}


def require(condition, message):
    if not condition:
        raise SystemExit(message)


swift_uuids = source_uuids(
    REPO_ROOT / "Sources" / "TokenLinkDevice" / "CoreBluetoothDeviceBridge.swift"
)
firmware_uuids = source_uuids(
    REPO_ROOT / "firmware" / "stopwatch-c152" / "src" / "CodexMicroBle.cpp"
)
require(swift_uuids == EXPECTED_UUIDS, f"Unexpected Mac GATT UUIDs: {swift_uuids}")
require(
    firmware_uuids == EXPECTED_UUIDS,
    f"Unexpected C152 firmware GATT UUIDs: {firmware_uuids}",
)

catalog = json.loads((REPO_ROOT / "firmware" / "catalog.json").read_text())
products = {product["id"]: product for product in catalog["products"]}
c152 = products.get("m5stack-stopwatch-c152")
require(c152 is not None, "C152 is missing from firmware/catalog.json")
require(
    c152["protocol_versions"] == [1, 2],
    f"Unexpected catalog protocol versions: {c152['protocol_versions']}",
)
require(
    re.search(
        r'\\"protocol_versions\\":\[1,2\]',
        (
            REPO_ROOT
            / "firmware"
            / "stopwatch-c152"
            / "src"
            / "CodexMicroBle.cpp"
        ).read_text(),
    )
    is not None,
    "C152 capabilities no longer advertise protocol v1 and v2",
)

print("Mac and C152 firmware BLE contracts agree (C01-C04, protocol v1/v2).")
