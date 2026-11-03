#!/usr/bin/env python3
"""Write a validated immutable identity shared by the updater and release job."""
import datetime
import json
from pathlib import Path
import re
import sys

REPOSITORY = "PEIT98/ImmortalWrt-Photonicat1-AutoBuild"


def stamp(root, version, commit):
    match = re.fullmatch(r"photonicat1-(\d{8})-(\d{6})-(\d+)", version)
    if not match or not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("Invalid firmware tag or builder commit")
    datetime.datetime.strptime(match[1] + match[2], "%Y%m%d%H%M%S")
    target = Path(root) / "files/etc/photonicat-release.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps({
        "repository": REPOSITORY, "board": "ariaboard,photonicat",
        "version": version, "commit": commit,
    }, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    stamp(*sys.argv[1:])
