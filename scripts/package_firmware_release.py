#!/usr/bin/env python3
"""Build deterministic C152 release assets from PlatformIO outputs."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import zipfile
from datetime import datetime, timezone
from pathlib import Path


SCHEMA_VERSION = 1
PRODUCT_ID = "m5stack-stopwatch-c152"
ZIP_TIMESTAMP = (1980, 1, 1, 0, 0, 0)
FLASH_FILES = {
    "bootloader.bin": 0x0,
    "partitions.bin": 0x8000,
    "boot_app0.bin": 0xE000,
    "firmware.bin": 0x10000,
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_version(firmware_root: Path) -> str:
    header = (firmware_root / "include" / "CodexMicroBle.h").read_text()
    match = re.search(r'kFirmwareVersion\[\]\s*=\s*"([^"]+)"', header)
    if match is None:
        raise RuntimeError("Could not read kFirmwareVersion from CodexMicroBle.h")
    return match.group(1)


def git_value(repo_root: Path, *arguments: str) -> str:
    result = subprocess.run(
        ["git", *arguments],
        cwd=repo_root,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def published_at(repo_root: Path) -> str:
    epoch = int(
        os.environ.get("SOURCE_DATE_EPOCH")
        or git_value(repo_root, "show", "-s", "--format=%ct", "HEAD")
    )
    return datetime.fromtimestamp(epoch, tz=timezone.utc).isoformat().replace(
        "+00:00", "Z"
    )


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def zip_entry(archive: zipfile.ZipFile, source: Path, destination: str) -> None:
    info = zipfile.ZipInfo(destination, ZIP_TIMESTAMP)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o644 << 16
    archive.writestr(info, source.read_bytes())


def zip_json(archive: zipfile.ZipFile, value: object, destination: str) -> None:
    info = zipfile.ZipInfo(destination, ZIP_TIMESTAMP)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o644 << 16
    archive.writestr(
        info, (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()
    )


def merge_binary(
    pio: Path, firmware_root: Path, build_dir: Path, output: Path
) -> None:
    command = [
        str(pio),
        "pkg",
        "exec",
        "--package",
        "tool-esptoolpy",
        "--",
        "esptool.py",
        "--chip",
        "esp32s3",
        "merge_bin",
        "-o",
        str(output),
        "--flash_mode",
        "dio",
        "--flash_freq",
        "80m",
        "--flash_size",
        "16MB",
    ]
    for name, offset in FLASH_FILES.items():
        command.extend([hex(offset), str(build_dir / name)])
    subprocess.run(command, cwd=firmware_root, check=True)


def package_release(
    repo_root: Path,
    output_dir: Path,
    release_version: str,
    pio: Path,
    revision: str | None = None,
) -> Path:
    firmware_root = repo_root / "firmware" / "stopwatch-c152"
    embedded = source_version(firmware_root)
    if embedded != f"{release_version}-tokenlink":
        raise RuntimeError(
            f"Release version {release_version!r} does not match embedded firmware {embedded!r}"
        )

    build_dir = firmware_root / ".pio" / "build" / "m5stack-stopwatch"
    release_files = {
        **{name: build_dir / name for name in FLASH_FILES},
        "firmware.elf": build_dir / "firmware.elf",
        "partition-table.csv": firmware_root / "partitions" / "default_16MB.csv",
        "LICENSE": firmware_root / "LICENSE",
        "NOTICE.md": firmware_root / "NOTICE.md",
    }
    missing = [str(path) for path in release_files.values() if not path.is_file()]
    if missing:
        raise RuntimeError("Missing firmware release inputs:\n" + "\n".join(missing))

    output_dir.mkdir(parents=True, exist_ok=True)
    generated_patterns = (
        "TokenLink-StopWatch-C152-*.bin",
        "TokenLink-StopWatch-C152-*.zip",
    )
    for pattern in generated_patterns:
        for stale in output_dir.glob(pattern):
            if stale.is_file() or stale.is_symlink():
                stale.unlink()
    for name in ("firmware-manifest.json", "SHA256SUMS"):
        stale = output_dir / name
        if stale.is_file() or stale.is_symlink():
            stale.unlink()

    merged_name = f"TokenLink-StopWatch-C152-{release_version}.bin"
    merged_path = output_dir / merged_name
    merge_binary(pio, firmware_root, build_dir, merged_path)

    files_manifest = {
        name: {
            "offset": FLASH_FILES.get(name),
            "sha256": sha256(path),
            "size": path.stat().st_size,
        }
        for name, path in sorted(release_files.items())
    }
    image_manifest: dict[str, object] = {
        "schema_version": SCHEMA_VERSION,
        "product_id": PRODUCT_ID,
        "variant": "wireless",
        "version": release_version,
        "source_revision": revision
        or git_value(repo_root, "rev-parse", "HEAD"),
        "protocol_versions": [1, 2],
        "files": files_manifest,
        "merged_image": {
            "file": merged_name,
            "offset": 0,
            "sha256": sha256(merged_path),
            "size": merged_path.stat().st_size,
        },
        "flash": {
            "chip": "esp32s3",
            "baud": 1_500_000,
            "flash_size": "16MB",
            "flash_mode": "dio",
            "flash_frequency": "80m",
        },
        "verification": {
            "kind": "serial-marker",
            "serial_marker": "CODEX_MICRO_STOPWATCH_READY",
        },
    }

    archive_name = f"TokenLink-StopWatch-C152-{release_version}.zip"
    archive_path = output_dir / archive_name
    with zipfile.ZipFile(archive_path, "w") as archive:
        for name, source in sorted(release_files.items()):
            zip_entry(archive, source, name)
        zip_entry(archive, merged_path, merged_name)
        zip_json(archive, image_manifest, "image-manifest.json")

    resolved_revision = revision or git_value(repo_root, "rev-parse", "HEAD")
    manifest = {
        "schema_version": SCHEMA_VERSION,
        "product": {
            "id": PRODUCT_ID,
            "display_name": "M5Stack StopWatch Dev Kit C152",
            "chip": "esp32s3",
        },
        "release": {
            "version": release_version,
            "channel": "stable",
            "published_at": published_at(repo_root),
            "source_revision": resolved_revision,
        },
        "minimum_tokenlink_version": "0.2.1",
        "protocol_versions": [1, 2],
        "images": [
            {
                "id": "wireless",
                "display_name": "Default wireless",
                "artifact": {
                    "file": merged_name,
                    "sha256": sha256(merged_path),
                    "size": merged_path.stat().st_size,
                    "flash_offset": 0,
                },
                "archive": {
                    "file": archive_name,
                    "sha256": sha256(archive_path),
                    "size": archive_path.stat().st_size,
                },
                "requires_usb_during_use": False,
                "verification": image_manifest["verification"],
            }
        ],
    }
    manifest_path = output_dir / "firmware-manifest.json"
    write_json(manifest_path, manifest)

    checksum_targets = sorted(
        path for path in output_dir.iterdir() if path.name != "SHA256SUMS"
    )
    checksums = "".join(
        f"{sha256(path)}  {path.name}\n" for path in checksum_targets
    )
    (output_dir / "SHA256SUMS").write_text(checksums)
    return manifest_path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--output", type=Path, default=Path("dist/firmware"))
    parser.add_argument("--pio", type=Path, required=True)
    parser.add_argument("--source-revision")
    args = parser.parse_args()
    repo_root = Path(__file__).resolve().parent.parent
    manifest = package_release(
        repo_root,
        args.output.resolve(),
        args.version,
        args.pio.resolve(),
        revision=args.source_revision,
    )
    print(manifest)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
