'use strict';
'require view';
'require fs';

return view.extend({
	handleSave: null,
	handleSaveApply: null,
	handleReset: null,

	render: function() {
		var result = E('pre', {
			style: 'white-space:pre-wrap;overflow-wrap:anywhere;line-height:1.7;background:rgba(127,127,127,.08);padding:14px;border-radius:6px;min-height:90px'
		}, '点击“检查 GitHub 更新”获取最新的光影猫一代固件信息。');
		var button = E('button', {
			class: 'btn cbi-button-action',
			click: function() {
				button.disabled = true;
				button.textContent = '检查中...';
				result.textContent = '正在访问 GitHub Releases...';
				fs.exec('/usr/bin/online-upgrade.sh', ['check']).then(function(r) {
					result.textContent = (r.stdout || '') + (r.stderr ? '\n' + r.stderr : '');
				}).catch(function(err) {
					result.textContent = '检查失败：' + (err.message || String(err));
				}).finally(function() {
					button.disabled = false;
					button.textContent = '检查 GitHub 更新';
				});
			}
		}, '检查 GitHub 更新');

		// The current updater is check-only. This is a guided choice for the
		// native LuCI manual flashing screen, NOT an automatic sysupgrade flag.
		var retainConfig = true;
		var modeHint = E('p', {
			style: 'margin:10px 0;font-weight:500'
		}, '已选择：保留配置。下一页请保持“保留配置”复选框勾选。');
		var modeWarning = E('p', {
			style: 'color:#b07000;margin:8px 0;'
		}, '此选择仅用于提示操作；不会自动修改系统原生升级页的选项，也不会开始刷机。');
		var modeKeep = E('input', {
			type: 'radio', name: 'photonicat-config-mode', value: 'keep', checked: true,
			change: function() {
				retainConfig = true;
				updateMode();
			}
		});
		var modeReset = E('input', {
			type: 'radio', name: 'photonicat-config-mode', value: 'reset',
			change: function() {
				retainConfig = false;
				updateMode();
			}
		});
		function updateMode() {
			modeHint.textContent = retainConfig
				? '已选择：保留配置。下一页请保持“保留配置”复选框勾选。'
				: '已选择：不保留配置。下一页必须取消勾选“保留配置”（Keep settings）；升级后需重新设置网络、Wi-Fi、QModem 等。';
		}
		function openNativeUpgrade() {
			var message = retainConfig
				? [
					'即将打开系统原生“备份 / 升级”页面。',
					'你选择：保留配置。请在原生升级页面确认“保留配置”（Keep settings）已勾选。',
					'核对设备型号、镜像格式和 SHA256 后再进行手动升级。插件本身不会刷机。'
				].join('\n\n')
				: [
					'警告：你选择了“不保留配置”！',
					'手动升级后原有网络、Wi-Fi、QModem 等系统配置可能需要重新设置。',
					'请在原生升级页面亲自取消勾选“保留配置”（Keep settings），并再次确认。',
					'不保留配置并不会自动擦除外置 Docker 存储或数据盘。'
				].join('\n\n');
			if (confirm(message))
				window.location.href = L.url('admin/system/flash');
		}
		var manualUpgradeButton = E('button', {
			class: 'btn cbi-button',
			click: openNativeUpgrade
		}, '前往手动升级（再次确认配置选项）');

		return E('div', { class: 'cbi-map' }, [
			E('h2', { class: 'cbi-map-title' }, '光影猫一代 · 在线固件检查'),
			E('div', { class: 'cbi-section' }, [
				E('p', {}, '基于 gooyjq/luci-app-online-upgrade 改造，专用于 Ariaboard Photonicat1（RK3568）。'),
				E('p', {}, '安全模式：此版本只检查你自己的 GitHub Releases，不在路由器上下载或刷写镜像，也不自动安装任何 APK。'),
				E('p', {}, '固件有 ext4 和 squashfs 两种格式。请选择与你当前安装方式匹配的镜像，并在手动刷写前核对 SHA256 和设备信息。'),

				E('div', { class: 'cbi-section', style: 'padding:12px 14px;border:1px solid rgba(127,127,127,.24);margin:14px 0' }, [
					E('h3', {}, '手动升级时如何处理配置'),
					E('div', { style: 'display:flex;gap:20px;flex-wrap:wrap;margin:10px 0' }, [
						E('label', { style: 'display:inline-flex;align-items:center;gap:6px;cursor:pointer' },
							[modeKeep, E('span', {}, '保留配置（默认）')]),
						E('label', { style: 'display:inline-flex;align-items:center;gap:6px;cursor:pointer' },
							[modeReset, E('span', {}, '不保留配置（重新配置系统）')])
					]),
					modeHint,
					modeWarning,
					E('p', { style: 'color:#b07000' },
						'不保留配置不代表清空数据盘、外置存储或 Docker 容器数据；操作前请独立备份重要数据。')
				]),
				E('div', { style: 'display:flex;gap:12px;align-items:center;flex-wrap:wrap;margin-bottom:12px' }, [
					button,
					E('a', {
						class: 'btn cbi-button',
						href: 'https://github.com/PEIT98/ImmortalWrt-Photonicat1-AutoBuild/releases/latest',
						target: '_blank',
						rel: 'noopener noreferrer'
					}, '查看最新 Release'),
					manualUpgradeButton
				]),
				result,
				E('p', { style: 'color:#b07000' }, '注意：GitHub 编译成功不等于设备可安全直接刷写。请先备份配置和救砖固件。')
			])
		]);
	}
});
