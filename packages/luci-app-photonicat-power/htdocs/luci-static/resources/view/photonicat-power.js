'use strict';
'require view';
'require rpc';
'require ui';
'require poll';

var statusCall = rpc.declare({ object: 'luci.photonicat_power', method: 'status', expect: {} });
var batteryCall = rpc.declare({ object: 'luci.photonicat_power', method: 'battery', expect: {} });
var modeCall = rpc.declare({ object: 'luci.photonicat_power', method: 'set_mode', params: [ 'mode', 'minutes' ], expect: {} });
var dailyCall = rpc.declare({ object: 'luci.photonicat_power', method: 'set_daily', params: [ 'start', 'stop' ], expect: {} });

function prettyTime(v) {
    var h = Number(v.hour), m = Number(v.minute);
    return String(h).padStart(2, '0') + ':' + String(m).padStart(2, '0');
}

return view.extend({
    render: function() {
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
            E('p', { 'class': 'cbi-value-description' }, '插电自动开机，拔电后延时关机；0 分钟表示不延迟。')
        ]);
        var timerBox = E('div', { style: 'margin:12px 0' }, [
            E('p', {}, [ '每天开机时间： ', start ]),
            E('p', {}, [ '每天关机时间： ', stop ]),
            E('p', { 'class': 'cbi-value-description' }, '每天按设定时间开关机；保存会覆盖原来的定时计划。')
        ]);
        var batteryInfo = E('div', { 'class': 'cbi-section', style: 'margin:8px 0 14px;padding:14px;border-radius:14px' }, '正在读取电量……');
        var info = E('p', { style: 'font-weight:600;margin:8px 0' }, '正在读取电源模式……');
        var detail = E('p', { 'class': 'cbi-value-description', style: 'line-height:1.6' });
        var button = E('button', { 'class': 'btn cbi-button cbi-button-apply', disabled: 'disabled' }, '保存电源模式');

        function displayMode() {
            carBox.style.display = mode.value === 'car' ? '' : 'none';
            timerBox.style.display = mode.value === 'timer' ? '' : 'none';
        }
        function updateBattery(data) {
            if (!data || !data.ok) {
                batteryInfo.textContent = '电池数据暂不可用';
                return;
            }
            var pct = Number(data.battery_percentage), mv = Number(data.battery_mv), cv = Number(data.charger_mv);
            if (!Number.isFinite(pct) || !Number.isFinite(mv) || mv <= 0) {
                batteryInfo.textContent = '等待 MCU 电池数据';
                return;
            }
            batteryInfo.textContent = '电量 ' + pct + '%  ·  ' +
                (Number(data.on_battery) === 1 ? '电池供电' : '外部供电/充电') +
                '  ·  电池 ' + (mv / 1000).toFixed(2) + 'V  ·  外部 ' +
                (cv / 1000).toFixed(2) + 'V  ·  板温 ' + data.board_temp + '°C';
        }
        function update(data) {
            updateBattery(data);
            if (!data || !data.ok) {
                info.textContent = '读取电源设置失败：' + (data && data.error ? data.error : '未知错误');
                detail.textContent = '请检查电源管理服务是否正常。';
                button.disabled = true;
                return;
            }
            var schedules = [];
            try {
                var parsed = JSON.parse(data.schedule || '{}');
                schedules = Array.isArray(parsed['event-list']) ? parsed['event-list'] : [];
            } catch (e) {
                info.textContent = '定时计划读取异常，暂时不能保存';
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
            var onBattery = Number(data.on_battery) === 1;
            var supply = onBattery ? '电池供电（外部电源已断开）' : '外部供电';
            var left = Number(data.car_countdown);
            var countdown = onBattery && Number.isFinite(left) && left >= 0
                ? '；剩余约 ' + Math.ceil(left) + ' 秒' : (onBattery ? '；倒计时已到或不可用' : '');
            info.textContent = '当前：' + name +
                (current === 'car' ? '；供电：' + supply + countdown : '');
            detail.textContent = '定时计划：' + schedules.length + ' 条。' +
                (current === 'car' ? ' 拔电后点击“刷新状态”可查看倒计时。' : '') +
                ' 保存新模式会替换原来的电源计划。';
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
            if (!window.confirm('确认保存电源模式？原有车载或定时计划会被替换。'))
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
            E('h2', {}, '光影猫 · 电源管理'),
            E('div', { 'class': 'cbi-section' }, [
                batteryInfo, info, detail,
                E('p', { 'class': 'cbi-value-description' },
                    '仅管理自动开关机，不影响网络和 QModem。'),
                E('p', {}, [ E('label', {}, [ '运行模式： ', mode ]) ]),
                carBox, timerBox,
                E('p', {}, [ button, ' ', refresh ])
            ])
        ]);
        displayMode();
        // Show LuCI page immediately; read modes in the background.
        // Let the browser paint the page before starting MCU/RPC requests.
        window.setTimeout(function() {
            statusCall().then(update).catch(function(e) { update({ ok: false, error: String(e) }); });
        }, 0);
        // Battery polling does not fetch car/timer settings each time.
        poll.add(function() { return batteryCall().then(updateBattery).catch(function() { updateBattery(null); }); }, 15);
        return page;
    },
    handleSaveApply: null,
    handleSave: null,
    handleReset: null
});
