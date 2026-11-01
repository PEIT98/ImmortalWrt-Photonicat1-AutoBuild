#!/usr/bin/env python3
"""修复 QModem ndisc6 旧版源码已下线导致的下载失败。"""

import argparse
from pathlib import Path


OLD = (
    "PKG_VERSION:=1.0.2",
    "PKG_SOURCE_URL:=http://www.remlab.net/files/ndisc6",
    "PKG_MD5SUM:=50cb4c19606cf6ff2b7388e71832f579",
)
NEW = (
    "PKG_VERSION:=1.0.8",
    "PKG_SOURCE_URL:=https://www.remlab.net/files/ndisc6",
    "PKG_HASH:=1f2fb2dc1172770aa5a09d39738a44d8b753cc5e2e25e306ca78682f9fea0b4f",
)


def patch_source(source: str) -> str:
    if all(source.count(line + "\n") == 1 for line in NEW):
        return source
    if "PKG_VERSION:=1.0.2\n" not in source:
        # 上游已升级时保留它的版本、校验值与打包定义。
        if "PKG_NAME:=ndisc6\n" not in source:
            raise ValueError("上游 ndisc6 包定义已变化，请检查")
        return source
    if any(source.count(line + "\n") != 1 for line in OLD):
        raise ValueError("QModem ndisc6 1.0.2 包定义已变化，请检查源码地址")
    for old, new in zip(OLD, NEW):
        source = source.replace(old + "\n", new + "\n", 1)
    return source


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("makefile", type=Path)
    args = parser.parse_args()
    try:
        old = args.makefile.read_text(encoding="utf-8")
        new = patch_source(old)
        if old != new:
            args.makefile.write_text(new, encoding="utf-8")
            print("QModem ndisc6：更新为可下载的 1.0.8，保留 IPv6 邻居/路由发现工具。")
        else:
            print("QModem ndisc6：上游已有新版本或修复，无需替换。")
    except (OSError, ValueError) as exc:
        parser.exit(1, f"::error::{exc}\n")


if __name__ == "__main__":
    main()
