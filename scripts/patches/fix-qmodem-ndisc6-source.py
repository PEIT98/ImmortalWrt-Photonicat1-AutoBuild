#!/usr/bin/env python3
"""升级 QModem ndisc6，并清理只适用于 1.0.2 的补丁。"""

import argparse
import hashlib
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
LEGACY_PATCHES = {
    "100-favor_bsd.patch": "cda0e50a5ee800e1a3a4ef364c1b96ee4f95d595faa304fd6ddadcdaa9a95302",
    "110-strverscmp.patch": "e45cb59f871a0b75b2554a8dfc431b9636f2d3354cea6c6c4912e7cf5a505678",
}
OLD_INSTALL = "\t$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/{rl,tcp}traceroute6 $(1)/usr/bin/\n"
NEW_INSTALL = (
    "\t$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/rltraceroute6 "
    "$(PKG_INSTALL_DIR)/usr/bin/tcptraceroute6 $(1)/usr/bin/\n"
)
OLD_CFLAGS = "TARGET_CFLAGS += -std=c99\n"
NEW_CFLAGS = "TARGET_CFLAGS += -std=gnu11\n"


def patch_source(source: str) -> str:
    if all(source.count(line + "\n") == 1 for line in NEW):
        pass
    elif "PKG_VERSION:=1.0.2\n" not in source:
        # 上游已升级时保留它的版本、校验值与打包定义。
        if "PKG_NAME:=ndisc6\n" not in source:
            raise ValueError("上游 ndisc6 包定义已变化，请检查")
        return source
    else:
        if any(source.count(line + "\n") != 1 for line in OLD):
            raise ValueError("QModem ndisc6 1.0.2 包定义已变化，请检查源码地址")
        for old, new in zip(OLD, NEW):
            source = source.replace(old + "\n", new + "\n", 1)

    # /bin/sh 不展开 {rl,tcp}，明确列出 1.0.8 安装的两个程序。
    if source.count(OLD_INSTALL) == 1:
        source = source.replace(OLD_INSTALL, NEW_INSTALL, 1)
    elif source.count(NEW_INSTALL) != 1:
        raise ValueError("QModem traceroute6 安装定义已变化，请检查")

    # 1.0.8 的 trace-tcp.c 使用 <stdalign.h> 的 alignas，需要 C11。
    if source.count(OLD_CFLAGS) == 1:
        source = source.replace(OLD_CFLAGS, NEW_CFLAGS, 1)
    elif source.count(NEW_CFLAGS) != 1:
        raise ValueError("QModem ndisc6 编译标准已变化，请检查")
    return source


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("makefile", type=Path)
    args = parser.parse_args()
    try:
        old = args.makefile.read_text(encoding="utf-8")
        new = patch_source(old)
        managed = all(new.count(line + "\n") == 1 for line in NEW)
        obsolete = []
        if managed:
            for name, expected in LEGACY_PATCHES.items():
                path = args.makefile.parent / "patches" / name
                if path.exists():
                    actual = hashlib.sha256(path.read_bytes()).hexdigest()
                    if actual != expected:
                        raise ValueError(f"QModem {name} 内容已变化，请检查补丁")
                    obsolete.append(path)
        if old != new:
            args.makefile.write_text(new, encoding="utf-8")
        for path in obsolete:
            path.unlink()
        if old != new or obsolete:
            print("QModem ndisc6：升级到 1.0.8，使用 GNU C11，移除不兼容的旧补丁，保留 IPv6 工具。")
        else:
            print("QModem ndisc6：上游已有新版本或修复，无需替换。")
    except (OSError, ValueError) as exc:
        parser.exit(1, f"::error::{exc}\n")


if __name__ == "__main__":
    main()
