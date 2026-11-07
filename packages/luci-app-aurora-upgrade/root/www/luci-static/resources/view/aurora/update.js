'use strict';
'require view';
'require rpc';
'require ui';

var statusCall = rpc.declare({ object: 'luci.aurora_update', method: 'status', expect: {} });
var checkCall = rpc.declare({ object: 'luci.aurora_update', method: 'check', expect: {} });
var sourceCall = rpc.declare({ object: 'luci.aurora_update', method: 'set_source', params: [ 'source' ], expect: {} });
var installCall = rpc.declare({ object: 'luci.aurora_update', method: 'install', params: [ 'package' ], expect: {} });

return view.extend({
    handleSave: null,
    handleSaveApply: null,
    handleReset: null,
    load: function() { return statusCall(); },
    render: function(initial) {
        var writable = L.hasViewPermission();
        var busy = false;
        var source = E('select', { 'class': 'cbi-input-select', 'aria-label': 'Aurora 更新下载地址' }, [
            E('option', { value: 'proxy' }, '国内加速（gh-proxy.com）'),
            E('option', { value: 'github' }, 'GitHub 官方')
        ]);
        var check = E('button', { type: 'button', 'class': 'btn cbi-button-action' }, '检查 Aurora 更新');
        var message = E('p', { role: 'status', 'aria-live': 'polite' });
        var rows = {};
        var packages = [
            [ 'luci-theme-aurora', 'Aurora 主题' ],
            [ 'luci-app-aurora-config', 'Aurora 设置' ]
        ];
        var state = initial;

        function accept(result) {
            if (!result || result.ok !== true) throw new Error(result && result.message || '更新服务没有响应');
            return result;
        }
        function notify(error) {
            ui.addNotification(null, E('p', {}, String(error.message || error)), 'error');
        }
        function update(result) {
            state = accept(result);
            source.value = state.source === 'github' ? 'github' : 'proxy';
            source.disabled = check.disabled = !writable || busy;
            packages.forEach(function(item) {
                var pkg = item[0];
                var installed = (state.installed || {})[pkg] || '未安装';
                var release = ((state.releases || {}).packages || {})[pkg] || {};
                rows[pkg].installed.textContent = installed;
                rows[pkg].available.textContent = release.version || '待检查';
                var upgradeable = !!(state.upgradeable || {})[pkg];
                rows[pkg].button.disabled = !writable || busy || !upgradeable;
                rows[pkg].button.textContent = !release.version ? '待检查' : upgradeable ? '下载并安装' : '当前版本不低于发布版本';
            });
            message.textContent = state.releases ? '发布信息已核对；安装前还会校验下载文件的 SHA256。' :
                '点击检查更新，从 Aurora 作者的 GitHub Releases 获取版本。';
        }
        function perform(call, after) {
            if (busy) return Promise.resolve();
            busy = true;
            source.disabled = check.disabled = true;
            packages.forEach(function(item) { rows[item[0]].button.disabled = true; });
            return call().then(accept).then(function(result) {
                if (after) after(result);
                return statusCall().then(accept).then(update);
            }).catch(function(error) {
                notify(error);
                return statusCall().then(accept).then(update).catch(notify);
            }).finally(function() {
                busy = false;
                if (state) update(state);
            });
        }

        var cards = packages.map(function(item) {
            var installed = E('strong', {}, '—');
            var available = E('strong', {}, '—');
            var button = E('button', { type: 'button', 'class': 'btn cbi-button-action' }, '下载并安装');
            rows[item[0]] = { installed: installed, available: available, button: button };
            button.addEventListener('click', function() {
                var pkg = item[0];
                var release = ((state.releases || {}).packages || {})[pkg] || {};
                if (!(state.upgradeable || {})[pkg] || busy) return;
                var confirm = E('button', { type: 'button', 'class': 'btn cbi-button-action important' }, '确认安装');
                confirm.addEventListener('click', function() {
                    ui.hideModal();
                    perform(function() { return installCall(pkg); }, function(result) {
                        ui.addNotification(null, E('p', {}, result.message || '更新完成，请刷新页面'));
                    });
                });
                ui.showModal('确认 Aurora 更新', [
                    E('p', {}, item[1] + '：' + (state.installed[pkg] || '未安装') + ' → ' + release.version),
                    E('p', {}, '从所选地址下载，核对 GitHub 发布的文件大小与 SHA256 后安装。'),
                    E('div', { 'class': 'right' }, [
                        E('button', { type: 'button', 'class': 'btn', click: ui.hideModal }, '取消'),
                        ' ', confirm
                    ])
                ]);
            });
            return E('div', { style: 'border:1px solid var(--hairline, #bbb);border-radius:8px;padding:14px;flex:1 1 240px;' }, [
                E('h3', {}, item[1]),
                E('p', {}, [ '已安装：', installed ]),
                E('p', {}, [ 'GitHub 发布：', available ]),
                button
            ]);
        });
        source.addEventListener('change', function() {
            if (!busy) perform(function() { return sourceCall(source.value); });
        });
        check.addEventListener('click', function() {
            perform(checkCall);
        });
        var page = E('div', {}, [
            E('h2', {}, 'Aurora 更新'),
            E('p', {}, '保留 Aurora 作者的签名软件源。这里在源无法访问时，通过 GitHub 发布包更新主题和设置。'),
            E('div', { style: 'display:flex;align-items:center;gap:12px;flex-wrap:wrap;margin:16px 0;' }, [
                E('label', {}, [ '下载地址：', source ]), check
            ]),
            message,
            E('div', { style: 'display:flex;gap:12px;flex-wrap:wrap;' }, cards),
            E('p', { style: 'margin-top:16px;opacity:.8;' },
                '从 GitHub APK 安装后，后续更新仍可使用本页面；作者签名源及其他系统软件源保持原样。')
        ]);
        try { update(initial); } catch (error) { notify(error); }
        return page;
    }
});
