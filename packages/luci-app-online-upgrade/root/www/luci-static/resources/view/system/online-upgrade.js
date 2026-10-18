"use strict";
"require view";
"require fs";
"require ui";
"require uci";
// photonicat-online-upgrade-adapted

return view.extend({
	handleSave: null,
	handleSaveApply: null,
	handleReset: null,

	load: function() { return uci.load('online-upgrade'); },

	render: function() {
		var cfgRepo = uci.get('online-upgrade', 'settings', 'repo') || 'PEIT98/ImmortalWrt-Photonicat1-AutoBuild';
		var cfgTag = uci.get('online-upgrade', 'settings', 'tag') || 'auto';
		var cfgProxy = uci.get('online-upgrade', 'settings', 'proxy') || '';
		var cfgPattern = uci.get('online-upgrade', 'settings', 'firmware_pattern') || '光影猫一代 squashfs sysupgrade';
		var _this = this;
		var pollTimer = null;

		function runCheck() {
			var btn = document.getElementById('btn-check');
			if (!btn) return;
			btn.disabled = true;
			btn.textContent = '检查中...';
			updateOutput('正在检查固件更新，请稍候...\n');

			fs.exec('/usr/bin/online-upgrade.sh', ['check']).then(function(r) {
				var text = r.stdout + (r.stderr ? '\n' + r.stderr : '');
				updateOutput(text);
				btn.disabled = false;
				btn.textContent = '检查更新';

				var resultEl = document.getElementById('check-result');
				if (!resultEl) return;

				if (text.indexOf('发现新固件') >= 0) {
					resultEl.textContent = '✅ 发现新固件！';
					resultEl.style.color = '';
					var upgBtn = document.getElementById('btn-upgrade');
					var forceBtn = document.getElementById('btn-force');
					if (upgBtn) upgBtn.style.display = 'inline-block';
					if (forceBtn) forceBtn.style.display = 'none';
				} else if (text.indexOf('403') >= 0 || text.indexOf('60次') >= 0) {
					resultEl.textContent = '❌ 检查失败 - 访问超60次/小时受限';
					resultEl.style.color = '';
					var forceBtn = document.getElementById('btn-force');
					if (forceBtn) forceBtn.style.display = 'none';
				} else if (text.indexOf('错误') >= 0) {
					resultEl.textContent = '❌ 检查失败';
					resultEl.style.color = '';
					var forceBtn = document.getElementById('btn-force');
					if (forceBtn) forceBtn.style.display = 'none';
				} else {
					resultEl.textContent = '✓ 已是最新';
					resultEl.style.color = '#4CAF50';
					var forceBtn = document.getElementById('btn-force');
					if (forceBtn) forceBtn.style.display = 'inline-block';
					var upgBtn = document.getElementById('btn-upgrade');
					if (upgBtn) upgBtn.style.display = 'none';
				}

				if (text.indexOf('当前构建比发布版本新') >= 0) { var b = document.getElementById('btn-force'); if (b) b.style.display = 'none'; }
				// 解析并显示版本信息
				var lines = text.split('\n');
				for (var i = 0; i < lines.length; i++) {
					var m = lines[i].match(/最新固件:\s*(\S+)/);
					if (m) {
						var el = document.getElementById('latest-ver');
						if (el) el.textContent = m[1];
					}
					m = lines[i].match(/文件大小:\s*(.+)/);
					if (m) {
						var el = document.getElementById('latest-size');
						if (el) el.textContent = m[1].trim();
					}
					// 新版本号
					m = lines[i].match(/新固件版本:\s*(.+)/);
					if (m) {
						var el = document.getElementById('new-ver');
						if (el) el.textContent = m[1].trim();
					}
					// 检测依据
					m = lines[i].match(/检测依据:\s*(.+)/);
					if (m) {
						var el = document.getElementById('check-reason');
						if (el) el.textContent = m[1].trim();
					}
				}
			}).catch(function(e) {
				updateOutput('检测失败: ' + e.message);
				btn.disabled = false;
				btn.textContent = '检查更新';
			});
		}

		function showRebootOverlay() {
			if (document.getElementById('reboot-overlay')) return;
			var seconds = 100;
			var overlay = E('div', {id: 'reboot-overlay', style: 'position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,0.85);z-index:9999;display:flex;flex-direction:column;align-items:center;justify-content:center;color:#fff;font-family:sans-serif;'}, [
				E('div', {style: 'font-size:28px;font-weight:600;margin-bottom:10px;'}, '🔄 设备正在升级'),
				E('div', {style: 'font-size:14px;color:#aaa;margin-bottom:20px;'}, '系统升级已开始，请等待设备重启后重新连接。'),
				E('div', {id: 'countdown', style: 'font-size:48px;font-weight:700;'}, String(seconds)),
				E('div', {style: 'font-size:13px;color:#888;margin-top:8px;margin-bottom:24px;'}, '秒后自动刷新'),
				E('button', {style: 'padding:10px 30px;font-size:16px;border:2px solid #4CAF50;background:transparent;color:#4CAF50;border-radius:8px;cursor:pointer;', click: function() { window.location.reload(); }}, '立即刷新')
			]);
			document.body.appendChild(overlay);

			var countdownEl = document.getElementById('countdown');
			var timer = setInterval(function() {
				seconds--;
				if (countdownEl) countdownEl.textContent = String(seconds);
				if (seconds <= 0) {
					clearInterval(timer);
					window.location.reload();
				}
			}, 1000);
		}

		function startUpgrade(isForce) {
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

		function runUpgrade() { startUpgrade(false); }
		function runForceUpgrade() { startUpgrade(true); }

		function runBackup() {
			updateOutput('正在创建配置备份...\n');
			fs.exec('/usr/bin/online-upgrade.sh', ['backup']).then(function(r) {
				updateOutput(r.stdout + (r.stderr ? '\n' + r.stderr : '') + '\n');
				// 刷新备份信息
				refreshBackupInfo();
			}).catch(function(e) {
				updateOutput('❌ 备份失败: ' + e.message + '\n');
			});
		}

		function refreshBackupInfo() {
			// 刷新备份文件信息显示
			fs.exec('/bin/sh', ['-c', "ls -t /root/pre-upgrade-backup-*.tar.gz 2>/dev/null | head -1 | while read f; do echo \"$f $(date -r \"$f\" '+%Y-%m-%d %H:%M:%S') $(du -h \"$f\" | cut -f1)\"; done"]).then(function(r) {
				var hint = document.getElementById('backup-hint');
				var dlBtn = document.getElementById('btn-download');
				if (!hint) return;
				var output = (r.stdout || '').trim();
				if (output) {
					var parts = output.split(' ');
					var name = parts[0].split('/').pop();
					var ts = parts[1] + ' ' + parts[2];
					var size = parts[3] || '';
					hint.innerHTML = '';
					hint.style.color = '#4CAF50';
					var link = E('a', {
						href: '/cgi-bin/luci/admin/system/online_upgrade/download',
						style: 'color:#4CAF50;text-decoration:none;',
						target: '_blank'
					}, '✅ 备份文件: ' + name + ' | ' + ts + ' | ' + size);
					hint.appendChild(link);
					if (dlBtn) dlBtn.style.display = 'inline-block';
				} else {
					fs.exec('/bin/sh', ['-c', 'date -r /etc/config/sysupgrade.tgz 2>/dev/null || echo ""']).then(function(r2) {
						var ts2 = (r2.stdout || '').trim();
						if (ts2) {
							hint.textContent = '⚠️ 配置文件备份时间 ' + ts2 + '（旧版备份）';
							hint.style.color = '#ff9800';
						} else {
							hint.textContent = '⚠️ 暂无备份文件';
							hint.style.color = '#999';
						}
					});
				}
			});
		}

		function openBackupRestore() { window.location.href = L.url('admin/system/flash'); }

		function updateOutput(t) {
			var el = document.getElementById('upgrade-result');
			if (el) { el.style.display = 'block'; el.textContent += t; }
		}

		function parseUrl() {
			var url = document.getElementById('cfg-url').value.trim();
			var m = url.match(/^https:\/\/github\.com\/([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)\/releases(?:\/tag\/([^\/\s?#]+))?\/?(?:[?#].*)?$/);
			if (!m) { ui.addNotification(null, E('p', '请填写 GitHub Releases 地址'), 'error'); return; }
			document.getElementById('cfg-repo').value = m[1];
			document.getElementById('cfg-tag').value = m[2] || 'auto';
			ui.addNotification(null, E('p', '已解析发布仓库和标签'), 'info');
		}

		function saveCfg() {
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

		function toggleAdv() {
			var body = document.getElementById('adv-body');
			var arrow = document.getElementById('adv-arrow');
			if (!body) return;
			var hidden = body.style.display === 'none';
			body.style.display = hidden ? 'block' : 'none';
			if (arrow) arrow.textContent = hidden ? '▼' : '▶';
		}

		// 读取当前版本和备份状态
		setTimeout(function() {
			fs.exec('/bin/cat', ['/etc/openwrt_release']).then(function(r) {
				var lines = (r.stdout || '').split('\n');
				for (var i = 0; i < lines.length; i++) {
					var m = lines[i].match(/DISTRIB_RELEASE='([^']+)'/);
					if (m) {
						var el = document.getElementById('cur-ver');
						if (el) el.textContent = m[1];
					}
					m = lines[i].match(/DISTRIB_REVISION='r?([^']+)'/);
					if (m) {
						var el = document.getElementById('cur-rev');
						if (el) el.textContent = 'r' + m[1];
					}
				}
			});
			refreshBackupInfo();
		}, 100);

		// ======== 构建页面 ========
		return E('div', {'class': 'cbi-map'}, [
			E('h2', {'class': 'cbi-page-title'}, '固件在线升级'),

			// 状态卡片
			E('div', {'class': 'cbi-section', style: 'margin-bottom:16px;padding:20px;'}, [
				E('div', {style: 'font-size:18px;font-weight:600;margin-bottom:12px;'}, [
					E('span', {style: 'display:inline-block;width:12px;height:12px;border-radius:50%;background:#4CAF50;margin-right:8px;'}),
					'固件状态'
				]),
				E('div', {style: 'font-size:14px;margin-bottom:12px;'}, [
					E('div', {style: 'padding:4px 0;'}, [
						E('span', {style: 'color:#666;display:inline-block;width:80px;'}, '当前版本'),
						E('span', {style: 'font-weight:600;'}, 'Photonicat-Wrt '),
						E('span', {id: 'cur-ver', style: 'font-weight:600;'}, '加载中...'),
						E('span', {id: 'cur-rev', style: 'color:#888;margin-left:4px;font-size:12px;'}, '')
					]),
					E('div', {style: 'padding:4px 0;'}, [
						E('span', {style: 'color:#666;display:inline-block;width:80px;'}, '最新版本'),
						E('span', {id: 'latest-ver'}, '-'),
						E('span', {id: 'latest-size', style: 'color:#888;margin-left:8px;font-size:12px;'}, '')
					]),
					E('div', {style: 'padding:4px 0;', id: 'new-ver-row'}, [
						E('span', {style: 'color:#666;display:inline-block;width:80px;'}, '固件版本'),
						E('span', {id: 'new-ver', style: 'font-weight:600;'}, '-'),
						E('span', {id: 'check-reason', style: 'color:#888;margin-left:8px;font-size:12px;'}, '')
					])
				]),
				E('div', {style: 'display:flex;gap:8px;align-items:center;flex-wrap:wrap;'}, [
					E('button', {id: 'btn-check', class: 'btn cbi-button-action', click: runCheck}, '检查更新'),
					E('button', {id: 'btn-upgrade', class: 'btn cbi-button-action important', style: 'display:none;background:#4CAF50;border-color:#4CAF50;', click: runUpgrade}, '立即升级'),
					E('button', {id: 'btn-force', class: 'btn cbi-button', style: 'display:none;padding:7px 14px;border-radius:4px;cursor:pointer;font-size:12px;', click: runForceUpgrade}, '强制更新'),
					E('span', {id: 'check-result', style: 'color:#888;font-size:12px;margin-left:4px;'}, '')
					])
					]),

					// 备份 & 恢复卡片
					E('div', {'class': 'cbi-section', style: 'margin-bottom:16px;padding:20px;'}, [
					E('div', {style: 'font-size:16px;font-weight:600;margin-bottom:14px;padding-bottom:10px;border-bottom:1px solid #eee;display:flex;align-items:center;gap:8px;'}, [
					E('span', {style: 'font-size:18px;'}, '💾'),
					'备份 & 恢复'
					]),
					E('div', {style: 'display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-bottom:10px;'}, [
					E('button', {id: 'btn-backup', class: 'btn cbi-button', style: 'padding:7px 14px;border-radius:4px;cursor:pointer;font-size:12px;border:1px solid #2196F3;color:#2196F3;background:transparent;', click: runBackup, title: '创建配置备份到 /root/'}, '📦 创建备份'),
					E('button', {id: 'btn-download', class: 'btn cbi-button', style: 'display:none;padding:7px 14px;border-radius:4px;cursor:pointer;font-size:12px;border:1px solid #4CAF50;color:#4CAF50;background:transparent;', click: function() { var p = window.location.pathname.match(/^\/.*\/admin/) || ['/cgi-bin/luci/admin']; var b = p[0].replace('/admin', ''); window.open(b + '/admin/system/online_upgrade/download', '_blank'); }}, '⬇ 下载备份'),
					E('button', {class: 'btn cbi-button', click: openBackupRestore}, '备份与恢复'),
					]),
					E('div', {id: 'backup-hint', style: 'color:#999;font-size:12px;padding:4px 0;'}, '状态检查中...')
					]),

			// 仓库配置
			E('div', {'class': 'cbi-section', style: 'margin-bottom:16px;padding:20px;'}, [
				E('div', {style: 'font-size:16px;font-weight:600;margin-bottom:14px;padding-bottom:10px;border-bottom:1px solid #eee;'}, '仓库配置'),
				E('div', {style: 'display:flex;flex-direction:column;gap:10px;'}, [
					E('div', {style: 'display:flex;align-items:center;gap:8px;flex-wrap:wrap;'}, [
						E('label', {style: 'min-width:100px;font-size:13px;color:#555;font-weight:500;'}, 'Release 地址'),
						E('div', {style: 'flex:1;min-width:200px;display:flex;align-items:center;gap:6px;'}, [
							E('input', {id: 'cfg-url', type: 'text', style: 'flex:1;padding:7px 10px;border:1px solid #ddd;border-radius:4px;font-size:13px;background:var(--input-bg,transparent);', value: 'https://github.com/' + cfgRepo + (cfgTag === 'auto' ? '/releases' : '/releases/tag/' + cfgTag)}),
							E('button', {class: 'btn cbi-button', style: 'padding:7px 14px;border-radius:4px;cursor:pointer;', click: parseUrl}, '解析'),
							E('span', {style: 'font-size:12px;color:#888;'}, '自动解析仓库和标签')
						])
					]),
					E('div', {style: 'margin-top:4px;margin-bottom:4px;'}, [
						E('div', {style: 'cursor:pointer;font-size:13px;color:#5e72e4;user-select:none;display:inline-flex;align-items:center;gap:4px;padding:4px 0;', click: toggleAdv}, [
							E('span', {id: 'adv-arrow'}, '▶'),
							' 高级配置'
						])
					]),
					E('div', {id: 'adv-body', style: 'display:none;'}, [
						E('div', {style: 'display:flex;align-items:center;gap:8px;flex-wrap:wrap;'}, [
							E('label', {style: 'min-width:100px;font-size:13px;color:#555;font-weight:500;'}, 'GitHub 仓库'),
							E('input', {id: 'cfg-repo', type: 'text', style: 'flex:1;min-width:200px;padding:7px 10px;border:1px solid #ddd;border-radius:4px;font-size:13px;background:var(--input-bg,transparent);color:#888;', value: cfgRepo})
						]),
						E('div', {style: 'display:flex;align-items:center;gap:8px;flex-wrap:wrap;'}, [
							E('label', {style: 'min-width:100px;font-size:13px;color:#555;font-weight:500;'}, 'Release 标签'),
							E('input', {id: 'cfg-tag', type: 'text', style: 'flex:1;min-width:200px;padding:7px 10px;border:1px solid #ddd;border-radius:4px;font-size:13px;background:var(--input-bg,transparent);color:#888;', value: cfgTag})
						]),
						E('div', {style: 'display:flex;align-items:center;gap:8px;flex-wrap:wrap;'}, [
							E('label', {style: 'min-width:100px;font-size:13px;color:#555;font-weight:500;'}, '固件匹配'),
							E('div', {style: 'flex:1;min-width:200px;'}, [
								E('input', {id: 'cfg-pattern', type: 'text', style: 'width:100%;padding:7px 10px;border:1px solid #ddd;border-radius:4px;font-size:13px;background:var(--input-bg,transparent);color:#888;', value: cfgPattern, readonly: 'readonly'}),
								E('div', {style: 'font-size:11px;color:#888;margin-top:2px;'}, '只匹配光影猫一代 squashfs 升级镜像')
							])
						]),
						E('div', {style: 'display:flex;align-items:center;gap:8px;flex-wrap:wrap;'}, [
							E('label', {style: 'min-width:100px;font-size:13px;color:#555;font-weight:500;'}, '下载代理(可选)'),
							E('input', {id: 'cfg-proxy', type: 'text', style: 'flex:1;min-width:200px;padding:7px 10px;border:1px solid #ddd;border-radius:4px;font-size:13px;background:var(--input-bg,transparent);', value: cfgProxy})
						])
					])
				]),
				E('div', {style: 'margin-top:14px;text-align:right;'}, [
					E('button', {class: 'btn cbi-button-save', style: 'padding:7px 20px;border-radius:4px;cursor:pointer;', click: saveCfg}, '保存配置')
				])
			]),

			// 进度条
			E('div', {id: 'progress-area', style: 'display:none;margin-bottom:16px;'}, [
				E('div', {'class': 'cbi-section', style: 'padding:20px;'}, [
					E('div', {style: 'font-size:14px;font-weight:600;margin-bottom:10px;'}, '升级进度'),
					E('div', {style: 'height:24px;background:#e9ecef;border-radius:12px;overflow:hidden;position:relative;'}, [
						E('div', {id: 'progress-bar', style: 'width:0%;height:100%;background:linear-gradient(90deg,#4CAF50,#8BC34A);border-radius:12px;transition:width 0.5s ease;'}),
						E('div', {id: 'progress-label', style: 'position:absolute;top:0;left:0;right:0;height:24px;line-height:24px;text-align:center;font-size:12px;font-weight:600;color:#333;'}, '0%')
					]),
					E('div', {id: 'progress-text', style: 'margin-top:8px;font-size:13px;color:#666;'}, '')
				])
			]),

			// 结果
			E('pre', {id: 'upgrade-result', style: 'background:var(--cbi-section-bg,#1e1e1e);color:#d4d4d4;padding:20px;border-radius:6px;overflow:auto;max-height:400px;font-size:13px;white-space:pre-wrap;display:none;border:1px solid var(--cbi-section-border,#ddd);box-shadow:0 1px 4px rgba(0,0,0,0.06);box-sizing:border-box;width:100%;'}, '')
		]);
	}
});
