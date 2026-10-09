#!/usr/bin/python3

# SPDX-License-Identifier: Apache-2.0
"""Recursively extract archives for direct scanning by ClamAV."""

import argparse
import logging
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from pathlib import Path
from typing import Optional

import libarchive
from libarchive.exception import ArchiveError


class ArchiveWarningFilter(logging.Filter):
    """Record and suppress libarchive's ARCHIVE_WARN diagnostics."""

    def __init__(self):
        super().__init__()
        self.warned = False

    def filter(self, record):
        self.warned = True
        return False


# Archive detection is serial, so one filter can track each probe without locks.
archive_warning_filter = ArchiveWarningFilter()
logging.getLogger("libarchive").addFilter(archive_warning_filter)


def is_archive(path: Path) -> bool:
    """Return whether libarchive cleanly recognizes a non-empty archive."""
    archive_warning_filter.warned = False
    try:
        with libarchive.file_reader(str(path)) as entries:
            has_entry = next(iter(entries), None) is not None
            return has_entry and not archive_warning_filter.warned
    except (ArchiveError, OSError):
        return False


def find_archives(directory: Path):
    """Yield regular archive files without following directory symlinks."""

    def raise_walk_error(error):
        raise error

    for parent, directories, files in os.walk(directory, onerror=raise_walk_error):
        directories[:] = [
            name
            for name in directories
            if not os.path.islink(os.path.join(parent, name))
        ]
        for name in files:
            path = Path(parent, name)
            try:
                mode = os.stat(path, follow_symlinks=False).st_mode
            except FileNotFoundError:
                continue
            if stat.S_ISREG(mode) and is_archive(path):
                yield path


def run_bsdtar(path: Path, output: Path):
    """Drain stderr without retaining more than 8 KiB per extraction."""
    limit = 8192
    diagnostic = bytearray()
    truncated = False
    with subprocess.Popen(
        ["bsdtar", "-xf", path, "-C", output],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    ) as process:
        while True:
            chunk = process.stderr.read(4096)
            if not chunk:
                break
            remaining = limit - len(diagnostic)
            diagnostic.extend(chunk[:remaining])
            truncated = truncated or len(chunk) > remaining
        returncode = process.wait()
    message = diagnostic.decode("utf-8", errors="replace")
    if truncated:
        message += " [stderr truncated after 8192 bytes]"
    return returncode, message


def extract_archive(path: Path) -> Optional[Path]:
    """Extract path beside itself, retaining it if extraction fails."""
    output = Path(f"{path}.d")
    if output.exists() or output.is_symlink():
        print(
            f"Warning: extraction output already exists for {path!r}",
            file=sys.stderr,
        )
        return None

    temporary_output = Path(
        tempfile.mkdtemp(prefix=".clamav-extract-", dir=path.parent)
    )
    try:
        returncode, diagnostic = run_bsdtar(path, temporary_output)
        if returncode != 0:
            # repr keeps untrusted control characters out of task log formatting.
            print(
                f"Warning: could not extract archive {path!r} "
                f"(bsdtar exit {returncode}): {diagnostic!r}",
                file=sys.stderr,
            )
            return None

        temporary_output.rename(output)
        path.unlink()
        return output
    finally:
        if temporary_output.exists():
            shutil.rmtree(temporary_output)


def extract_archives(root: Path, workers: int) -> bool:
    """Recursively extract archives with bounded running and queued jobs."""
    pending = [root]
    succeeded = True
    with ThreadPoolExecutor(max_workers=workers) as pool:
        while pending:
            archives = iter(
                path for directory in pending for path in find_archives(directory)
            )
            next_pending = []
            outstanding = set()
            exhausted = False
            while outstanding or not exhausted:
                # Bound submissions as well as workers: map() eagerly queues jobs.
                while not exhausted and len(outstanding) < 2 * workers:
                    path = next(archives, None)
                    if path is None:
                        exhausted = True
                    else:
                        outstanding.add(pool.submit(extract_archive, path))
                if not outstanding:
                    break
                completed, outstanding = wait(
                    outstanding, return_when=FIRST_COMPLETED
                )
                for future in completed:
                    output = future.result()
                    if output is None:
                        succeeded = False
                    else:
                        next_pending.append(output)
                completed.clear()
            pending = next_pending
    return succeeded


def positive_integer(value: str) -> int:
    try:
        parsed = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("must be an integer") from error
    if parsed < 1:
        raise argparse.ArgumentTypeError("must be positive")
    return parsed


def parse_args():
    parser = argparse.ArgumentParser(
        description="recursively extract archives for direct ClamAV scanning"
    )
    parser.add_argument(
        "--workers",
        type=positive_integer,
        default=8,
        help="maximum concurrent bsdtar processes (default: 8)",
    )
    parser.add_argument("directory", type=Path, help="directory tree to process")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.directory.is_dir():
        print(f"error: not a directory: {args.directory}", file=sys.stderr)
        return 2
    if not extract_archives(args.directory, args.workers):
        print("error: archive extraction incomplete", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
