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

return baseclass.extend({
	__init__() {
		this.updateIndicator();
		poll.add(L.bind(this.updateIndicator, this), 5);
	},

	updateIndicator() {
		return callBatteryStatus().then(L.bind(function(devs) {
			for (let dev in devs) {
				let info = devs[dev];
				if (info.valid) {
					info.status = (info.charging ? _('Charging') : _('Not Charging')) + ": " + info.percentage + "%";
					info.state = "active";
					if (info.percentage <= 20)
						info.color = "Red";
					else if (info.percentage <= 30)
						info.color = "GoldenRod";
				} else {
					info.status = info.message;
					info.state = "inactive";
				}

				info.name = "battery-" + dev.replace(" ", "-");
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

				devices[dev] = info;
			}

			for (let dev in devices) {
				if (!devs.hasOwnProperty(dev)) {
					ui.hideIndicator('battery-%s'.format(dev));
					delete devices[dev];
				}
			}
		}, this));
	}
});
