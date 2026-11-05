'use strict';
'require view';
'require rpc';
'require ui';
'require poll';

var statusCall = rpc.declare({ object: 'luci.swrt_upgrade', method: 'status', expect: {} });
var checkCall = rpc.declare({ object: 'luci.swrt_upgrade', method: 'check', expect: {} });
var downloadCall = rpc.declare({ object: 'luci.swrt_upgrade', method: 'download', expect: {} });
var channelCall = rpc.declare({ object: 'luci.swrt_upgrade', method: 'set_channel', params: [ 'channel' ], expect: {} });
var sourceCall = rpc.declare({ object: 'luci.swrt_upgrade', method: 'set_source', params: [ 'source' ], expect: {} });
var installCall = rpc.declare({ object: 'luci.swrt_upgrade', method: 'install', params: [ 'keep', 'sha256' ], expect: {} });

return view.extend({
    handleSave: null,
    handleSaveApply: null,
    handleReset: null,

    load: function() {
        return statusCall().catch(function() { return { ok: false, message: '在线更新服务暂不可用' }; });
    },

    render: function(initial) {
        var writable = L.hasViewPermission();
        var latest = null, pending = false, polling = false, reconnecting = false;
        var installRequested = false, statusFailures = 0;
        var current = E('strong', {}, '—'), available = E('strong', {}, '—');
        var filesystem = E('strong', {}, '—'), size = E('strong', {}, '—');
        var filename = E('span', {}, '检查后显示匹配的固件');
        var digest = E('code', {}, '下载时获取并验证');
        var message = E('p', { role: 'status', 'aria-live': 'polite' });
        var progress = E('progress', { max: '100', value: '0', 'aria-label': '固件下载进度' });
        var progressText = E('span', { 'class': 'np-hint' });
        var notes = E('pre', { 'class': 'swrt-release-notes' }, '检查更新后显示发布说明。');
        var releaseLink = E('a', { href: 'https://gh-proxy.com/#https://github.com/PEIT98/ImmortalWrt-Photonicat1-AutoBuild', target: '_blank', rel: 'noopener noreferrer' }, '查看发布页面');
        var keep = E('input', { type: 'checkbox', id: 'swrt-keep-config', 'aria-describedby': 'swrt-keep-help' });
        var keepState = E('strong', { 'class': 'swrt-keep-state', 'aria-live': 'polite' });
        var keepHint = E('span', { id: 'swrt-keep-help', 'class': 'swrt-keep-hint' });
        var keepChoice = E('label', { 'class': 'swrt-keep', 'for': 'swrt-keep-config' }, [ keep,
            E('span', { 'class': 'swrt-keep-copy' }, [
                E('strong', { 'class': 'swrt-keep-title' }, '保留配置升级'), keepState, keepHint
            ])
        ]);
        var checkButton = E('button', { type: 'button', 'class': 'np-btn primary' }, '检查更新');
        var downloadButton = E('button', { type: 'button', 'class': 'np-btn', disabled: '' }, '下载并校验');
        var installButton = E('button', { type: 'button', 'class': 'np-btn primary', disabled: '' }, '确认升级');
        var backupButton = E('button', { type: 'button', 'class': 'np-btn' }, '下载配置备份');
        var updateSource = E('select', { id: 'swrt-update-source', 'class': 'np-input', 'aria-label': '在线更新源' }, [
            E('option', { value: 'proxy' }, '国内加速（gh-proxy.com）'),
            E('option', { value: 'github' }, 'GitHub 官方')
        ]);
        var updateChannel = E('select', { id: 'swrt-update-channel', 'class': 'np-input', 'aria-label': '版本通道' }, [
            E('option', { value: 'prerelease' }, '正式版＋预发行版'),
            E('option', { value: 'stable' }, '仅正式版')
        ]);
        var root;

        function notifyError(err) {
            ui.addNotification(null, E('p', {}, String(err.message || err)), 'error');
        }
        function accept(result) {
            if (!result || result.ok !== true) throw new Error(result && result.message || '操作未成功，请重试');
            return result;
        }
        function bytes(value) { return (Math.max(0, Number(value) || 0) / 1048576).toFixed(1) + ' MiB'; }
        function updateKeepChoice() {
            keepChoice.dataset.keep = keep.checked ? '1' : '0';
            keepState.textContent = keep.checked ? '已勾选：保留配置' : '未勾选：恢复默认配置';
            keepHint.textContent = keep.checked ? '升级后沿用现有网络、Wi-Fi 和拨号设置。' :
                '升级后恢复固件默认设置，需重新配置网络、Wi-Fi 和拨号。';
        }
        function update(data) {
            accept(data);
            latest = data;
            var state = data.state || {}, release = data.release || {};
            statusFailures = 0;
            if ([ 'preparing', 'installing' ].indexOf(state.phase) !== -1) installRequested = true;
            var busy = [ 'checking', 'downloading', 'verifying', 'preparing', 'installing' ].indexOf(state.phase) !== -1;
            current.textContent = data.current ? data.current : '需要手动安装支持在线更新的固件';
            available.textContent = release.version ? release.version + (release.prerelease ? '（预发行）' : '（正式版）') : '待检查';
            filesystem.textContent = data.filesystem || '未识别';
            size.textContent = release.size ? bytes(release.size) : '—';
            filename.textContent = release.name || '检查后显示匹配的固件';
            digest.textContent = release.sha256 || '下载时获取并验证';
            notes.textContent = String(release.notes || '暂无发布说明。').slice(0, 24000);
            releaseLink.href = data.source === 'github' ? 'https://github.com/PEIT98/ImmortalWrt-Photonicat1-AutoBuild/releases' :
                'https://gh-proxy.com/#https://github.com/PEIT98/ImmortalWrt-Photonicat1-AutoBuild';
            message.textContent = state.message || '';
            message.dataset.phase = state.phase || 'idle';
            checkButton.disabled = !writable || pending || busy;
            downloadButton.disabled = !writable || pending || !data.eligible || state.phase !== 'available';
            installButton.disabled = !writable || pending || !data.eligible || state.phase !== 'ready';
            keep.disabled = !writable || pending || busy;
            backupButton.disabled = !writable || busy;
            updateSource.disabled = updateChannel.disabled = !writable || pending || busy;
            if (!pending) {
                updateSource.value = data.source === 'github' ? 'github' : 'proxy';
                updateChannel.value = data.channel === 'stable' ? 'stable' : 'prerelease';
            }
            progress.hidden = state.phase !== 'downloading';
            progressText.hidden = state.phase !== 'downloading';
            var percent = release.size ? Math.min(100, 100 * Math.max(0, Number(data.downloaded_bytes) || 0) / release.size) : 0;
            progress.value = percent;
            progressText.textContent = state.phase === 'downloading' ? bytes(data.downloaded_bytes) + ' / ' + bytes(release.size) + ' · ' + Math.floor(percent) + '%' : '';
            if (state.phase === 'failed') installRequested = false;
        }
        function refresh() {
            return statusCall().then(function(data) {
                accept(data);
                installRequested = [ 'preparing', 'installing' ].indexOf((data.state || {}).phase) !== -1;
                update(data);
            });
        }
        function statusUnavailable(err) {
            latest = null;
            checkButton.disabled = downloadButton.disabled = installButton.disabled = true;
            keep.disabled = backupButton.disabled = true;
            updateSource.disabled = updateChannel.disabled = true;
            statusFailures++;
            if (installRequested) {
                message.textContent = '设备连接暂时中断，正在等待升级和重启，请勿断电。';
                if (statusFailures >= 2 && !reconnecting) {
                    reconnecting = true;
                    ui.showModal('等待设备重新连接', [ E('p', { 'class': 'spinning' }, '升级请求已提交，设备连接已中断。请勿断电，正在等待重新连接。') ]);
                    ui.awaitReconnect(window.location.host, '172.16.0.1');
                }
            } else {
                message.textContent = '暂时无法获取任务状态：' + String(err.message || err);
            }
        }
        function perform(call) {
            if (pending) return Promise.resolve();
            pending = true;
            if (latest) update(latest);
            return call().then(accept).then(function() { return refresh().catch(statusUnavailable); })
                .catch(function(err) {
                    notifyError(err);
                    return refresh().catch(statusUnavailable);
                }).finally(function() {
                pending = false;
                if (latest) update(latest);
            });
        }
        keep.addEventListener('change', updateKeepChoice);
        checkButton.addEventListener('click', function() { perform(checkCall); });
        downloadButton.addEventListener('click', function() { perform(downloadCall); });
        updateSource.addEventListener('change', function() {
            if (updateSource.disabled) return Promise.resolve();
            var selected = updateSource.value;
            return perform(function() { return sourceCall(selected); });
        });
        updateChannel.addEventListener('change', function() {
            if (updateChannel.disabled) return Promise.resolve();
            var selected = updateChannel.value;
            return perform(function() { return channelCall(selected); });
        });
        backupButton.addEventListener('click', function() {
            var form = E('form', { method: 'post', action: L.env.cgi_base + '/cgi-backup' },
                E('input', { type: 'hidden', name: 'sessionid', value: rpc.getSessionID() }));
            root.appendChild(form);
            form.submit();
            form.remove();
        });
        installButton.addEventListener('click', function() {
            if (!latest || !latest.eligible || latest.state.phase !== 'ready' || pending) return;
            var release = latest.release, preserve = keep.checked;
            var acknowledged = E('input', { type: 'checkbox' });
            var confirm = E('button', { type: 'button', 'class': 'np-btn danger', disabled: '' }, '开始刷写并重启');
            acknowledged.addEventListener('change', function() { confirm.disabled = !acknowledged.checked; });
            confirm.addEventListener('click', function() {
                if (!acknowledged.checked) return;
                confirm.disabled = true;
                installRequested = true;
                ui.hideModal();
                perform(function() { return installCall(preserve ? 1 : 0, release.sha256); });
            });
            ui.showModal('确认更新至 ' + release.version, [
                E('p', { 'class': 'swrt-confirm-file' }, release.name),
                E('p', {}, release.prerelease ? '这是预发行测试固件，可能包含尚未完成真机验证的改动。' : '这是正式发行固件。'),
                E('p', {}, preserve ? '保留当前配置。旧配置可能覆盖新版默认设置。' : '不保留配置。完成后通过 172.16.0.1 重新设置密码、Wi-Fi 和拨号。'),
                E('p', {}, '刷写会中断网络，请勿断电。额外安装的软件包和容器数据需另行备份。'),
                E('label', { 'class': 'swrt-confirm-backup' }, [ acknowledged, ' 我已保存需要的配置和数据，确认现在升级。' ]),
                E('div', { 'class': 'np-actions right' }, [
                    E('button', { type: 'button', 'class': 'np-btn', click: ui.hideModal }, '取消'), confirm
                ])
            ], 'np-root', 'np-dialog', 'swrt-upgrade-confirm');
        });
        function field(label, value) {
            return E('div', { 'class': 'np-info-field' }, [ E('span', { 'class': 'np-info-label' }, label), value ]);
        }
        function card(title, content, extraClass) {
            return E('section', { 'class': 'np-native-card' + (extraClass ? ' ' + extraClass : '') }, [
                E('div', { 'class': 'np-native-card-head' }, E('strong', {}, title)),
                E('div', { 'class': 'np-native-card-body' }, content)
            ]);
        }
        root = E('div', { id: 'swrt-upgrade', 'class': 'np-root swrt-page' }, [
            E('link', { rel: 'stylesheet', href: L.resource('swrt-upgrade.css') + '?v=2.0.0-3' }),
            E('div', { 'class': 'np-page-heading' }, [
                E('div', {}, [ E('h2', { 'class': 'np-page-title' }, 'Pwrt 在线更新'),
                    E('p', { 'class': 'np-page-description' }, '光影猫一代 · PEIT98 仓库 · 支持正式与预发行固件') ]),
                E('span', { 'class': 'np-chip' }, 'Photonicat 1')
            ]),
            E('div', { 'class': 'swrt-workspace' }, [
            E('div', { 'class': 'swrt-source-bar' }, [
                E('label', { 'for': 'swrt-update-source' }, '更新源'), updateSource,
                E('span', { 'class': 'np-hint' }, '检查更新与固件下载均使用所选源。')
            ]),
            E('div', { 'class': 'swrt-source-bar' }, [
                E('label', { 'for': 'swrt-update-channel' }, '版本通道'), updateChannel,
                E('span', { 'class': 'np-hint' }, '预发行版会明确标注；下载后需手动确认升级。')
            ]),
            E('div', { 'class': 'swrt-main-grid' }, [
                card('固件版本', [
                    E('div', { 'class': 'np-info-grid' }, [ field('当前版本', current), field('可用版本', available), field('系统类型', filesystem), field('固件大小', size) ]),
                    E('div', { 'class': 'np-actions' }, [ checkButton, downloadButton ])
                ]),
                card('升级准备', [
                    E('div', { 'class': 'np-actions swrt-backup' }, [ backupButton,
                        E('a', { 'class': 'np-btn', href: L.url('admin/system/flash') }, '恢复配置备份') ]),
                    E('div', { 'class': 'swrt-keep-group' }, [ keepChoice ]),
                    E('div', { 'class': 'np-actions' }, [ installButton,
                        E('a', { href: L.url('admin/system/flash') }, '手动上传固件') ])
                ])
            ]),
            E('div', { 'class': 'swrt-status-strip' }, [ E('span', { 'class': 'swrt-status-label' }, '任务状态'), message, progress, progressText ]),
            E('details', { 'class': 'swrt-details', open: '' }, [ E('summary', {}, '固件文件与校验信息'),
                E('div', { 'class': 'swrt-file swrt-details-content' }, [ field('匹配固件', filename), field('SHA256', digest) ]) ]),
            E('details', { 'class': 'swrt-details', open: '' }, [ E('summary', {}, '发布说明'),
                E('div', { 'class': 'swrt-details-content' }, [ notes, releaseLink ]) ])
            ]),
            E('p', { 'class': 'np-footer' }, 'Pwrt · 更新器基于 SlAlot SWRT 适配')
        ]);
        keep.checked = !initial || initial.keep_default !== false;
        updateKeepChoice();
        if (initial && initial.ok === true) update(initial);
        else statusUnavailable(new Error(initial && initial.message || '在线更新服务暂不可用'));
        poll.add(function() {
            if (polling || pending || !document.getElementById('swrt-upgrade')) return Promise.resolve();
            polling = true;
            return refresh().catch(statusUnavailable).finally(function() { polling = false; });
        }, 2);
        return root;
    }
});
