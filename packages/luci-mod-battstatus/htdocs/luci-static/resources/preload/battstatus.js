'use strict';
'require ui';
'require rpc';
'require poll';
'require baseclass';

const callBatteryStatus = rpc.declare({
	object: 'luci.battstatus',
	method: 'getBatteryStatus',
	expect: { '': {} }
});

const devices = {};
const warned = {};

function checkLowBattery(dev, info) {
	const key = 'photonicat-low-battery-' + dev;
	const threshold = Number(info.low_threshold) || 20;
	try { warned[dev] = sessionStorage.getItem(key) === '1'; } catch (e) {}
	if (!info.low_alert || (info.valid && (info.charging || info.percentage > threshold + 3))) {
		delete warned[dev];
		try { sessionStorage.removeItem(key); } catch (e) {}
	} else if (info.valid && !info.charging && info.percentage <= threshold && !warned[dev]) {
		ui.addNotification(null, E('p', {}, '电池电量剩余 ' + info.percentage + '%，请及时接通电源。'), 'warning');
		warned[dev] = true;
		try { sessionStorage.setItem(key, '1'); } catch (e) {}
	}
}

return baseclass.extend({
	__init__() {
		this.revision = 0;
		this.updateIndicator();
		poll.add(L.bind(this.updateIndicator, this), 5);
		document.addEventListener('photonicat-battery-settings-changed', L.bind(this.updateIndicator, this));
	},

	updateIndicator() {
		const revision = ++this.revision;
		return callBatteryStatus().then(L.bind(function(devs) {
			if (revision !== this.revision)
				return;
			for (let dev in devs) {
				let info = devs[dev];
				checkLowBattery(dev, info);
				info.name = 'battery-' + dev.replace(/\s/g, '-');
				devices[dev] = info;
				if (info.indicator_enabled === false) {
					ui.hideIndicator(info.name);
					continue;
				}
				if (info.valid) {
					info.status = (info.power_page ? (info.charging ? '外部供电' : '电池供电') :
						(info.charging ? _('Charging') : _('Not Charging'))) + ': ' + info.percentage + '%';
					info.state = "active";
					if (info.percentage <= 20)
						info.color = "Red";
					else if (info.percentage <= 30)
						info.color = "GoldenRod";
				} else {
					info.status = info.message;
					info.state = "inactive";
				}

				const auroraTheme = document.querySelector('link[href*="/luci-static/aurora/main.css"]') != null;
				const batteryLabel = auroraTheme && info.valid
					? (info.charging ? '⚡ ' : '🔋 ') + info.percentage + '%'
					: info.status;
				ui.showIndicator(info.name, batteryLabel, null, info.state);
				// Photonicat1 battery-only patch; no Aurora file changes.
				// Keep ui.showIndicator()'s text node intact for 5-second updates.
				let el = null;
				for (const node of document.querySelectorAll('#indicators > span[data-indicator]')) {
					if (node.getAttribute('data-indicator') == info.name) {
						el = node;
						break;
					}
				}
				if (el) {
					el.title = info.status;
					if (info.power_page && !el.hasAttribute('data-power-link')) {
						el.setAttribute('data-power-link', '1');
						el.setAttribute('role', 'link');
						el.setAttribute('tabindex', '0');
						el.setAttribute('aria-label', '打开电池与电源管理');
						el.style.cursor = 'pointer';
						el.addEventListener('click', function() { window.location.href = L.url('admin/system/photonicat-power'); });
						el.addEventListener('keydown', function(event) {
							if (event.key === 'Enter' || event.key === ' ') {
								event.preventDefault();
								el.click();
							}
						});
					}
					if (auroraTheme) {
						// The battery plugin hides Aurora's generic empty icon at runtime.
						// Nothing in the Aurora theme package is edited.
						if (!document.getElementById('photonicat-battery-only-style')) {
							const sheet = document.createElement('style');
							sheet.id = 'photonicat-battery-only-style';
							sheet.textContent = '#indicators span[data-indicator^="battery-"]::before { display:none !important; content:none !important; }';
							document.head.appendChild(sheet);
						}
						const styles = {
							display: 'inline-flex',
							'align-items': 'center',
							'justify-content': 'center',
							width: 'auto',
							'min-width': 'max-content',
							'max-width': 'none',
							height: '28px',
							'min-height': '28px',
							padding: '0 10px',
							margin: '0 4px',
							'vertical-align': 'middle',
							'font-size': '12px',
							'line-height': '28px',
							'font-weight': '500',
							background: 'rgba(37,99,235,.10)',
							border: '1px solid rgba(37,99,235,.20)',
							'border-radius': '6px',
							'text-indent': '0',
							'white-space': 'nowrap',
							overflow: 'visible',
							visibility: 'visible',
							opacity: '1',
							'box-sizing': 'border-box',
							'clip-path': 'none',
							transform: 'none'
						};
						for (const key in styles)
							el.style.setProperty(key, styles[key], 'important');
						if (info.color)
							el.style.setProperty('color', info.color, 'important');
						else
							el.style.removeProperty('color');
					} else {
						// Preserve native appearance under Bootstrap/other themes.
						if (info.color)
							el.style.setProperty('color', info.color);
						else
							el.style.removeProperty('color');
					}
				}

			}

			for (let dev in devices) {
				if (!devs.hasOwnProperty(dev)) {
					ui.hideIndicator(devices[dev].name);
					delete devices[dev];
				}
			}
		}, this)).catch(function() {
			if (revision === this.revision) {
				for (const dev in devices) {
					ui.hideIndicator(devices[dev].name);
					delete devices[dev];
				}
			}
		}.bind(this));
	}
});
