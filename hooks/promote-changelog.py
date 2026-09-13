#!/usr/bin/env python3
"""Promote [Unreleased] in CHANGELOG.md to a versioned section.

Usage:
    promote-changelog.py v0.3.0
    promote-changelog.py 0.3.0 --date 2026-09-12
"""

import argparse
import datetime
import pathlib
import re
import sys

EMPTY_SECTIONS = ["Added", "Changed", "Fixed", "Removed"]
VERSION_RE = re.compile(r"^##\s+\[([^\]]+)\]\s*(?:-\s*(\S+))?\s*$")


def split_changelog(text):
    lines = text.splitlines(keepends=True)
    start = end = None
    for i, line in enumerate(lines):
        m = VERSION_RE.match(line)
        if not m:
            continue
        if m.group(1) == "Unreleased":
            start = i
        elif start is not None:
            end = i
            break
    if start is None:
        sys.exit("error: no ## [Unreleased] section found")
    if end is None:
        end = len(lines)
    return (
        "".join(lines[:start]),
        "".join(lines[start + 1 : end]),
        "".join(lines[end:]),
    )


def has_content(body):
    return any(line.strip().startswith("-") for line in body.splitlines())


def fresh_unreleased():
    out = ["## [Unreleased]\n\n"]
    for section in EMPTY_SECTIONS:
        out.append(f"### {section}\n\n")
    return "".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("version")
    ap.add_argument("--date", default=datetime.date.today().isoformat())
    ap.add_argument("--file", default="CHANGELOG.md")
    args = ap.parse_args()

    path = pathlib.Path(args.file)
    text = path.read_text()
    header, body, tail = split_changelog(text)

    if not has_content(body):
        sys.exit("error: [Unreleased] is empty; nothing to release")

    version = args.version.lstrip("v")
    versioned = f"## [{version}] - {args.date}\n{body.rstrip()}\n\n"
    path.write_text(header + fresh_unreleased() + "\n" + versioned + tail)
    print(f"promoted [Unreleased] -> [{version}] - {args.date}")


if __name__ == "__main__":
    main()
