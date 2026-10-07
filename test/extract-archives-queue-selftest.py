#!/usr/bin/python3

# SPDX-License-Identifier: Apache-2.0
"""Verify bounded, lazy submission independently of extraction timing."""

import importlib.util
from importlib.machinery import SourceFileLoader
from pathlib import Path
import sys
import unittest
from unittest.mock import patch


extractor_path = sys.argv.pop(1)
# The installed executable has no .py suffix, so specify its source loader.
spec = importlib.util.spec_from_file_location(
    "extractor", extractor_path,
    loader=SourceFileLoader("extractor", extractor_path),
)
extractor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(extractor)


class QueueTest(unittest.TestCase):
    def test_bounded_submission_and_recursion(self):
        for workers in (1, 2, 8):
            for fail in (False, True):
                with self.subTest(workers=workers, fail=fail):
                    active = set()
                    submitted = []
                    discovered = []
                    root = Path("root")
                    nested = Path("nested")

                    class Job:
                        def __init__(self, path):
                            self.path = path

                        def result(self):
                            active.remove(self)
                            if fail and self.path == root / "50":
                                return None
                            return nested if self.path == root / "0" else self.path

                    class Pool:
                        def __init__(self, max_workers):
                            self.max_workers = max_workers

                        def __enter__(self):
                            return self

                        def __exit__(self, *args):
                            pass

                        def submit(pool, function, path):
                            self.assertIs(function, extractor.extract_archive)
                            self.assertLess(len(active), 2 * workers)
                            job = Job(path)
                            active.add(job)
                            submitted.append(path)
                            return job

                    def discover(directory):
                        discovered.append(directory)
                        if directory == root:
                            for number in range(100):
                                # Discovery must pause whenever the queue is full.
                                self.assertLess(len(active), 2 * workers)
                                yield root / str(number)
                        elif directory == nested:
                            yield Path("nested-child")

                    def complete_one(jobs, return_when):
                        self.assertEqual(return_when, extractor.FIRST_COMPLETED)
                        # Complete out of submission order to exercise replenishment.
                        job = max(jobs, key=lambda item: str(item.path))
                        return {job}, jobs - {job}

                    with patch.object(extractor, "ThreadPoolExecutor", Pool), \
                            patch.object(extractor, "find_archives", discover), \
                            patch.object(extractor, "wait", complete_one):
                        self.assertEqual(extractor.extract_archives(root, workers), not fail)
                    self.assertFalse(active)
                    self.assertEqual(len(submitted), 101)
                    self.assertEqual(len(set(submitted)), 101)
                    self.assertIn(nested, discovered)
                    self.assertIn(Path("nested-child"), discovered)


if __name__ == "__main__":
    unittest.main()
