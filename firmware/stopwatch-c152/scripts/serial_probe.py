#!/usr/bin/env python3
"""Reset the attached ESP32-S3 over DTR and stream its serial diagnostics."""

from __future__ import annotations

import argparse
import fcntl
import os
import select
import struct
import sys
import termios
import time


def set_modem_line(fd: int, request: int, line: int) -> None:
    fcntl.ioctl(fd, request, struct.pack("I", line))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("port")
    parser.add_argument("--seconds", type=float, default=30.0)
    parser.add_argument("--no-reset", action="store_true")
    parser.add_argument("--expect")
    args = parser.parse_args()

    expected = args.expect.encode() if args.expect is not None else None
    search_tail = b""
    found = expected is None

    fd = os.open(args.port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    try:
        attrs = termios.tcgetattr(fd)
        attrs[0] = 0
        attrs[1] = 0
        attrs[2] = termios.CS8 | termios.CLOCAL | termios.CREAD
        attrs[3] = 0
        attrs[4] = termios.B115200
        attrs[5] = termios.B115200
        termios.tcsetattr(fd, termios.TCSANOW, attrs)

        if not args.no_reset:
            set_modem_line(fd, termios.TIOCMBIC, termios.TIOCM_DTR)
            time.sleep(0.15)
            set_modem_line(fd, termios.TIOCMBIS, termios.TIOCM_DTR)

        deadline = time.monotonic() + args.seconds
        while time.monotonic() < deadline:
            readable, _, _ = select.select([fd], [], [], 0.5)
            if not readable:
                continue
            chunk = os.read(fd, 4096)
            if chunk:
                sys.stdout.buffer.write(chunk)
                sys.stdout.buffer.flush()
                if expected is not None:
                    searchable = search_tail + chunk
                    if expected in searchable:
                        found = True
                        break
                    overlap = max(0, len(expected) - 1)
                    search_tail = searchable[-overlap:] if overlap else b""
    finally:
        os.close(fd)
    if not found:
        print(f"Expected serial marker not observed: {args.expect}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
