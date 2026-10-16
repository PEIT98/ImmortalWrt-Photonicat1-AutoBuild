#!/usr/bin/env python3
"""将上游在线升级包适配到光影猫；上游布局变化时停止，避免漏改。"""
from pathlib import Path
import json
import re
import shutil
import sys

plugin = Path(sys.argv[1])
assets = Path(__file__).resolve().parent.parent / "online-upgrade"
root = plugin / "root"
makefile = plugin / "Makefile"
text = makefile.read_text()
assert "PKG_NAME:=luci-app-online-upgrade" in text, "在线升级软件源包名已变更"
text, count = re.subn(r"^LUCI_DEPENDS:=.*$", "LUCI_DEPENDS:=+luci-base +luci-compat +curl +jsonfilter +jq +ca-bundle +flock +coreutils-sha256sum", text, flags=re.M)
assert count == 1, "在线升级依赖定义已变更"
# 上游恢复 CGI 未检查登录身份；改用已认证的 LuCI 备份恢复页。
text, count = re.subn(r"\t\$\(INSTALL_DIR\) \$\(1\)/www/cgi-bin\n\t\$\(INSTALL_BIN\) .*online-upgrade-restore.*\n", "", text)
assert count == 1 or "/www/cgi-bin/online-upgrade-restore" not in text, "恢复 CGI 安装规则已变更"
makefile.write_text(text)
(root / "www/cgi-bin/online-upgrade-restore").unlink(missing_ok=True)

for source, target in [
    ("online-upgrade.sh", "usr/bin/online-upgrade.sh"),
    ("online-upgrade.config", "etc/config/online-upgrade"),
    ("99-online-upgrade", "etc/uci-defaults/99-online-upgrade"),
]:
    shutil.copyfile(assets / source, root / target)
    if source != "online-upgrade.config":
        (root / target).chmod(0o755)
(root / "etc/uci-defaults/90-online-upgrade-auto").write_text("#!/bin/sh\n# 插件随本项目固件提供，不在开机时下载或重装软件。\nexit 0\n")
(root / "etc/uci-defaults/90-online-upgrade-auto").chmod(0o755)
(root / "lib/upgrade/keep.d/online-upgrade").write_text("/etc/config/online-upgrade\n")

js_path = root / "www/luci-static/resources/view/system/online-upgrade.js"
js = js_path.read_text()
if "photonicat-online-upgrade-adapted" not in js:
    def replace_once(old, new):
        global js
        assert js.count(old) == 1, f"在线升级前端定位失败：{old[:70]}"
        js = js.replace(old, new, 1)

    def replace_region(start, end, replacement):
        global js
        assert js.count(start) == 1 and js.count(end) == 1, "在线升级前端函数布局变化"
        first = js.index(start)
        last = js.index(end, first)
        js = js[:first] + replacement + js[last:]

    replace_once('"require ui";', '"require ui";\n"require uci";\n// photonicat-online-upgrade-adapted')
    replace_once("\trender: function() {", "\tload: function() { return uci.load('online-upgrade'); },\n\n\trender: function() {\n\t\tvar cfgRepo = uci.get('online-upgrade', 'settings', 'repo') || 'PEIT98/ImmortalWrt-Photonicat1-AutoBuild';\n\t\tvar cfgTag = uci.get('online-upgrade', 'settings', 'tag') || 'auto';\n\t\tvar cfgProxy = uci.get('online-upgrade', 'settings', 'proxy') || '';\n\t\tvar cfgPattern = uci.get('online-upgrade', 'settings', 'firmware_pattern') || '光影猫一代 squashfs sysupgrade';")
    replace_once("value: 'https://github.com/gooyjq/ImmortalWrt-Builder/releases/tag/Autobuild-x86-64'", "value: 'https://github.com/' + cfgRepo + (cfgTag === 'auto' ? '/releases' : '/releases/tag/' + cfgTag)")
    replace_once("value: 'gooyjq/ImmortalWrt-Builder', readonly: 'readonly'", "value: cfgRepo")
    replace_once("value: 'Autobuild-x86-64', readonly: 'readonly'", "value: cfgTag")
    replace_once("value: 'auto（自动检测）', readonly: 'readonly'", "value: cfgPattern, readonly: 'readonly'")
    replace_once("自动根据路由器架构匹配固件文件", "只匹配光影猫一代 squashfs 升级镜像")
    replace_once("'}, 'https://ghfast.top/')", "', value: cfgProxy})")
    replace_region("\t\tfunction parseUrl() {", "\n\t\tfunction saveCfg()", r'''		function parseUrl() {
			var url = document.getElementById('cfg-url').value.trim();
			var m = url.match(/^https:\/\/github\.com\/([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)\/releases(?:\/tag\/([^\/\s?#]+))?\/?(?:[?#].*)?$/);
			if (!m) { ui.addNotification(null, E('p', '请填写 GitHub Releases 地址'), 'error'); return; }
			document.getElementById('cfg-repo').value = m[1];
			document.getElementById('cfg-tag').value = m[2] || 'auto';
			ui.addNotification(null, E('p', '已解析发布仓库和标签'), 'info');
		}
''')
    replace_region("\t\tfunction saveCfg() {", "\n\t\tfunction toggleAdv()", r'''		function saveCfg() {
			var g = function(id) { return (document.getElementById(id) || {}).value || ''; };
			var entries = {repo: g('cfg-repo').trim(), tag: g('cfg-tag').trim() || 'auto', proxy: g('cfg-proxy').trim()};
			var chain = Promise.resolve();
			Object.keys(entries).forEach(function(key) {
				chain = chain.then(function() {
					return fs.exec('/sbin/uci', ['set', 'online-upgrade.settings.' + key + '=' + entries[key]]);
				}).then(function(r) { if (r.code) throw new Error(r.stderr || '保存失败'); });
			});
			chain.then(function() { return fs.exec('/sbin/uci', ['commit', 'online-upgrade']); })
				.then(function(r) {
					if (r.code) throw new Error(r.stderr || '提交配置失败');
					ui.addNotification(null, E('p', '配置已保存'), 'info');
				}).catch(function(e) { ui.addNotification(null, E('p', e.message), 'error'); });
		}
''')
    replace_region("\t\tfunction startUpgrade(isForce) {", "\n\t\tfunction runUpgrade()", r'''		function startUpgrade(isForce) {
			if (!confirm(isForce ? '重新安装当前发布固件？文件和机型校验仍会执行。请勿断电。' : '下载并校验固件后执行升级？请勿断电。')) return;
			var area = document.getElementById('progress-area');
			if (area) area.style.display = 'block';
			var buttons = ['btn-check', 'btn-upgrade', 'btn-force'];
			function enableButtons() { buttons.forEach(function(id) { var b = document.getElementById(id); if (b) b.disabled = false; }); }
			buttons.forEach(function(id) { var b = document.getElementById(id); if (b) b.disabled = true; });
			var phases = {checking: [5, '正在检查发布信息...'], downloading: [25, '正在下载并核对固件...'], verifying: [65, '正在检查机型兼容性...'], backing_up: [80, '正在备份配置...'], sysupgrade: [95, '已开始系统升级，请等待设备重启...'], up_to_date: [100, '已是最新版本']};
			var busy = false;
			function stopPoll() { if (pollTimer) clearInterval(pollTimer); pollTimer = null; }
			function pollStatus() {
				if (!document.getElementById('progress-area')) { stopPoll(); return; }
				if (busy) return;
				busy = true;
				fs.exec('/bin/cat', ['/tmp/online-upgrade-status']).then(function(r) {
					var status = (r.stdout || '').trim();
					if (status.indexOf('failed:') === 0) {
						stopPoll(); enableButtons();
						updateOutput('\n升级失败：' + status.substring(7) + '\n');
						return;
					}
					var phase = phases[status];
					if (!phase) return;
					var bar = document.getElementById('progress-bar');
					var label = document.getElementById('progress-label');
					var text = document.getElementById('progress-text');
					if (bar) bar.style.width = phase[0] + '%';
					if (label) label.textContent = phase[0] + '%';
					if (text) text.textContent = phase[1];
					if (status === 'sysupgrade') { stopPoll(); showRebootOverlay(); }
					if (status === 'up_to_date') { stopPoll(); enableButtons(); }
				}).catch(function() {}).then(function() { busy = false; });
			}
			fs.exec('/usr/bin/online-upgrade.sh', [isForce ? 'background-force' : 'background']).then(function(r) {
				if (r.code) throw new Error(r.stdout || r.stderr || '无法启动升级');
				stopPoll(); pollTimer = setInterval(pollStatus, 2000); pollStatus();
			}).catch(function(e) { stopPoll(); enableButtons(); updateOutput('升级启动失败：' + e.message + '\n'); });
			window.addEventListener('pagehide', stopPoll, {once: true});
		}
''')
    replace_region("\t\tfunction autoRestore() {", "\n\t\tfunction updateOutput(t)", "\t\tfunction openBackupRestore() { window.location.href = L.url('admin/system/flash'); }\n")
    lines = []
    for line in js.splitlines(keepends=True):
        if "E('button', {id: 'btn-manual-restore'" in line or "E('input', {id: 'manual-backup-file'" in line:
            continue
        if "E('button', {id: 'btn-auto-restore'" in line:
            line = "\t\t\t\t\tE('button', {class: 'btn cbi-button', click: openBackupRestore}, '备份与恢复'),\n"
        if "E('button', {id: 'btn-force'" in line:
            line = line.replace("style: 'padding:", "style: 'display:none;padding:")
        lines.append(line)
    js = "".join(lines)
    first = js.index("\t\tfunction runCheck()")
    last = js.index("\t\tfunction showRebootOverlay()", first)
    check = js[first:last].replace("forceBtn.style.display = 'inline-block'", "forceBtn.style.display = 'none'", 2)
    check = check.replace("// 解析并显示版本信息", "if (text.indexOf('当前构建比发布版本新') >= 0) { var b = document.getElementById('btn-force'); if (b) b.style.display = 'none'; }\n\t\t\t\t// 解析并显示版本信息")
    js = js[:first] + check + js[last:]
    js = js.replace("路由器正在重启", "设备正在升级").replace("固件刷写完成，配置将自动恢复，等待路由器重启...", "系统升级已开始，请等待设备重启后重新连接。")
    js_path.write_text(js)

acl_path = root / "usr/share/rpcd/acl.d/luci-app-online-upgrade.json"
acl = json.loads(acl_path.read_text())
entry = acl["luci-app-online-upgrade"]
read_files = entry["read"]["file"]
write_files = entry["write"]["file"]
for path in ("/usr/bin/online-upgrade.sh", "/bin/sh"):
    read_files.pop(path, None)
    write_files[path] = ["exec"]
write_files["/sbin/uci"] = ["exec"]
acl_path.write_text(json.dumps(acl, ensure_ascii=False, indent=2) + "\n")
menu_path = root / "usr/share/luci/menu.d/luci-app-online-upgrade.json"
menu = json.loads(menu_path.read_text())
menu["admin/system/online_upgrade"]["depends"] = {"acl": ["luci-app-online-upgrade"]}
menu_path.write_text(json.dumps(menu, ensure_ascii=False, indent=2) + "\n")
print("在线升级已适配光影猫：发布匹配、完整性/机型校验、真实进度和 LuCI 备份恢复。")
