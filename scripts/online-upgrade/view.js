'use strict';
'require view';
'require fs';
'require ui';

return view.extend({
	handleSave: null,
	handleSaveApply: null,
	handleReset: null,

	render: function() {
		var root = E('div', {class:'cbi-map'});
		var result = E('pre', {style:'white-space:pre-wrap;overflow-wrap:anywhere;padding:12px;border-radius:6px;background:rgba(127,127,127,.08);min-height:80px'}, '正在初始化...');
		var progress = E('p', {style:'font-weight:600'}, '升级状态：尚未开始');
		var tagHint = E('p', {style:'font-size:12px;opacity:.85'}, '最近 5 个 Release 标签正在读取；也可以在下方手工输入标签。');
		var keep = E('input', {type:'radio',name:'photonicat-config-mode',checked:true});
		var reset = E('input', {type:'radio',name:'photonicat-config-mode'});
		var repo = E('input', {type:'text',class:'cbi-input-text',style:'width:100%;max-width:450px',value:'PEIT98/ImmortalWrt-Photonicat1-AutoBuild'});
		var tag = E('input', {type:'text',class:'cbi-input-text',value:'latest',placeholder:'latest 或自定义 Release 标签'});
		var versions = E('select', {class:'cbi-input-select',style:'min-width:260px',change:function() {
			if (versions.value !== '__manual__') tag.value = versions.value;
		}}, [E('option',{value:'latest'},'latest（最新正式 Release）')]);
		var accel = E('select', {class:'cbi-input-select',change:function() {
			proxy.style.display = accel.value === 'custom' ? '' : 'none';
		}}, [
			E('option',{value:''},'GitHub 直连（默认）'),
			E('option',{value:'https://ghproxy.net/'},'GHProxy.net（国内加速）'),
			E('option',{value:'https://ghfast.top/'},'GHFast（国内加速）'),
			E('option',{value:'https://gh-proxy.org/'},'GH-Proxy（国内加速）'),
			E('option',{value:'custom'},'自定义 HTTPS 代理')
		]);
		var proxy = E('input', {type:'text',class:'cbi-input-text',style:'width:100%;max-width:450px;display:none',placeholder:'https://你的加速域名/'});
		var url = E('input', {type:'text',class:'cbi-input-text',style:'width:100%;max-width:540px',placeholder:'可选：光影猫专用 HTTPS .img.gz 完整下载地址'});
		var sha = E('input', {type:'text',class:'cbi-input-text',style:'width:100%;max-width:540px',placeholder:'自定义固件必填：64 位 SHA256'});
		var buttons = [], checked = false, running = false, checkPoll = null, tagsPoll = null, upgradePoll = null;
		var selectedTag = null, selectedSha = null;

		function setBusy(v) {
			buttons.forEach(function(x) { x.disabled = !!v; });
		}
		function api(args) {
			return fs.exec('/usr/bin/online-upgrade.sh', args).then(function(r) {
				var text = (r.stdout || '') + (r.stderr ? '\n' + r.stderr : '');
				if (r.code != null && r.code !== 0) throw new Error(text || ('exit ' + r.code));
				return text;
			});
		}
		function clearCheck() {
			checked = false;
			selectedTag = null;
			selectedSha = null;
		}
		function splitStatus(v) {
			var line = (v || '').trim(), pos = line.indexOf('|');
			return {state:pos < 0 ? 'unknown' : line.slice(0,pos),
			        message:pos < 0 ? line : line.slice(pos+1)};
		}
		function selectedProxy() {
			return accel.value === 'custom' ? proxy.value.trim() : accel.value;
		}
		function readSettings() {
			return api(['settings']).then(function(text) {
				var data = {};
				text.split('\n').forEach(function(line) {
					var p = line.indexOf('=');
					if (p >= 0) data[line.slice(0,p)] = line.slice(p+1);
				});
				if (data.repo) repo.value = data.repo;
				if (data.tag) tag.value = data.tag;
				if (data.custom_url) url.value = data.custom_url;
				if (data.custom_sha256) sha.value = data.custom_sha256;
				var preset = ['', 'https://ghproxy.net/', 'https://ghfast.top/', 'https://gh-proxy.org/'];
				if (preset.indexOf(data.proxy || '') >= 0) {
					accel.value = data.proxy || '';
				} else {
					accel.value = 'custom';
					proxy.value = data.proxy;
					proxy.style.display = '';
				}
			});
		}
		function saveSettings() {
			setBusy(true);
			api(['configure',repo.value.trim(),tag.value.trim() || 'latest',selectedProxy(),url.value.trim(),sha.value.trim()]).then(function(t) {
				clearCheck(); result.textContent = t + '\n请重新检查固件。';
			}).catch(function(e) {
				result.textContent = '配置保存失败：' + e.message;
			}).finally(function(){setBusy(false);});
		}
		function loadTags() {
			if (tagsPoll) clearInterval(tagsPoll);
			tagHint.textContent = '正在后台读取最近 5 个 Release 标签...';
			api(['tags-start',repo.value.trim()]).then(function(){
				var tries = 0;
				tagsPoll = setInterval(function(){
					tries++;
					api(['tags-status']).then(function(t){
						var v = splitStatus(t);
						if (v.state === 'working' && tries < 25) return;
						clearInterval(tagsPoll); tagsPoll = null;
						if (v.state !== 'ready') {
							tagHint.textContent = v.message || '获取失败，请手工输入 Release 标签';
							return;
						}
						api(['tags-result']).then(function(t){
							versions.textContent = '';
							versions.appendChild(E('option',{value:'latest'},'latest（最新正式 Release）'));
							var count = 0;
							t.split('\n').forEach(function(z){
								z = z.trim();
								if (/^[A-Za-z0-9._-]+$/.test(z) && count++ < 5)
									versions.appendChild(E('option',{value:z},z));
							});
							versions.appendChild(E('option',{value:'__manual__'},'自定义标签（手工输入）'));
							versions.value = tag.value;
							if (versions.value !== tag.value) versions.value = '__manual__';
							tagHint.textContent = '已读取最近 ' + Math.min(count,5) + ' 个发布版本；一般 Git 提交没有固件镜像，不能直接升级。';
						}).catch(function(e){tagHint.textContent = '标签结果读取失败：' + e.message;});
					}).catch(function(e){
						clearInterval(tagsPoll);tagsPoll=null;
						tagHint.textContent='标签检查失败：'+e.message;
					});
					if (tries >= 25) { clearInterval(tagsPoll);tagsPoll=null;tagHint.textContent='标签查询超时；可以直接输入标签'; }
				}, 2000);
			}).catch(function(e){tagHint.textContent = '启动标签查询失败：'+e.message;});
		}
		function checkUpdate() {
			if (checkPoll) clearInterval(checkPoll);
			clearCheck();
			setBusy(true);
			result.textContent = '已启动后台检查，正在读取 GitHub Release 与 SHA256（页面不会长时间等待同一个请求）...';
			api(['check-start']).then(function(){
				var tries = 0;
				checkPoll = setInterval(function(){
					tries++;
					api(['check-status']).then(function(t){
						var v = splitStatus(t);
						if (v.state === 'working' && tries < 65) return;
						if (checkPoll) clearInterval(checkPoll);
						checkPoll = null;
						if (v.state !== 'ready') {
							result.textContent = '检查失败：' + (v.message || '后台检查超时。请查看 /tmp/photonicat-upgrade/check.err');
							setBusy(false);
							return;
						}
						api(['check-result']).then(function(info){
							var tm = info.match(/^Release：([A-Za-z0-9._-]+)$/m);
							var hm = info.match(/^固件 SHA256：([0-9a-fA-F]{64})$/m);
							if (!tm || !hm) throw new Error('未返回有效的固件版本及 SHA256');
							selectedTag=tm[1]; selectedSha=hm[1];checked=true;
							result.textContent=info;
						}).catch(function(e){result.textContent='结果解析失败：'+e.message;})
							.finally(function(){setBusy(false);});
					}).catch(function(e){
						if(checkPoll)clearInterval(checkPoll);checkPoll=null;
						result.textContent='检查状态获取失败：'+e.message;
						setBusy(false);
					});
					if (tries >= 65) { if(checkPoll)clearInterval(checkPoll);checkPoll=null;setBusy(false); }
				}, 2000);
			}).catch(function(e){result.textContent='无法启动检查：'+e.message;setBusy(false);});
		}
		function updateStatus() {
			api(['status']).then(function(t){
				var v=splitStatus(t);
				progress.textContent='升级状态：'+v.message;
				if(v.state==='failed') {
					if(upgradePoll)clearInterval(upgradePoll);
					upgradePoll=null;running=false;setBusy(false);
					result.textContent='升级失败：'+v.message+'\n详细日志位于 /tmp/photonicat-upgrade/upgrade.log';
				} else if(v.state==='flashing' || v.state==='reboot') {
					progress.textContent='正在刷写或重启：'+v.message+'。请勿断电。';
				}
			}).catch(function(){
				if(running) progress.textContent='连接中断，设备可能正在升级或重启。请勿断电。';
			});
		}
		function startUpgrade(force) {
			if(!checked || !selectedTag || !selectedSha) {
				ui.addNotification(null,E('p',{},'请先完成固件检查与 SHA256 校验信息读取'));
				return;
			}
			var mode=reset.checked?'reset':'keep';
			var warning=[
				'即将升级光影猫一代固件',
				mode==='keep'?'保留原网络、Wi-Fi、QModem 等配置（尽可能恢复兼容项）':'不保留配置，升级后需要重新配置网络、Wi-Fi、QModem 等',
				force?'强制重新刷写已发布版本，但绝不绕过校验':'安装已选择的 Release',
				'升级时需下载固件、校验 SHA256、运行 sysupgrade -T 和对比启动磁盘分区。',
				'请先将原有配置备份到电脑，并准备好救砖方法。升级过程中不能断电！'
			].join('\n\n');
			if(!confirm(warning))return;
			setBusy(true);running=true;
			progress.textContent='正在启动后台固件下载任务...';
			api(['start',mode,force?'force':'normal',selectedTag,selectedSha]).then(function(text){
				result.textContent=text;
				if(upgradePoll)clearInterval(upgradePoll);
				upgradePoll=setInterval(updateStatus,3000);
				updateStatus();
			}).catch(function(e){running=false;setBusy(false);result.textContent='启动升级失败：'+e.message;});
		}
		function makeBackup() {
			setBusy(true);result.textContent='正在创建配置备份...';
			api(['backup']).then(function(t){result.textContent=t;})
				.catch(function(e){result.textContent='配置备份失败：'+e.message;})
				.finally(function(){setBusy(false);});
		}
		function btn(text,cb,style) {
			var b=E('button',{type:'button',class:'btn '+(style||'cbi-button'),click:cb},text);
			buttons.push(b);return b;
		}
		function form(title,field) {
			return E('div',{style:'display:flex;gap:12px;flex-wrap:wrap;align-items:center;margin:9px 0'},[
				E('label',{style:'width:125px'},title),field]);
		}
		root.appendChild(E('h2',{class:'cbi-map-title'},'光影猫一代 · GitHub 在线升级'));
		root.appendChild(E('div',{class:'cbi-section',style:'padding:16px;margin-bottom:12px'},[
			E('h3',{},'固件来源'),
			form('GitHub 仓库',repo),
			form('最近 5 个标签',versions),
			tagHint,
			form('Release 标签',tag),
			form('下载加速源',accel),
			form('自定义加速地址',proxy),
			E('p',{style:'font-size:12px;opacity:.82'},'内置加速节点为第三方服务，可能不可用或缓存旧文件。默认 GitHub 直连；不论选择哪种代理，均强制 SHA256 校验。'),
			E('h4',{},'自定义下载（可选）'),
			form('固件 HTTPS 链接',url),
			form('固件 SHA256',sha),
			E('p',{style:'font-size:12px;opacity:.82'},'填写自定义固件直链时必须提供对应 SHA256；只接受 Photonicat1 当前 ext4/squashfs 镜像。自定义镜像不需要 GitHub API。'),
			E('div',{style:'display:flex;gap:8px;flex-wrap:wrap'},[
				btn('保存来源设置',saveSettings),
				btn('获取最近 5 个标签',loadTags),
				btn('检查最新固件',checkUpdate,'cbi-button-action'),
				E('a',{class:'btn cbi-button',href:'https://github.com/PEIT98/ImmortalWrt-Photonicat1-AutoBuild/releases',target:'_blank',rel:'noopener noreferrer'},'查看 Releases')
			])
		]));
		root.appendChild(E('div',{class:'cbi-section',style:'padding:16px;margin-bottom:12px'},[
			E('h3',{},'升级时处理配置'),
			E('div',{style:'display:flex;gap:18px;flex-wrap:wrap'},[
				E('label',{},[keep,' 保留配置（默认）']),
				E('label',{},[reset,' 不保留配置（恢复默认设置）'])
			]),
			E('p',{style:'color:#b07000'},'不保留配置会清除网络、Wi-Fi、QModem 等系统配置的恢复；不会因为此选项主动格式化外置 Docker 数据盘。'),
			E('div',{style:'display:flex;gap:8px;flex-wrap:wrap;margin:12px 0'},[
				btn('创建升级前备份',makeBackup),
				E('a',{class:'btn cbi-button',href:L.url('admin/system/flash')},'系统备份下载 / 手动升级')
			]),
			E('div',{style:'display:flex;gap:8px;flex-wrap:wrap;margin:12px 0'},[
				btn('立即升级',function(){startUpgrade(false)},'cbi-button-action important'),
				btn('强制重装当前版本',function(){startUpgrade(true)})
			]),
			E('p',{style:'color:#b07000'},'所有升级操作必须通过型号、SHA256、sysupgrade -T 及分区校验；强制重装也不例外。'),
			progress
		]));
		root.appendChild(E('div',{class:'cbi-section',style:'padding:16px'},[
			E('h3',{},'固件检测与升级日志'), result
		]));
		readSettings().then(function(){
			checkUpdate();
			loadTags();
		}).catch(function(e){result.textContent='读取配置失败：'+e.message;});
		return root;
	}
});
