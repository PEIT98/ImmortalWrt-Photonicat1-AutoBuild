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

		return E('div', { class: 'cbi-map' }, [
			E('h2', { class: 'cbi-map-title' }, '光影猫一代 · 在线固件检查'),
			E('div', { class: 'cbi-section' }, [
				E('p', {}, '基于 gooyjq/luci-app-online-upgrade 改造，专用于 Ariaboard Photonicat1（RK3568）。'),
				E('p', {}, '安全模式：此版本只检查你自己的 GitHub Releases，不在路由器上下载或刷写镜像，也不自动安装任何 APK。'),
				E('p', {}, '固件有 ext4 和 squashfs 两种格式。请选择与你当前安装方式匹配的镜像，并在手动刷写前核对 SHA256 和设备信息。'),
				E('div', { style: 'display:flex;gap:12px;align-items:center;flex-wrap:wrap;margin-bottom:12px' }, [
					button,
					E('a', {
						class: 'btn cbi-button',
						href: 'https://github.com/PEIT98/ImmortalWrt-Photonicat1-AutoBuild/releases/latest',
						target: '_blank',
						rel: 'noopener noreferrer'
					}, '查看最新 Release'),
					E('a', {
						class: 'btn cbi-button',
						href: L.url('admin/system/flash')
					}, '系统备份 / 手动升级')
				]),
				result,
				E('p', { style: 'color:#b07000' }, '注意：GitHub 编译成功不等于设备可安全直接刷写。请先备份配置和救砖固件。')
			])
		]);
	}
});
