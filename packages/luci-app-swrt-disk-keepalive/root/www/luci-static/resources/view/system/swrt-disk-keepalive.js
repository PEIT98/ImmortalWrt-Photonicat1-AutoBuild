'use strict';
'require view';
'require rpc';
'require ui';
'require poll';
'require dom';

var statusCall = rpc.declare({ object: 'luci.swrt_disk_keepalive', method: 'status', expect: {} });
var configureCall = rpc.declare({ object: 'luci.swrt_disk_keepalive', method: 'configure',
    params: [ 'enabled', 'interval', 'usb_awake', 'devices' ], expect: {} });
var testCall = rpc.declare({ object: 'luci.swrt_disk_keepalive', method: 'test', params: [ 'id' ], expect: {} });

return view.extend({
    handleSave: null,
    handleSaveApply: null,
    handleReset: null,
    load: function() { return statusCall().catch(function() { return { ok: false }; }); },
    render: function(initial) {
        var writable = L.hasViewPermission(), data = null, selected = new Set(), dirty = false, busy = false, reading = false;
        var choices = E('div', { 'class': 'dk-disks' });
        var enabled = E('input', { type: 'checkbox', id: 'dk-enabled' });
        var awake = E('input', { type: 'checkbox', id: 'dk-awake' });
        var interval = E('input', { type: 'number', min: '10', max: '3600', step: '1', value: '60',
            id: 'dk-interval', 'class': 'dk-input', 'aria-label': '保活间隔（秒）' });
        var message = E('p', { role: 'status', 'aria-live': 'polite' });
        var badge = E('span', { 'class': 'dk-chip' }, '读取中');
        var save = E('button', { type: 'button', 'class': 'dk-btn primary', disabled: '' }, '保存并应用');
        var refresh = E('button', { type: 'button', 'class': 'dk-btn' }, '刷新硬盘');
        var root;

        function theme() {
            if (!root || typeof getComputedStyle !== 'function') return;
            var rgb = getComputedStyle(document.body).backgroundColor.match(/[\d.]+/g);
            if (rgb && rgb.length >= 3 && !(rgb.length === 4 && Number(rgb[3]) === 0)) {
                root.setAttribute('data-theme', Number(rgb[0]) * .2126 + Number(rgb[1]) * .7152 + Number(rgb[2]) * .0722 < 128 ? 'dark' : 'light');
            }
        }

        function error(err) { ui.addNotification(null, E('p', {}, String(err.message || err)), 'error'); }
        function accept(result) {
            if (!result || result.ok !== true) throw new Error(result && result.message || '硬盘保活服务暂不可用');
            return result;
        }
        function bytes(n) {
            return n >= 1099511627776 ? (n / 1099511627776).toFixed(2) + ' TiB' : (n / 1073741824).toFixed(1) + ' GiB';
        }
        function time(n) { return n ? new Date(n * 1000).toLocaleString() : '尚未读取'; }
        function controls() {
            save.disabled = !writable || !data || !dirty || busy || reading;
            refresh.disabled = busy || reading;
            [enabled, awake, interval].forEach(function(node) { node.disabled = !writable || busy; });
        }
        function changed() { dirty = true; controls(); }
        [enabled, awake, interval].forEach(function(node) { node.addEventListener('change', changed); node.addEventListener('input', changed); });
        function field(label, child) { return E('div', { 'class': 'dk-field' }, [ E('span', { 'class': 'dk-muted' }, label), child ]); }
        function renderDisks() {
            var rows = [], found = new Set();
            (data.devices || []).forEach(function(disk) {
                if (disk.id) found.add(disk.id);
                var checked = E('input', { type: 'checkbox', 'aria-label': '选择硬盘 ' + disk.name });
                checked.checked = selected.has(disk.id);
                checked.disabled = !writable || busy || !disk.selectable;
                checked.addEventListener('change', function() {
                    if (checked.checked) selected.add(disk.id); else selected.delete(disk.id);
                    changed();
                });
                var runtime = (data.runtime || []).find(function(row) { return row.id === disk.id; }) || {};
                var test = E('button', { type: 'button', 'class': 'dk-btn', disabled: !writable || busy || !disk.selectable ? '' : null }, '读取测试');
                test.addEventListener('click', function() {
                    if (busy || test.disabled) return;
                    busy = true; controls(); renderDisks();
                    testCall(disk.id).then(accept).then(function(result) { ui.addNotification(null, E('p', {}, result.message)); })
                        .catch(error).finally(function() { busy = false; fetchStatus(false); });
                });
                rows.push(E('article', { 'class': 'dk-disk' }, [
                    E('div', { 'class': 'dk-disk-head' }, [ E('label', { 'class': 'dk-check' }, [checked,
                        E('strong', {}, disk.model.trim() || disk.name)]), E('span', { 'class': 'dk-chip' }, bytes(disk.bytes)) ]),
                    E('p', { 'class': 'dk-muted dk-ident' }, '/dev/' + disk.name + ' · ' + (disk.driver || 'USB 存储') + (disk.serial ? ' · ' + disk.serial : '')),
                    E('p', { 'class': 'dk-muted' }, disk.mounts ? '挂载：' + disk.mounts : '未挂载（仍可保活）'),
                    E('div', { 'class': 'dk-metrics' }, [field('上次成功', E('span', {}, time(runtime.last_success))),
                        field('成功读取', E('span', {}, String(runtime.count || 0) + ' 次'))]),
                    E('div', { 'class': 'dk-disk-bottom' }, [E('span', { 'class': runtime.error || disk.reason ? 'dk-error' : 'dk-muted' },
                        disk.reason || runtime.error || (disk.usb_power === 'on' ? 'USB 自动挂起已关闭' : 'USB 自动挂起：' + (disk.usb_power || '未提供'))), test])
                ]));
            });
            selected.forEach(function(id) {
                if (found.has(id)) return;
                var remove = E('button', { type: 'button', 'class': 'dk-btn', disabled: !writable || busy ? '' : null }, '移除');
                remove.addEventListener('click', function() { selected.delete(id); changed(); renderDisks(); });
                rows.push(E('article', { 'class': 'dk-disk offline' }, [E('div', { 'class': 'dk-disk-bottom' }, [
                    E('div', {}, [E('strong', {}, '已选硬盘未连接'), E('p', { 'class': 'dk-muted dk-ident' }, id.slice(0, 21) + '…')]), remove]) ]));
            });
            if (!rows.length) rows.push(E('div', { 'class': 'dk-empty' }, [
                E('strong', {}, '未发现 USB 硬盘'), E('p', { 'class': 'dk-muted' }, '接入硬盘盒后点击“刷新硬盘”。TF 卡和内置存储不会出现在此处。') ]));
            dom.content(choices, rows);
        }
        function update(result, reset) {
            data = accept(result);
            if (!dirty || reset) {
                selected = new Set(data.selected || []);
                enabled.checked = data.enabled === true;
                awake.checked = data.usb_awake === true;
                interval.value = data.interval || 60;
                dirty = false;
            }
            badge.textContent = !data.enabled ? '未启用' : data.running ? '运行中' : '服务未运行';
            var online = (data.devices || []).filter(function(d) { return d.selectable && (data.selected || []).indexOf(d.id) >= 0; }).length;
            message.textContent = !data.enabled ? '保活已关闭，硬盘继续使用原有休眠策略。' :
                !data.running ? '已启用，但服务未运行，请重新保存或检查系统日志。' : !online ? '等待已选硬盘接入；不会改用其他硬盘。' :
                '正在保活 ' + online + ' 块硬盘，每 ' + data.interval + ' 秒读取 1 MiB。';
            renderDisks(); controls();
            theme();
        }
        function fetchStatus(reset) {
            if (reading || busy) return Promise.resolve();
            reading = true; controls();
            return statusCall().then(function(result) { update(result, reset); }).catch(function(err) {
                data = null; badge.textContent = '连接中断'; message.textContent = String(err.message || err);
                dom.content(choices, [E('p', { 'class': 'dk-muted' }, '无法读取硬盘状态，请稍后刷新。')]);
            }).finally(function() { reading = false; controls(); });
        }
        save.addEventListener('click', function() {
            if (save.disabled) return;
            var seconds = Number(interval.value);
            if (!Number.isInteger(seconds) || seconds < 10 || seconds > 3600 || (enabled.checked && !selected.size)) {
                error(new Error('请选择硬盘，并输入 10～3600 秒的整数间隔。')); return;
            }
            busy = true; controls(); renderDisks();
            configureCall(enabled.checked, seconds, awake.checked, Array.from(selected)).then(accept)
                .then(function(result) { update(result, true); ui.addNotification(null, E('p', {}, '保活设置已保存。')); })
                .catch(error).finally(function() { busy = false; controls(); renderDisks(); });
        });
        refresh.addEventListener('click', function() { fetchStatus(false); });
        function card(title, children, right) { return E('section', { 'class': 'dk-card' }, [
            E('div', { 'class': 'dk-card-head' }, [E('strong', {}, title), right || '']), E('div', { 'class': 'dk-card-body' }, children)]); }
        root = E('div', { id: 'swrt-disk-keepalive' }, [
            E('link', { rel: 'stylesheet', href: L.resource('swrt-disk-keepalive.css') + '?v=1.0.0' }),
            E('div', { 'class': 'dk-heading' }, [E('div', {}, [E('h2', {}, '硬盘保活'),
                E('p', { 'class': 'dk-muted' }, '定时直接读取，避免 USB 硬盘空闲休眠')]), badge]),
            E('div', { 'class': 'dk-workspace' }, [E('div', { 'class': 'dk-grid' }, [
                card('选择硬盘', [choices], refresh),
                card('保活设置', [
                    E('label', { 'class': 'dk-check' }, [enabled, E('span', {}, '启用硬盘保活')]),
                    field('保活间隔（秒）', interval),
                    E('p', { 'class': 'dk-muted' }, '默认 60 秒，支持 10～3600 秒。请小于硬盘盒的自动休眠时间。'),
                    E('label', { 'class': 'dk-check' }, [awake, E('span', {}, '禁用所选硬盘的 USB 自动挂起')]),
                    E('p', { 'class': 'dk-muted' }, '仅对所选硬盘生效；关闭保活后恢复原策略。'),
                    E('div', { 'class': 'dk-actions' }, [save])
                ])
            ]), E('div', { 'class': 'dk-status' }, [E('span', { 'class': 'dk-muted' }, '服务状态'), message])]),
            E('p', { 'class': 'dk-note dk-muted' }, '保活只读取、不写入硬盘，不会永久修改硬盘盒固件。它不能修复供电、线材或硬盘盒本身造成的掉盘。'),
            E('p', { 'class': 'dk-footer' }, 'SWRT · SlAlot')
        ]);
        try { update(initial, true); } catch (err) { message.textContent = err.message; controls(); }
        poll.add(function() { if (!document.getElementById('swrt-disk-keepalive')) return Promise.resolve(); return fetchStatus(false); }, 10);
        return root;
    }
});
