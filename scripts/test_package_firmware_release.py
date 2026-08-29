#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).with_name("package_firmware_release.py")
SPEC = importlib.util.spec_from_file_location("package_firmware_release", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class PackageFirmwareReleaseTests(unittest.TestCase):
    def make_repository(self, root: Path) -> None:
        firmware = root / "firmware" / "stopwatch-c152"
        (firmware / "include").mkdir(parents=True)
        (firmware / "include" / "CodexMicroBle.h").write_text(
            'static constexpr char kFirmwareVersion[] = "1.2.3-tokenlink";\n'
        )
        (firmware / "partitions").mkdir()
        (firmware / "partitions" / "default_16MB.csv").write_text(
            "nvs,data,nvs,0x9000,0x5000\n"
        )
        (firmware / "LICENSE").write_text("MIT\n")
        (firmware / "NOTICE.md").write_text("Notice\n")
        build = firmware / ".pio" / "build" / "m5stack-stopwatch"
        build.mkdir(parents=True)
        for name in [*MODULE.FLASH_FILES, "firmware.elf"]:
            (build / name).write_bytes(f"content:{name}".encode())

    def fake_merge(
        self, pio: Path, firmware_root: Path, build_dir: Path, output: Path
    ) -> None:
        del pio, firmware_root, build_dir
        output.write_bytes(b"merged firmware")

    @patch.object(MODULE, "published_at", return_value="2026-08-30T00:00:00Z")
    @patch.object(MODULE, "git_value", return_value="a" * 40)
    def test_packages_wireless_archive_and_server_manifest(
        self, _git_value, _published_at
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.make_repository(root)
            with patch.object(MODULE, "merge_binary", side_effect=self.fake_merge):
                manifest_path = MODULE.package_release(
                    root, root / "dist", "1.2.3", Path("pio")
                )

            manifest = json.loads(manifest_path.read_text())
            self.assertEqual(manifest["product"]["id"], "m5stack-stopwatch-c152")
            self.assertEqual(manifest["protocol_versions"], [1, 2])
            image = manifest["images"][0]
            self.assertEqual(image["artifact"]["flash_offset"], 0)
            archive = root / "dist" / image["archive"]["file"]
            self.assertEqual(MODULE.sha256(archive), image["archive"]["sha256"])
            with zipfile.ZipFile(archive) as packaged:
                names = set(packaged.namelist())
                self.assertIn("bootloader.bin", names)
                self.assertIn("TokenLink-StopWatch-C152-1.2.3.bin", names)
                image_manifest = json.loads(packaged.read("image-manifest.json"))
                self.assertEqual(image_manifest["files"]["firmware.bin"]["offset"], 0x10000)

    def test_rejects_release_version_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.make_repository(root)
            with self.assertRaisesRegex(RuntimeError, "does not match"):
                MODULE.package_release(
                    root, root / "dist", "9.9.9", Path("pio"), revision="a" * 40
                )


if __name__ == "__main__":
    unittest.main()
