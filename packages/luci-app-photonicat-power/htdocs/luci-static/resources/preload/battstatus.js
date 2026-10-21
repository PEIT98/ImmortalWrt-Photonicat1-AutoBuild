'use strict';
'require ui';
'require rpc';
'require poll';
'require baseclass';

const callBatteryStatus = rpc.declare({ object: 'luci.battstatus', method: 'getBatteryStatus', expect: { '': {} } });
const callHeaderStatus = rpc.declare({ object: 'luci.photonicat_header', method: 'status', expect: { '': {} } });
const devices = {}, warned = {};
const HEADER_CACHE_KEY = 'photonicat-header-cache-v1';
const HEADER_CACHE_MS = 60000;
let headerStyleReady = false, headerStyleLoading = false, pendingHeader = null;

function readHeaderCache() {
	try {
		const cached = JSON.parse(sessionStorage.getItem(HEADER_CACHE_KEY));
		const age = Date.now() - cached.updatedAt;
		return cached.header && age >= 0 && age < HEADER_CACHE_MS ? cached : null;
	} catch (e) { return null; }
}

function saveHeaderCache(header, battery, updatedAt) {
	if (!header || !updatedAt || Date.now() - updatedAt >= HEADER_CACHE_MS) return;
	try { sessionStorage.setItem(HEADER_CACHE_KEY, JSON.stringify({ header, battery, updatedAt })); }
	catch (e) {}
}

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

const SVG_NS = 'http://www.w3.org/2000/svg';

function shape(tag, attrs, content) {
	const element = document.createElementNS(SVG_NS, tag);
	for (const key in attrs)
		element.setAttribute(key, String(attrs[key]));
	if (content != null)
		element.textContent = String(content);
	return element;
}

function svg(shapes, viewBox) {
	const element = shape('svg', { viewBox: viewBox || '0 0 24 24', fill: 'none',
		stroke: 'currentColor', 'stroke-width': '1.8', 'stroke-linecap': 'round',
		'stroke-linejoin': 'round', 'aria-hidden': 'true' });
	for (const child of shapes) element.appendChild(child);
	return element;
}

function icon(kind, level, state, charging) {
	switch (kind) {
	case 'signal':
		return svg([ [2, 16, 4], [7, 12, 8], [12, 8, 12], [17, 4, 16] ].map(function(bar, index) {
			return shape('rect', { x: bar[0], y: bar[1], width: 3, height: bar[2], rx: 1,
				fill: 'currentColor', stroke: 'none', opacity: index < level ? 1 : .22 });
		}));
	case 'ethernet':
		return svg([ shape('path', { d: 'M9 2H19V4H21V6H23V9H26V21H2V9H5V6H7V4H9Z' +
			'M5 14H7V19H5ZM9 14H11V19H9ZM13 14H15V19H13Z' +
			'M17 14H19V19H17ZM21 14H23V19H21Z',
			'fill-rule': 'evenodd', fill: 'currentColor', stroke: 'none' }) ].concat(state === 'on' ?
			[shape('rect', { x: 1, y: 23, width: 26, height: 2.3, rx: 1.15,
				fill: '#1ac766', stroke: 'none' })] : []), '0 0 28 26');
	case 'wifi':
		return svg([ shape('path', { d: 'M2 9a16 16 0 0 1 20 0M5 12a11 11 0 0 1 14 0M8.5 15.5a6 6 0 0 1 7 0' }),
			shape('circle', { cx: 12, cy: 19, r: 1, fill: 'currentColor', stroke: 'none' }) ]);
	case 'car':
		return svg([ shape('circle', { cx: 12, cy: 12, r: 9 }),
			shape('path', { d: 'M3.5 9.5h17M10.7 15.3l-1.5 5M13.3 15.3l1.5 5' }),
			shape('circle', { cx: 12, cy: 13.5, r: 2.2 }) ]);
	case 'timer':
		return svg([ shape('circle', { cx: 12, cy: 12, r: 9 }),
			shape('path', { d: 'M12 6.5V12l4 2.3' }) ]);
	case 'manual':
		return svg([ shape('path', { d: 'M3 7h8m4 0h6M3 17h3m4 0h11' }),
			shape('circle', { cx: 13, cy: 7, r: 2 }),
			shape('circle', { cx: 8, cy: 17, r: 2 }) ]);
	case 'unknown':
		return svg([ shape('circle', { cx: 12, cy: 12, r: 9 }),
			shape('path', { d: 'M9.5 9a2.5 2.5 0 1 1 4 2l-1.5 1.2V14M12 17h.01' }) ]);
	case 'battery':
		return svg([ shape('rect', { x: 1, y: 2, width: 33, height: 16, rx: 3 }),
			shape('path', { d: 'M36 7v6' }),
			shape('rect', { x: 3, y: 4, width: Math.max(0, Math.min(29, Math.round((Number.isFinite(level) ? level : 0) * 29 / 100))),
				height: 12, rx: 1, fill: 'currentColor', stroke: 'none', opacity: .16 }),
			shape('text', { x: charging ? 16 : 17.5, y: 13.8, 'text-anchor': 'middle',
				'font-size': 10, 'font-weight': 700, fill: 'currentColor', stroke: 'none' },
				Number.isFinite(level) ? Math.round(level) : '—') ].concat(charging ?
				[shape('path', { d: 'M30.5 4.5 27.2 10h2.5L28.5 16l4-7h-2.3l1.9-4.5Z',
					'class': 'pcat-charge-bolt', fill: 'currentColor', stroke: 'none' })] : []), '0 0 39 20');
	}
}

function item(kind, label, title, state, textLabel, target, level, charging) {
	const attrs = { 'class': 'pcat-item pcat-' + kind, 'data-state': state,
		title: title, 'aria-label': title };
	if (target) attrs.href = L.url(target);
	else attrs.role = 'img';
	const children = [icon(kind, level, state, charging)];
	if (label) children.push(E('span', { 'class': 'pcat-label' }, label));
	if (textLabel) children.push(E('span', { 'class': 'pcat-name' }, textLabel));
	const element = E(target ? 'a' : 'span', attrs, children);
	element._pcatKey = JSON.stringify([kind, label, title, state, textLabel, target, level, charging]);
	return element;
}

function aurora() {
	return !!document.querySelector('link[href*="/luci-static/aurora/main.css"]');
}

function headerStyle() {
	if (!aurora()) return null;
	let link = document.getElementById('photonicat-header-style');
	if (!link) {
		link = E('link', { id: 'photonicat-header-style', rel: 'stylesheet',
			href: L.resource('photonicat-header.css') });
		document.head.appendChild(link);
	}
	return link;
}

function decorateNativeBattery(info) {
	for (const el of document.querySelectorAll('#indicators > span[data-indicator]')) {
		if (el.getAttribute('data-indicator') !== info.name) continue;
		el.title = info.status;
		if (info.power_page && !el.hasAttribute('data-power-link')) {
			el.setAttribute('data-power-link', '1');
			el.setAttribute('role', 'link');
			el.setAttribute('tabindex', '0');
			el.setAttribute('aria-label', '打开光影猫管理');
			el.style.cursor = 'pointer';
			el.addEventListener('click', function() { window.location.href = L.url('admin/system/photonicat-power'); });
			el.addEventListener('keydown', function(event) {
				if (event.key === 'Enter' || event.key === ' ') {
					event.preventDefault();
					el.click();
				}
			});
		}
		if (info.valid && info.percentage <= 20) el.style.color = 'Red';
		else if (info.valid && info.percentage <= 30) el.style.color = 'GoldenRod';
		else el.style.removeProperty('color');
		break;
	}
}

function showHeader(data, battery) {
	const style = headerStyle();
	if (!style) return;
	if (!style.sheet && !headerStyleReady) {
		pendingHeader = { data, battery };
		if (!headerStyleLoading) {
			headerStyleLoading = true;
			const ready = function() {
				if (headerStyleReady) return;
				headerStyleReady = true;
				const latest = pendingHeader;
				pendingHeader = null;
				if (latest) showHeader(latest.data, latest.battery);
			};
			style.addEventListener('load', ready, { once: true });
			style.addEventListener('error', ready, { once: true });
		}
		return;
	}
	pendingHeader = null;
	const indicators = document.getElementById('indicators');
	if (!indicators) return;
	let strip = document.getElementById('photonicat-status');
	if (!strip) {
		strip = E('div', { id: 'photonicat-status', role: 'group', 'aria-label': '光影猫设备状态' });
		indicators.prepend(strip);
	}
	const cells = [], cellular = data && data.cellular || {};
	const connection = cellular.connection || 'unknown';
	const connected = connection === 'yes';
	const generation = connected ? (cellular.generation || '已连接') :
		(connection === 'no' ? '无服务' : '读取中');
	const bars = connected ? Math.max(0, Math.min(4, Number(cellular.bars) || 0)) : 0;
	const cellTitle = generation + (connected && cellular.rsrp ? ' · RSRP ' + cellular.rsrp + ' dBm' : '');
	cells.push(item('signal', generation, cellTitle,
		connected ? 'on' : (connection === 'no' ? 'off' : 'unknown'), null, 'admin/modem/qmodem', bars));
	const ethernet = data && data.ethernet || [
		{ name: 'eth0', label: 'WAN' }, { name: 'eth1', label: 'LAN' }
	];
	ethernet.forEach(function(port) {
		const title = (port.label || port.name) + ' (' + port.name + ') · ' +
			(port.linked == null ? '状态未知' : (port.linked ? '已连接' : '未连接'));
		cells.push(item('ethernet', null, title, port.linked == null ? 'unknown' : (port.linked ? 'on' : 'off'),
			null, 'admin/network/network'));
	});
	const wifi = data && data.wifi || [];
	wifi.forEach(function(radio) {
		const title = radio.phy + (radio.driver ? ' · ' + radio.driver : '') +
			' · 驱动已加载 · ' + (radio.enabled ? '已开启' : '未开启');
		cells.push(item('wifi', null, title, radio.enabled ? 'on' : 'off', null, 'admin/network/wireless'));
	});
	const mode = data && data.mode || '';
	const modeName = { manual: '手动', car: '车载', timer: '定时' }[mode] || '未读取';
	cells.push(item(mode || 'unknown', null, '电池模式 · ' + modeName, mode ? 'on' : 'unknown',
		modeName, 'admin/system/photonicat-power'));
	if (battery && battery.indicator_enabled !== false) {
		const percentage = battery.valid ? Number(battery.percentage) : null;
		const title = battery.valid
			? (battery.charging ? '外部供电' : '电池供电') + ' · ' + percentage + '%'
			: (battery.message || '电量暂不可用');
		cells.push(item('battery', null, title,
			battery.valid ? (percentage <= 20 ? 'low' : 'on') : 'unknown', null,
			battery.power_page ? 'admin/system/photonicat-power' : null, percentage, battery.charging));
	}
	for (let i = 0; i < cells.length; i++) {
		const current = strip.children[i];
		if (!current) strip.appendChild(cells[i]);
		else if (current._pcatKey !== cells[i]._pcatKey) strip.replaceChild(cells[i], current);
	}
	while (strip.children.length > cells.length) strip.removeChild(strip.lastElementChild);
}

return baseclass.extend({
	__init__() {
		const cached = readHeaderCache();
		this.revision = 0;
		this.headerRevision = 0;
		this.headerData = cached ? cached.header : null;
		this.batteryData = cached ? cached.battery : null;
		this.headerUpdatedAt = cached ? cached.updatedAt : 0;
		this.batteryUpdatedAt = cached ? cached.updatedAt : 0;
		this.headerReady = !!cached;
		this.batteryReady = !!cached;
		headerStyle();
		if (cached) showHeader(this.headerData, this.batteryData);
		this.updateIndicator();
		this.updateHeader();
		poll.add(L.bind(this.updateIndicator, this), 5);
		poll.add(L.bind(this.updateHeader, this), 15);
		document.addEventListener('photonicat-battery-settings-changed', L.bind(this.updateIndicator, this));
	},
	renderHeader() {
		if (!this.headerReady || !this.batteryReady) return;
		showHeader(this.headerData, this.batteryData);
		saveHeaderCache(this.headerData, this.batteryData, this.headerUpdatedAt);
	},
	updateHeader() {
		const revision = ++this.headerRevision;
		return callHeaderStatus().then(L.bind(function(data) {
			if (revision !== this.headerRevision) return;
			this.headerData = data;
			this.headerUpdatedAt = Date.now();
			this.headerReady = true;
			this.renderHeader();
		}, this)).catch(L.bind(function() {
			if (revision !== this.headerRevision) return;
			if (Date.now() - this.headerUpdatedAt >= HEADER_CACHE_MS) this.headerData = null;
			this.headerReady = true;
			this.renderHeader();
		}, this));
	},
	updateIndicator() {
		const revision = ++this.revision;
		return callBatteryStatus().then(L.bind(function(devs) {
			if (revision !== this.revision) return;
			this.batteryData = null;
			this.batteryUpdatedAt = Date.now();
			for (const dev in devs) {
				const info = devs[dev];
				checkLowBattery(dev, info);
				info.name = 'battery-' + dev.replace(/\s/g, '-');
				devices[dev] = info;
				if (info.power_page) this.batteryData = info;
				if (info.indicator_enabled === false || aurora()) {
					ui.hideIndicator(info.name);
					continue;
				}
				info.status = info.valid
					? (info.charging ? _('Charging') : _('Not Charging')) + ': ' + info.percentage + '%'
					: info.message;
				info.state = info.valid ? 'active' : 'inactive';
				ui.showIndicator(info.name, info.status, null, info.state);
				decorateNativeBattery(info);
			}
			for (const dev in devices) {
				if (!Object.prototype.hasOwnProperty.call(devs, dev)) {
					ui.hideIndicator(devices[dev].name);
					delete devices[dev];
				}
			}
			this.batteryReady = true;
			this.renderHeader();
		}, this)).catch(L.bind(function() {
			if (revision !== this.revision) return;
			if (Date.now() - this.batteryUpdatedAt >= HEADER_CACHE_MS) this.batteryData = null;
			for (const dev in devices) {
				ui.hideIndicator(devices[dev].name);
				delete devices[dev];
			}
			this.batteryReady = true;
			this.renderHeader();
		}, this));
	}
});
