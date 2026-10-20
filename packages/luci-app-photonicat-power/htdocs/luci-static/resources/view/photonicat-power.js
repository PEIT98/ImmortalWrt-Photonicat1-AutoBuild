'use strict';
'require view';
'require rpc';
'require ui';
'require poll';

var statusCall = rpc.declare({ object: 'luci.photonicat_power', method: 'status', expect: {} });
var runtimeCall = rpc.declare({ object: 'luci.photonicat_power', method: 'runtime', expect: {} });
var modeCall = rpc.declare({ object: 'luci.photonicat_power', method: 'set_mode', params: [ 'mode', 'minutes' ], expect: {} });
var dailyCall = rpc.declare({ object: 'luci.photonicat_power', method: 'set_daily', params: [ 'start', 'stop' ], expect: {} });
var settingsCall = rpc.declare({ object: 'luci.battstatus', method: 'getSettings', expect: {} });
var saveSettingsCall = rpc.declare({ object: 'luci.battstatus', method: 'setSettings', params: [ 'enabled', 'low_alert', 'low_threshold' ], expect: {} });

function prettyTime(v) {
    return String(Number(v.hour)).padStart(2, '0') + ':' + String(Number(v.minute)).padStart(2, '0');
}

return view.extend({
    render: function() {
        var writable = L.hasViewPermission();
        var lastBattery = null, live = null, currentMode = 'manual';
        var readBusy = false, saving = false, settingsReady = false, modeReady = false;
        var preferences = { enabled: true, low_alert: true, low_threshold: 20 };
        var names = { manual: '手动模式', car: '车载 / UPS 模式', timer: '定时模式' };
        var percentage = E('strong', { 'class': 'pcat-percentage' }, '--%');
        var supply = E('span', { 'class': 'pcat-badge' }, '正在读取');
        var meter = E('progress', { max: '100', value: '0', 'aria-label': '电池电量' });
        var batteryVoltage = E('strong', {}, '--');
        var chargerVoltage = E('strong', {}, '--');
        var temperature = E('strong', {}, '--');
        var warning = E('p', { 'class': 'pcat-warning', hidden: '' });
        var updated = E('span', { 'class': 'pcat-muted' }, '正在连接电源服务……');
        var info = E('p', { 'class': 'pcat-current' }, '正在读取电源模式……');
        var detail = E('p', { 'class': 'pcat-muted' });
        var mode = E('select', { 'class': 'cbi-input-select', disabled: '' }, [
            E('option', { value: 'manual' }, names.manual),
            E('option', { value: 'car' }, names.car),
            E('option', { value: 'timer' }, names.timer)
        ]);
        var minutes = E('input', { type: 'number', min: '0', max: '600', step: '1', value: '5', 'class': 'cbi-input-text', 'aria-label': '拔电后延迟关机分钟数' });
        var start = E('input', { type: 'time', value: '08:00', 'aria-label': '每天开机时间' });
        var stop = E('input', { type: 'time', value: '23:00', 'aria-label': '每天关机时间' });
        var carBox = E('div', { 'class': 'pcat-mode-options' }, [
            E('label', { 'class': 'pcat-row' }, [ E('span', {}, '拔电后延迟关机'), E('span', {}, [ minutes, ' 分钟' ]) ]),
            E('p', { 'class': 'pcat-muted' }, '插电自动开机，拔电后延时关机；0 分钟表示立即关机。')
        ]);
        var timerBox = E('div', { 'class': 'pcat-mode-options' }, [
            E('label', { 'class': 'pcat-row' }, [ E('span', {}, '每天开机'), start ]),
            E('label', { 'class': 'pcat-row' }, [ E('span', {}, '每天关机'), stop ]),
            E('p', { 'class': 'pcat-muted' }, '按设备时间每天执行，保存会替换原来的计划。')
        ]);
        var button = E('button', { 'class': 'btn cbi-button cbi-button-apply', disabled: '' }, '保存电源模式');
        var refresh = E('button', { 'class': 'btn cbi-button' }, '刷新状态');
        var showIndicator = E('input', { type: 'checkbox', role: 'switch', 'class': 'pcat-switch', disabled: '' });
        var lowAlert = E('input', { type: 'checkbox', role: 'switch', 'class': 'pcat-switch', disabled: '' });
        var threshold = E('input', { type: 'number', min: '5', max: '50', step: '1', value: '20', 'class': 'cbi-input-text', disabled: '', 'aria-label': '低电量提醒阈值百分比' });
        var settingsNote = E('p', { 'class': 'pcat-muted' }, '正在读取显示设置……');
        var settingsButton = E('button', { 'class': 'btn cbi-button cbi-button-apply', disabled: '' }, '保存显示设置');

        function displayMode() {
            carBox.hidden = mode.value !== 'car';
            timerBox.hidden = mode.value !== 'timer';
        }
        function updateWarning() {
            var low = lastBattery && Number(lastBattery.on_battery) === 1 && preferences.low_alert &&
                Number(lastBattery.battery_percentage) <= preferences.low_threshold;
            warning.hidden = !low;
            warning.textContent = low ? '电量偏低，请及时接通电源。' : '';
        }
        function updateBattery(data) {
            var pct = Number(data && data.battery_percentage), mv = Number(data && data.battery_mv);
            if (!data || !data.ok || !Number.isFinite(pct) || pct < 0 || pct > 100 || !Number.isFinite(mv) || mv <= 0) {
                lastBattery = null;
                percentage.textContent = '--%';
                supply.textContent = '暂不可用';
                batteryVoltage.textContent = chargerVoltage.textContent = temperature.textContent = '--';
                meter.value = 0;
                updated.textContent = '电池数据暂不可用，稍后会自动重试';
                updateWarning();
                return false;
            }
            lastBattery = data;
            percentage.textContent = pct + '%';
            meter.value = pct;
            supply.textContent = Number(data.on_battery) === 1 ? '电池供电' : '外部供电';
            supply.setAttribute('data-battery', String(Number(data.on_battery) === 1));
            batteryVoltage.textContent = (mv / 1000).toFixed(2) + ' V';
            chargerVoltage.textContent = Number.isFinite(Number(data.charger_mv)) ? (Number(data.charger_mv) / 1000).toFixed(2) + ' V' : '--';
            temperature.textContent = Number.isFinite(Number(data.board_temp)) ? data.board_temp + ' °C' : '--';
            updated.textContent = '更新于 ' + new Date().toLocaleTimeString() + ' · 每 15 秒刷新';
            updateWarning();
            return true;
        }
        function showRuntime() {
            if (!live) return;
            info.textContent = '当前：' + names[currentMode];
            if (Number(live.data.car_state) !== 1) return;
            if (Number(live.data.on_battery) !== 1) {
                info.textContent += ' · 外部供电';
                return;
            }
            var seconds = Number(live.data.car_countdown);
            if (!Number.isFinite(seconds) || seconds < 0) {
                info.textContent += ' · 电池供电 · 倒计时暂不可用';
                return;
            }
            // Interpolate between read-only samples; only the MCU service controls shutdown.
            var age = Math.floor((Date.now() - live.at) / 1000);
            if (age > 30) {
                info.textContent += ' · 等待倒计时更新';
                return;
            }
            var left = Math.max(0, seconds - age);
            info.textContent += left > 0 ? ' · 约 ' + Math.floor(left / 60) + ' 分 ' + (left % 60) + ' 秒后关机' : ' · 等待设备执行关机';
        }
        function updateRuntime(data) {
            if (!updateBattery(data)) {
                live = null;
                info.textContent = '暂时无法读取电源状态';
                return false;
            }
            currentMode = Number(data.car_state) === 1 ? 'car' : (currentMode === 'car' ? 'manual' : currentMode);
            live = { data: data, at: Date.now() };
            showRuntime();
            return true;
        }
        function updateStatus(data, resetInputs) {
            if (!updateRuntime(data)) {
                detail.textContent = data && data.error || '请检查电源管理服务是否正常。';
                button.disabled = true;
                return;
            }
            var schedules;
            try {
                var parsed = JSON.parse(data.schedule || '{}');
                if (!Array.isArray(parsed['event-list'])) throw new Error('invalid schedule');
                schedules = parsed['event-list'];
            } catch (e) {
                detail.textContent = '定时计划读取异常，暂时不能保存';
                button.disabled = true;
                return;
            }
            currentMode = Number(data.car_state) === 1 ? 'car' : (schedules.length ? 'timer' : 'manual');
            showRuntime();
            if (resetInputs || !modeReady) {
                mode.value = currentMode;
                if (currentMode === 'car' && Number.isFinite(Number(data.car_seconds))) minutes.value = Math.ceil(Number(data.car_seconds) / 60);
                var on = schedules.find(function(e) { return e.action === 1 && e.enabled !== 0; });
                var off = schedules.find(function(e) { return e.action === 0 && e.enabled !== 0; });
                if (on) start.value = prettyTime(on);
                if (off) stop.value = prettyTime(off);
                displayMode();
            }
            modeReady = true;
            mode.disabled = !writable;
            button.disabled = !writable || saving;
            detail.textContent = '定时计划 ' + schedules.length + ' 条；保存新模式会替换原来的电源计划。';
        }
        function fetchStatus(resetInputs) {
            if (readBusy || saving) return Promise.resolve();
            readBusy = true;
            refresh.disabled = true;
            return statusCall().then(function(data) { updateStatus(data, resetInputs); })
                .catch(function(err) { updateStatus({ ok: false, error: String(err) }, false); })
                .finally(function() { readBusy = false; refresh.disabled = false; });
        }
        function updatePreferences(data) {
            if (!data || !data.ok) throw new Error(data && data.error || '读取显示设置失败');
            preferences = data;
            settingsReady = true;
            showIndicator.checked = !!data.enabled;
            lowAlert.checked = !!data.low_alert;
            threshold.value = data.low_threshold;
            showIndicator.disabled = lowAlert.disabled = settingsButton.disabled = !writable;
            threshold.disabled = !writable || !lowAlert.checked;
            settingsNote.textContent = '保存后立即生效，重启保留。提醒仅在路由器后台打开时生效。';
            updateWarning();
        }
        lowAlert.addEventListener('change', function() { threshold.disabled = !writable || !lowAlert.checked; });
        settingsButton.addEventListener('click', function() {
            var value = Number(threshold.value);
            if (!settingsReady || !writable) return;
            if (!Number.isInteger(value) || value < 5 || value > 50) {
                ui.addNotification(null, E('p', {}, '请输入 5～50 的整数电量'));
                return;
            }
            settingsButton.disabled = true;
            saveSettingsCall(showIndicator.checked ? 1 : 0, lowAlert.checked ? 1 : 0, value)
                .then(function(result) {
                    updatePreferences(result);
                    document.dispatchEvent(new Event('photonicat-battery-settings-changed'));
                    ui.addNotification(null, E('p', {}, '显示设置已保存'));
                })
                .catch(function(err) { ui.addNotification(null, E('p', {}, String(err))); })
                .finally(function() { settingsButton.disabled = !writable; });
        });
        mode.addEventListener('change', displayMode);
        button.addEventListener('click', function() {
            if (!writable || saving || readBusy) return;
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
            if (!window.confirm('确认保存电源模式？原有车载或定时计划会被替换。')) return;
            saving = true;
            button.disabled = refresh.disabled = true;
            var operation = selected === 'timer' ? dailyCall(start.value, stop.value) : modeCall(selected, selected === 'car' ? value : 0);
            operation.then(function(result) {
                if (!result || !result.ok) throw new Error(result && result.error || 'MCU 设置未成功');
                ui.addNotification(null, E('p', {}, '电源策略保存成功'));
            }).catch(function(err) { ui.addNotification(null, E('p', {}, String(err))); })
                .finally(function() { saving = false; refresh.disabled = false; return fetchStatus(true); });
        });
        // Refresh live state without replacing unsaved form selections.
        refresh.addEventListener('click', function() { fetchStatus(false); });
        var page = E('div', { 'class': 'cbi-map pcat-power' }, [
            E('style', {}, [
                '.pcat-power{max-width:1040px;margin:0 auto}.pcat-power [hidden]{display:none!important}',
                '.pcat-power .pcat-card{padding:22px;margin:18px 0;border:1px solid rgba(128,128,128,.2);border-radius:16px;background:rgba(128,128,128,.035)}',
                '.pcat-power .pcat-hero{background:linear-gradient(120deg,rgba(37,99,235,.1),rgba(14,165,150,.05))}',
                '.pcat-power .pcat-head,.pcat-power .pcat-row{display:flex;align-items:center;justify-content:space-between;gap:16px}',
                '.pcat-power .pcat-row{padding:12px 0}.pcat-power h3{margin:0 0 8px}.pcat-power .pcat-percentage{font-size:42px;line-height:1.3;letter-spacing:-1px}',
                '.pcat-power .pcat-badge{font-size:13px;padding:5px 12px;border-radius:20px;background:rgba(37,99,235,.13)}',
                '.pcat-power .pcat-badge[data-battery="true"]{background:rgba(217,119,6,.15)}',
                '.pcat-power progress{display:block;width:100%;height:9px;border:0;border-radius:8px;margin:14px 0 22px;accent-color:#2563eb;overflow:hidden}',
                '.pcat-power progress::-webkit-progress-bar{background:rgba(128,128,128,.18)}.pcat-power progress::-webkit-progress-value{background:#2563eb;border-radius:8px}',
                '.pcat-power .pcat-stats{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:14px;margin-bottom:18px}',
                '.pcat-power .pcat-stats strong{display:block;font-size:20px;margin-top:4px}.pcat-power .pcat-muted{font-size:13px;opacity:.7;line-height:1.7}',
                '.pcat-power .pcat-warning{padding:10px 14px;border-radius:8px;background:rgba(217,119,6,.13);color:inherit}',
                '.pcat-power .pcat-current{font-weight:600;line-height:1.7}.pcat-power .pcat-actions{display:flex;gap:10px;flex-wrap:wrap;margin-top:16px}',
                '.pcat-power .pcat-row input[type=number]{width:84px;min-width:0}.pcat-power .pcat-row select{max-width:60%}',
                '.pcat-power .pcat-switch{appearance:none;-webkit-appearance:none;flex:0 0 42px;width:42px;height:24px;min-height:24px;padding:0;margin:0;border:0;border-radius:20px;background:#8a9099;cursor:pointer;position:relative;box-shadow:none}',
                '.pcat-power .pcat-switch::before{content:"";position:absolute;top:3px;left:3px;width:18px;height:18px;border-radius:50%;background:white;transition:transform .15s}',
                '.pcat-power .pcat-switch:checked{background:#2563eb}.pcat-power .pcat-switch:checked::before{transform:translateX(18px)}',
                '.pcat-power .pcat-switch:focus-visible{outline:2px solid #2563eb;outline-offset:3px}.pcat-power input:disabled{opacity:.5;cursor:default}',
                '@media(max-width:600px){.pcat-power .pcat-card{padding:16px;margin:12px 0}.pcat-power .pcat-stats{gap:8px}.pcat-power .pcat-stats strong{font-size:17px}.pcat-power .pcat-percentage{font-size:36px}.pcat-power .pcat-row{gap:10px}}'
            ].join('')),
            E('h2', {}, '光影猫管理'),
            E('p', { 'class': 'pcat-muted' }, '查看电池状态，设置电量显示和自动开关机。'),
            E('section', { 'class': 'pcat-card pcat-hero' }, [
                E('div', { 'class': 'pcat-head' }, [ percentage, supply ]), meter,
                E('div', { 'class': 'pcat-stats' }, [
                    E('div', {}, [ E('span', { 'class': 'pcat-muted' }, '电池电压'), batteryVoltage ]),
                    E('div', {}, [ E('span', { 'class': 'pcat-muted' }, '外部电压'), chargerVoltage ]),
                    E('div', {}, [ E('span', { 'class': 'pcat-muted' }, '主板温度'), temperature ])
                ]), warning, updated
            ]),
            E('section', { 'class': 'pcat-card' }, [
                E('h3', {}, '电量显示'),
                E('label', { 'class': 'pcat-row' }, [ E('span', {}, '右上角显示电量'), showIndicator ]),
                E('label', { 'class': 'pcat-row' }, [ E('span', {}, '低电量提醒'), lowAlert ]),
                E('label', { 'class': 'pcat-row' }, [ E('span', {}, '电量低于或等于'), E('span', {}, [ threshold, ' %' ]) ]),
                settingsNote, E('div', { 'class': 'pcat-actions' }, [ settingsButton ])
            ]),
            E('section', { 'class': 'pcat-card' }, [
                E('h3', {}, '自动开关机'), info, detail,
                E('label', { 'class': 'pcat-row' }, [ E('span', {}, '运行模式'), mode ]),
                carBox, timerBox, E('div', { 'class': 'pcat-actions' }, [ button, refresh ])
            ])
        ]);
        displayMode();
        minutes.disabled = start.disabled = stop.disabled = !writable;
        // Paint immediately, then load independent MCU and display settings.
        window.setTimeout(function() {
            fetchStatus(true);
            settingsCall().then(updatePreferences).catch(function(err) { settingsNote.textContent = String(err); });
        }, 0);
        poll.add(function() {
            if (readBusy || saving) return Promise.resolve();
            readBusy = true;
            // Runtime excludes timer schedules and never resets edited controls.
            return runtimeCall().then(updateRuntime).catch(function() { updateRuntime(null); })
                .finally(function() { readBusy = false; });
        }, 15);
        poll.add(function() { showRuntime(); }, 1);
        return page;
    },
    handleSaveApply: null,
    handleSave: null,
    handleReset: null
});
