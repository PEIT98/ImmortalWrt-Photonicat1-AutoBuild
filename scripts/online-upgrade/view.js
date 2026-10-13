'use strict';
'require view';
'require fs';
'require ui';

return view.extend({
	handleSave: null,
	handleSaveApply: null,
	handleReset: null,

	render: function() {
		var root = E('div', {class: 'cbi-map'});
		var result = E('pre', {style: 'white-space:pre-wrap;overflow-wrap:anywhere;padding:12px;border-radius:7px;background:rgba(127,127,127,.08);min-height:85px'}, '正在读取在线升级配置...');
		var progress = E('p', {style: 'font-weight:600'}, '升级状态：尚未开始');
		var keep = E('input', {type:'radio',name:'photonicat-keep',checked:true});
		var reset = E('input', {type:'radio',name:'photonicat-keep'});
		var repo = E('input', {class:'cbi-input-text',type:'text',style:'min-width:260px;width:100%;max-width:450px',value:'PEIT98/ImmortalWrt-Photonicat1-AutoBuild'});
		var tag = E('input', {class:'cbi-input-text',type:'text',value:'latest'});
		var proxy = E('input', {class:'cbi-input-text',type:'text',style:'min-width:260px;width:100%;max-width:450px',placeholder:'留空为 GitHub 直连；可填可信 HTTPS 加速前缀'});
		var buttons = [], checked = false, busy = false, poll = null, upgrading = false, selectedRelease = null, selectedHash = null;

		function setBusy(yes) {
			busy = yes;
			for (var i = 0; i < buttons.length; i++)
				buttons[i].disabled = yes;
		}
		function output(message) { result.textContent = message; }
		function getKeep() { return reset.checked ? 'reset' : 'keep'; }
		function api(args) {
			return fs.exec('/usr/bin/online-upgrade.sh', args).then(function(r) {
				var text = (r.stdout || '') + (r.stderr ? '\n' + r.stderr : '');
				if (r.code !== 0 && r.code != null) throw new Error(text || '命令退出码 ' + r.code);
				return text;
			});
		}
		function readSettings() {
			api(['settings']).then(function(text) {
				text.split('\n').forEach(function(line) {
					var index = line.indexOf('=');
					if (index < 0) return;
					var key = line.slice(0,index), val = line.slice(index+1).trim();
					if (key === 'repo' && val) repo.value = val;
					if (key === 'tag' && val) tag.value = val;
					if (key === 'proxy') proxy.value = val;
				});
			}).catch(function(e) { output('读取配置失败：' + e.message); });
		}
		function saveSettings() {
			setBusy(true);
			api(['configure', repo.value.trim(), tag.value.trim() || 'latest', proxy.value.trim()]).then(function(text) {
				checked = false;
				selectedRelease = null; selectedHash = null;
				output(text + '\n请重新检查最新固件。');
			}).catch(function(e) { output('保存失败：' + e.message); })
			  .finally(function() { setBusy(false); });
		}
		function checkUpdate() {
			setBusy(true);
			checked = false;
			selectedRelease = null; selectedHash = null;
			output('正在从 GitHub Releases 检查设备、当前根文件系统及 SHA256 清单...');
			api(['check']).then(function(text) {
				var tagMatch = text.match(/^Release：([A-Za-z0-9._-]+)$/m);
				var hashMatch = text.match(/^固件 SHA256：([0-9a-fA-F]{64})$/m);
				if (!tagMatch || !hashMatch) throw new Error('固件身份信息不完整');
				selectedRelease = tagMatch[1]; selectedHash = hashMatch[1];
				checked = true;
				output(text);
			}).catch(function(e) { output('检查失败：' + e.message); })
			  .finally(function() { setBusy(false); });
		}
		function updateStatus() {
			api(['status']).then(function(text) {
				var clean = text.trim();
				var split = clean.indexOf('|');
				var stage = split >= 0 ? clean.slice(0, split) : 'unknown';
				var msg = split >= 0 ? clean.slice(split+1) : clean;
				progress.textContent = '升级状态：' + msg;
				if (stage === 'failed') {
					if (poll) clearInterval(poll);
					poll = null; upgrading = false;
					setBusy(false);
					output('升级失败：' + msg + '\n请检查设备上 /tmp/photonicat-upgrade/upgrade.log');
				} else if (stage === 'flashing' || stage === 'reboot') {
					progress.textContent = '正在刷写/重启：' + msg + '。请勿断电，等待路由器重新上线。';
					// Continue observing: sysupgrade can still fail after entering
					// the flashing phase; do not report success prematurely.
				}
			}).catch(function() {
				if (upgrading) progress.textContent = '已失去连接，可能正在升级重启。不要断电，请等待设备重新上线。';
			});
		}
		function startUpgrade(force) {
			if (!checked || !selectedRelease || !selectedHash) { ui.addNotification(null,E('p',{},'请先检查最新固件并确认设备匹配')); return; }
			var mode = getKeep();
			var summary = mode === 'keep'
				? '保留配置：刷写后尝试恢复已有网络、Wi-Fi、QModem 等配置。'
				: '不保留配置：系统将以新固件默认设置启动，网络、Wi-Fi、QModem 等需要重新设置。';
			var notice = [
				'确定要执行光影猫一代在线升级吗？',
				summary,
				force ? '当前选择：强制重装（仍必须通过全部镜像安全校验）。' : '当前选择：升级到最新构建。',
				'插件将下载光影猫同文件系统镜像、验证 SHA256、运行 sysupgrade -T、备份配置后刷写。',
				'升级存在设备无法启动的风险。务必提前备份至电脑，并准备好救砖手段。',
				'刷写期间严禁断电或拔掉存储介质。'
			].join('\n\n');
			if (!confirm(notice)) return;
			setBusy(true);
			upgrading = true;
			progress.textContent = '升级状态：正在启动后台任务...';
			api(['start', mode, force ? 'force' : 'normal', selectedRelease, selectedHash]).then(function(t) {
				output(t);
				if (poll) clearInterval(poll);
				poll = setInterval(updateStatus, 3000);
				updateStatus();
			}).catch(function(e) {
				upgrading = false; setBusy(false); output('启动失败：' + e.message);
			});
		}
		function makeBackup() {
			setBusy(true);
			output('正在使用 sysupgrade 创建配置备份...');
			api(['backup']).then(output)
				.catch(function(e) { output('备份失败：' + e.message); })
				.finally(function() { setBusy(false); });
		}
		function btn(text, action, variant) {
			var b = E('button',{type:'button',class:'btn ' + (variant || 'cbi-button'),click:action},text);
			buttons.push(b); return b;
		}
		function formRow(title, field) {
			return E('div',{style:'display:flex;align-items:center;gap:12px;flex-wrap:wrap;margin:8px 0'},[
				E('label',{style:'width:115px;max-width:100%'},title),field]);
		}
		root.appendChild(E('h2',{class:'cbi-map-title'},'光影猫一代 · GitHub 在线升级'));
		root.appendChild(E('div',{class:'cbi-section',style:'padding:16px;margin-bottom:14px'},[
			E('h3',{},'固件来源'),
			formRow('GitHub 仓库',repo),
			formRow('Release 标签',tag),
			formRow('HTTPS 下载代理',proxy),
			E('p',{style:'font-size:12px;opacity:.8'},'标签 latest 表示最新正式 Release；自定义仓库也必须发布光影猫一代匹配镜像及 SHA256SUMS.txt。代理仅用于下载镜像；校验值必须从 GitHub 直连获取。'),
			btn('保存来源设置',saveSettings),
			btn('检查最新固件',checkUpdate,'cbi-button-action'),
			E('a',{class:'btn cbi-button',href:'https://github.com/PEIT98/ImmortalWrt-Photonicat1-AutoBuild/releases',target:'_blank',rel:'noopener noreferrer'},'查看 Releases')
		]));
		root.appendChild(E('div',{class:'cbi-section',style:'padding:16px;margin-bottom:14px'},[
			E('h3',{},'升级时处理配置'),
			E('div',{style:'display:flex;gap:18px;flex-wrap:wrap'},[
				E('label',{},[keep,' 保留配置（默认）']),
				E('label',{},[reset,' 不保留配置（恢复新固件默认设置）'])
			]),
			E('p',{style:'color:#b07000'},'不保留配置会失去当前网络、Wi-Fi、QModem 等设置；外置 Docker 数据盘不会因这一选项主动格式化。请事先下载独立备份。'),
			E('div',{style:'display:flex;gap:10px;flex-wrap:wrap;margin:14px 0'},[
				btn('创建升级前备份',makeBackup),
				E('a',{class:'btn cbi-button',href:L.url('admin/system/flash')},'系统备份下载 / 手动升级')
			]),
			E('div',{style:'display:flex;gap:10px;flex-wrap:wrap;margin:14px 0'},[
				btn('立即升级',function(){startUpgrade(false)},'cbi-button-action important'),
				btn('强制重装当前版本',function(){startUpgrade(true)})
			]),
			E('p',{style:'color:#b07000'},'强制重装不能绕过设备验证、SHA256 或 sysupgrade -T；首次使用前建议准备救砖方案。'),
			progress
		]));
		root.appendChild(E('div',{class:'cbi-section',style:'padding:16px'},[
			E('h3',{},'固件检测与升级日志'),result]));
		readSettings();
		// Automatic update check on page open; does not initiate a firmware flash.
		checkUpdate();
		return root;
	}
});
