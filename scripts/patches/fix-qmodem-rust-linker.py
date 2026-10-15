#!/usr/bin/env python3
"""Adapt QModem's Rust cross-linker without changing C compilation.

With CCache enabled, OpenWrt TARGET_CC is 'ccache <target>-gcc'.
Cargo expects one linker executable, not a shell command with spaces.
"""

from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("Usage: fix-qmodem-rust-linker.py <qmodem Makefile>")

path = Path(sys.argv[1])
if not path.is_file():
    raise SystemExit(f"QModem Makefile missing: {path}")

source = path.read_text()
old = '\tTARGET_CC="$(TARGET_CC)" \\\n'
new = '\tTARGET_CC="$(TARGET_CROSS)gcc" \\\n'
if source.count(old) != 1 or "define Build/CompileRust\n" not in source:
    raise SystemExit("QModem Rust build layout changed; aborting safe linker fix")
if source.count(new) != 0:
    raise SystemExit("Rust GCC override already exists unexpectedly")

pre, rest = source.split("define Build/CompileRust\n", 1)
rust_block, post = rest.split("\nendef", 1)
if rust_block.count(old) != 1:
    raise SystemExit("Rust TARGET_CC assignment missing within Build/CompileRust")
rust_block = rust_block.replace(old, new, 1)
patched = pre + "define Build/CompileRust\n" + rust_block + "\nendef" + post
if patched.replace(new, old, 1) != source:
    raise SystemExit("QModem patch roundtrip verification failed")
path.write_text(patched)
print("QModem Rust uses $(TARGET_CROSS)gcc; C builds still use CCache")
