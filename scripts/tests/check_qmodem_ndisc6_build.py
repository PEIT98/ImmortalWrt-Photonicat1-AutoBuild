#!/usr/bin/env python3
"""在正式固件编译前，用 musl 编译并检查 QModem 的 ndisc6 源码。"""

import argparse
import hashlib
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile


PROGRAMS = (
    "usr/bin/ndisc6",
    "usr/bin/rdisc6",
    "usr/bin/rltraceroute6",
    "usr/bin/tcptraceroute6",
    "usr/bin/tracert6",
    "usr/sbin/rdnssd",
)


def make_value(source: str, name: str) -> str:
    matches = re.findall(rf"^{re.escape(name)}\s*:?=\s*(\S[^\n]*)$", source, re.M)
    if len(matches) != 1:
        raise ValueError(f"ndisc6 的 {name} 定义缺失或重复")
    return matches[0].strip()


def run(*args: str, cwd: Path, env: dict[str, str] | None = None) -> None:
    result = subprocess.run(args, cwd=cwd, env=env, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"{' '.join(args)} 失败：\n{(result.stdout + result.stderr)[-8000:]}")


def check(feed: Path, downloads: Path) -> None:
    source = (feed / "Makefile").read_text(encoding="utf-8")
    version = make_value(source, "PKG_VERSION")
    expected_hash = make_value(source, "PKG_HASH")
    flags = make_value(source, "TARGET_CFLAGS +")
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", version):
        raise ValueError(f"ndisc6 版本格式已变化：{version}")
    if not re.fullmatch(r"[0-9a-f]{64}", expected_hash):
        raise ValueError("ndisc6 缺少可信的 SHA256 校验值")
    archive = downloads / f"ndisc6-{version}.tar.bz2"
    actual_hash = hashlib.sha256(archive.read_bytes()).hexdigest()
    if actual_hash != expected_hash:
        raise ValueError(f"ndisc6 源码 SHA256 不匹配：{actual_hash}")
    compiler = shutil.which("musl-gcc")
    if compiler is None:
        raise ValueError("缺少 musl-gcc；请安装 musl-tools")
    machine = subprocess.check_output(["gcc", "-dumpmachine"], text=True).strip()

    with tempfile.TemporaryDirectory(prefix="ndisc6-musl-") as temp:
        tempdir = Path(temp)
        with tarfile.open(archive) as tar:
            tar.extractall(tempdir, filter="data")
        source_dir = tempdir / f"ndisc6-{version}"
        if not (source_dir / "configure").is_file():
            raise ValueError("ndisc6 源码归档结构已变化")
        build = tempdir / "build"
        build.mkdir()
        dest = tempdir / "install"
        cflags = f"-O2 {flags} -idirafter /usr/include -idirafter /usr/include/{machine}"
        run(str(source_dir / "configure"), "--disable-nls", "--prefix=/usr",
            f"CC={compiler}", "LDFLAGS=-static", f"CFLAGS={cflags}", cwd=build)
        run("make", "-j2", cwd=build)
        run("make", "install", f"DESTDIR={dest}", cwd=build)
        missing = [name for name in PROGRAMS if not (dest / name).is_file()]
        if missing:
            raise ValueError(f"ndisc6 安装结果缺少：{', '.join(missing)}")
    print(f"ndisc6 {version}：SHA256、musl 编译及 6 个程序安装检查通过。")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("feed", type=Path)
    parser.add_argument("downloads", type=Path)
    args = parser.parse_args()
    try:
        check(args.feed, args.downloads)
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError, tarfile.TarError) as exc:
        parser.exit(1, f"::error::{exc}\n")


if __name__ == "__main__":
    main()
