#!/usr/bin/env python3
"""Patch luci-mod-battstatus only; NEVER alter Aurora theme source files.

The plugin sets its own styles at runtime when Aurora is active.
Battery RPC / pcat-mgr integration remains upstream and unchanged.
"""
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("Usage: python3 scripts/fix-aurora-battstatus.py IMMORTALWRT_ROOT")

root = Path(sys.argv[1]).resolve()
battery = root / "feeds/luci/modules/luci-mod-battstatus/htdocs/luci-static/resources/preload/battstatus.js"
if not battery.is_file():
    raise SystemExit(f"::error::Battery plugin not found: {battery}")

# Original plugin incorrectly quotes JS template strings with single quotes.
# When <= 30%, querySelector() returns null, its innerHTML assignment throws,
# and the indicator polling promise fails.
old = """\t\t\t\tif (typeof info.color != 'undefined') {
\t\t\t\t\tinfo.element = document.querySelector('[data-indicator="${info.name}"]');
\t\t\t\t\tinfo.element.innerHTML = '<span style="color:${info.color}">${info.status}</span>';
\t\t\t\t}"""
new = """\t\t\t\t// Photonicat1 battery-only patch; no Aurora file changes.
\t\t\t\t// Keep ui.showIndicator()'s text node intact for 5-second updates.
\t\t\t\tlet el = null;
\t\t\t\tfor (const node of document.querySelectorAll('#indicators > span[data-indicator]')) {
\t\t\t\t\tif (node.getAttribute('data-indicator') == info.name) {
\t\t\t\t\t\tel = node;
\t\t\t\t\t\tbreak;
\t\t\t\t\t}
\t\t\t\t}
\t\t\t\tif (el) {
\t\t\t\t\tel.title = info.status;
\t\t\t\t\tif (auroraTheme) {
\t\t\t\t\t\t// The battery plugin hides Aurora's generic empty icon at runtime.
\t\t\t\t\t\t// Nothing in the Aurora theme package is edited.
\t\t\t\t\t\tif (!document.getElementById('photonicat-battery-only-style')) {
\t\t\t\t\t\t\tconst sheet = document.createElement('style');
\t\t\t\t\t\t\tsheet.id = 'photonicat-battery-only-style';
\t\t\t\t\t\t\tsheet.textContent = '#indicators span[data-indicator^="battery-"]::before { display:none !important; content:none !important; }';
\t\t\t\t\t\t\tdocument.head.appendChild(sheet);
\t\t\t\t\t\t}
\t\t\t\t\t\tconst styles = {
\t\t\t\t\t\t\tdisplay: 'inline-flex',
\t\t\t\t\t\t\t'align-items': 'center',
\t\t\t\t\t\t\t'justify-content': 'center',
\t\t\t\t\t\t\twidth: 'auto',
\t\t\t\t\t\t\t'min-width': 'max-content',
\t\t\t\t\t\t\t'max-width': 'none',
\t\t\t\t\t\t\theight: '28px',
\t\t\t\t\t\t\t'min-height': '28px',
\t\t\t\t\t\t\tpadding: '0 10px',
\t\t\t\t\t\t\tmargin: '0 4px',
\t\t\t\t\t\t\t'vertical-align': 'middle',
\t\t\t\t\t\t\t'font-size': '12px',
\t\t\t\t\t\t\t'line-height': '28px',
\t\t\t\t\t\t\t'font-weight': '500',
\t\t\t\t\t\t\tbackground: 'rgba(37,99,235,.10)',
\t\t\t\t\t\t\tborder: '1px solid rgba(37,99,235,.20)',
\t\t\t\t\t\t\t'border-radius': '6px',
\t\t\t\t\t\t\t'text-indent': '0',
\t\t\t\t\t\t\t'white-space': 'nowrap',
\t\t\t\t\t\t\toverflow: 'visible',
\t\t\t\t\t\t\tvisibility: 'visible',
\t\t\t\t\t\t\topacity: '1',
\t\t\t\t\t\t\t'box-sizing': 'border-box',
\t\t\t\t\t\t\t'clip-path': 'none',
\t\t\t\t\t\t\ttransform: 'none'
\t\t\t\t\t\t};
\t\t\t\t\t\tfor (const key in styles)
\t\t\t\t\t\t\tel.style.setProperty(key, styles[key], 'important');
\t\t\t\t\t\tif (info.color)
\t\t\t\t\t\t\tel.style.setProperty('color', info.color, 'important');
\t\t\t\t\t\telse
\t\t\t\t\t\t\tel.style.removeProperty('color');
\t\t\t\t\t} else {
\t\t\t\t\t\t// Preserve native appearance under Bootstrap/other themes.
\t\t\t\t\t\tif (info.color)
\t\t\t\t\t\t\tel.style.setProperty('color', info.color);
\t\t\t\t\t\telse
\t\t\t\t\t\t\tel.style.removeProperty('color');
\t\t\t\t\t}
\t\t\t\t}"""
body = battery.read_text()

# On Aurora keep the visible header compact, while the title still contains
# the complete Charging/Not Charging state. Bootstrap keeps upstream wording.
call_before = '\t\t\t\tui.showIndicator(info.name, info.status, null, info.state);'
call_after = """\t\t\t\tconst auroraTheme = document.querySelector('link[href*="/luci-static/aurora/main.css"]') != null;
\t\t\t\tconst batteryLabel = auroraTheme && info.valid
\t\t\t\t\t? (info.charging ? '⚡ ' : '🔋 ') + info.percentage + '%'
\t\t\t\t\t: info.status;
\t\t\t\tui.showIndicator(info.name, batteryLabel, null, info.state);"""
if call_before in body:
    body = body.replace(call_before, call_after, 1)
elif call_after not in body:
    raise SystemExit("::error::Upstream battery indicator call changed; check manually")

if old in body:
    battery.write_text(body.replace(old, new, 1))
    print("Battery plugin: fixed low-battery indicator and inserted theme-safe presentation")
elif new in body:
    print("Battery plugin: already patched")
else:
    raise SystemExit("::error::Upstream battstatus.js changed; manual review required before overwriting")

