'use strict';
'require view';
'require rpc';
'require ui';

var statusCall = rpc.declare({ object: 'luci.photonicat_power', method: 'status', expect: {} });
var modeCall = rpc.declare({ object: 'luci.photonicat_power', method: 'set_mode', params: [ 'mode', 'minutes' ], expect: {} });
var dailyCall = rpc.declare({ object: 'luci.photonicat_power', method: 'set_daily', params: [ 'start', 'stop' ], expect: {} });

function prettyTime(v) {
    var h = Number(v.hour), m = Number(v.minute);
    return String(h).padStart(2, '0') + ':' + String(m).padStart(2, '0');
}

return view.extend({
    load: function() { return statusCall().catch(function(e) { return { ok: false, error: String(e) }; }); },
    render: function(initial) {
        var mode = E('select', { 'class': 'cbi-input-select' }, [
            E('option', { value: 'manual' }, '手动模式'),
            E('option', { value: 'car' }, '车载 / UPS 模式'),
            E('option', { value: 'timer' }, '定时模式')
        ]);
        var minutes = E('input', { type: 'number', min: '0', max: '600', step: '1', value: '5', 'class': 'cbi-input-text', style: 'width:110px' });
        var start = E('input', { type: 'time', value: '08:00' });
        var stop = E('input', { type: 'time', value: '23:00' });
        var carBox = E('div', { style: 'margin:12px 0' }, [
            E('label', {}, [ '外部电源断开后延迟（分钟）： ', minutes ]),
            E('p', { 'class': 'cbi-value-description' }, '接通外部电源自动开机；拔掉外部电源后延时安全关机。0 表示不延迟。')
        ]);
        var timerBox = E('div', { style: 'margin:12px 0' }, [
            E('p', {}, [ '每天开机时间： ', start ]),
            E('p', {}, [ '每天关机时间： ', stop ]),
            E('p', { 'class': 'cbi-value-description' }, '简单定时模式：每天各执行一次。保存会替换 MCU 原有全部定时计划。')
        ]);
        var info = E('p', {}, '正在读取 MCU 电源状态……');
        var detail = E('p', { 'class': 'cbi-value-description' });
        var button = E('button', { 'class': 'btn cbi-button cbi-button-apply', disabled: 'disabled' }, '保存电源模式');

        function displayMode() {
            carBox.style.display = mode.value === 'car' ? '' : 'none';
            timerBox.style.display = mode.value === 'timer' ? '' : 'none';
        }
        function update(data) {
            if (!data || !data.ok) {
                info.textContent = '电源控制接口不可用：' + (data && data.error ? data.error : '未知错误');
                detail.textContent = '现有电池显示与 Go 版 pcat-mgr 不会被修改。';
                button.disabled = true;
                return;
            }
            var schedules = [];
            try {
                var parsed = JSON.parse(data.schedule || '{}');
                schedules = Array.isArray(parsed['event-list']) ? parsed['event-list'] : [];
            } catch (e) {
                info.textContent = 'MCU 定时计划返回数据无效，已禁止修改';
                button.disabled = true;
                return;
            }
            var current = Number(data.car_state) === 1 ? 'car' : (schedules.length ? 'timer' : 'manual');
            mode.value = current;
            if (Number.isFinite(Number(data.car_seconds)))
                minutes.value = Math.ceil(Number(data.car_seconds) / 60);
            var on = schedules.find(function(e) { return e.action === 1 && e.enabled !== 0; });
            var off = schedules.find(function(e) { return e.action === 0 && e.enabled !== 0; });
            if (on) start.value = prettyTime(on);
            if (off) stop.value = prettyTime(off);
            var name = { manual: '手动模式', car: '车载 / UPS 模式', timer: '定时模式' }[current];
            info.textContent = '当前：' + name + '（使用 ' + data.backend + '）';
            detail.textContent = '当前 MCU 定时计划：' + schedules.length + ' 条。切换模式将清除其它模式的计划；不会影响网络和 QModem 配置。';
            button.disabled = false;
            displayMode();
        }
        mode.addEventListener('change', displayMode);
        button.addEventListener('click', function() {
            var selected = mode.value, value = Number(minutes.value);
            if (selected === 'car' && (!Number.isInteger(value) || value < 0 || value > 600)) {
                ui.addNotification(null, E('p', {}, '请输入 0～600 分钟的整数'));
                return;
            }
            if (selected === 'timer' && (!/^([01]\d|2[0-3]):[0-5]\d$/.test(start.value) ||
                !/^([01]\d|2[0-3]):[0-5]\d$/.test(stop.value) || start.value === stop.value)) {
                ui.addNotification(null, E('p', {}, '请填写不同的合法开关机时间'));
                return;
            }
            if (!window.confirm('确认修改 MCU 电源策略？原有车载/定时模式设置会被清除，定时模式只保存每天两条计划。'))
                return;
            button.disabled = true;
            var operation = selected === 'timer'
                ? dailyCall(start.value, stop.value)
                : modeCall(selected, selected === 'car' ? value : 0);
            operation.then(function(result) {
                if (!result || !result.ok) throw new Error(result && result.error || 'MCU 设置未成功');
                ui.addNotification(null, E('p', {}, '电源策略保存成功'));
                return statusCall().then(update);
            }).catch(function(err) {
                ui.addNotification(null, E('p', {}, String(err)));
                return statusCall().then(update).catch(function() { button.disabled = true; });
            });
        });
        var refresh = E('button', { 'class': 'btn cbi-button' }, '刷新状态');
        refresh.addEventListener('click', function() {
            button.disabled = true;
            statusCall().then(update).catch(function(e) { update({ ok: false, error: String(e) }); });
        });
        var page = E('div', { 'class': 'cbi-map' }, [
            E('h2', {}, '光影猫一代 · 电源管理'),
            E('div', { 'class': 'cbi-section' }, [
                info, detail,
                E('p', { 'class': 'cbi-value-description' },
                    '本插件仅连接光影猫一代官方 MCU 控制 Socket。不访问串口，不停止 pcat-mgr，也不包含二代专用的直连电源模式。'),
                E('p', {}, [ E('label', {}, [ '运行模式： ', mode ]) ]),
                carBox, timerBox,
                E('p', {}, [ button, ' ', refresh ])
            ])
        ]);
        displayMode();
        update(initial);
        return page;
    },
    handleSaveApply: null,
    handleSave: null,
    handleReset: null
});
