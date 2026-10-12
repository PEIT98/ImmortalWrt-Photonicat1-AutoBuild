#!/usr/bin/env python3
"""Patch upstream luci-mod-battstatus and the bundled Aurora theme for Photonicat1.

Only browser presentation is changed; /usr/libexec/rpcd/luci.battstatus stays upstream.
Run after 'feeds update/install' and before 'make'. Fail if upstream changes incompatibly.
"""
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("Usage: python3 scripts/fix-aurora-battstatus.py IMMORTALWRT_ROOT")

root = Path(sys.argv[1]).resolve()
battery = root / "feeds/luci/modules/luci-mod-battstatus/htdocs/luci-static/resources/preload/battstatus.js"
aurora_css = root / "package/luci-theme-aurora/htdocs/luci-static/aurora/main.css"
patch_css = Path(__file__).with_name("aurora-battstatus.css")

for p in (battery, aurora_css, patch_css):
    if not p.is_file():
        raise SystemExit(f"::error::Battery compatibility patch: required file not found: {p}")

# Original plugin incorrectly quotes JS template strings with single quotes.
# When <= 30%, querySelector() returns null, its innerHTML assignment throws,
# and the indicator polling promise fails.
old = """\t\t\t\tif (typeof info.color != 'undefined') {
\t\t\t\t\tinfo.element = document.querySelector('[data-indicator="${info.name}"]');
\t\t\t\t\tinfo.element.innerHTML = '<span style="color:${info.color}">${info.status}</span>';
\t\t\t\t}"""
new = """\t\t\t\t// Keep ui.showIndicator()'s text node intact for future 5s updates.
\t\t\t\t// Avoid HTML injection, selector interpolation bugs and stale colors.
\t\t\t\tconst batteryIndicator = document.querySelector(
\t\t\t\t\t'#indicators > span[data-indicator="' + info.name + '"]');
\t\t\t\tif (batteryIndicator) {
\t\t\t\t\tbatteryIndicator.title = info.status;
\t\t\t\t\tif (auroraTheme) {
\t\t\t\t\t\t// Align with the local 28px battery-pill style; override icon-only CSS.
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
\t\t\t\t\t\t\tbatteryIndicator.style.setProperty(key, styles[key], 'important');
\t\t\t\t\t}
\t\t\t\t\t// Do not keep the low-battery color after returning above 30%.
\t\t\t\t\tif (info.color)
\t\t\t\t\t\tbatteryIndicator.style.setProperty('color', info.color, 'important');
\t\t\t\t\telse
\t\t\t\t\t\tbatteryIndicator.style.removeProperty('color');
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
    print("Battery JS: fixed invalid indicator selector and low-battery update")
elif new in body:
    print("Battery JS: already patched")
else:
    raise SystemExit("::error::Upstream battstatus.js changed; manual review required before overwriting")

# The Aurora shell gives every #indicators span font-size: 0 and icon size 20px.
# Battery indicators do not have a matching icon mask, so their charge text vanishes.
css = aurora_css.read_text()
marker = "/* Photonicat1 Aurora battery indicator compatibility */"
extra = patch_css.read_text()
if marker not in extra:
    raise SystemExit("::error::Battery CSS patch marker missing")
if marker not in css:
    aurora_css.write_text(css + "\n" + extra.strip() + "\n")
    print("Aurora CSS: restored battery percentage visibility and disabled empty icon")
else:
    print("Aurora CSS: already patched")
