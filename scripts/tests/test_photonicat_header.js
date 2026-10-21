// Exercise the real LuCI preload with a small DOM/RPC harness. No router is
// available in CI, so PMU/driver integration still needs a device check.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '../..');
const source = fs.readFileSync(path.join(root,
	'packages/luci-app-photonicat-power/htdocs/luci-static/resources/preload/battstatus.js'), 'utf8');
const nodes = {};
let styleImmediate = true;
function node(tag, attrs, children) {
	const result = {
		tag, attrs: attrs || {}, children: Array.isArray(children) ? children : children == null ? [] : [children],
		appendChild(child) {
			this.children.push(child);
			if (child.attrs.id) nodes[child.attrs.id] = child;
			if (this.tag === 'head' && child.tag === 'link' && styleImmediate) child.sheet = {};
		},
		prepend(child) { this.children.unshift(child); if (child.attrs.id) nodes[child.attrs.id] = child; },
		replaceChild(child, previous) { this.children[this.children.indexOf(previous)] = child; },
		removeChild(child) { this.children.splice(this.children.indexOf(child), 1); },
		get lastElementChild() { return this.children[this.children.length - 1]; },
		addEventListener(type, callback) { (this.listeners ||= {})[type] = callback; },
		dispatchEvent(type) { this.listeners[type](); }
	};
	return result;
}
nodes.indicators = node('div');
let isAurora = true, nativeShown = 0;
const nativeAttrs = { 'data-indicator': 'battery-Photonicat' };
const nativeStyle = { color: '', removeProperty(key) { this[key] = ''; } };
const nativeIndicator = {
	getAttribute(key) { return nativeAttrs[key]; },
	hasAttribute(key) { return key in nativeAttrs; },
	setAttribute(key, value) { nativeAttrs[key] = value; },
	addEventListener() {}, style: nativeStyle
};
const document = {
	head: node('head'),
	querySelector() { return isAurora ? {} : null; },
	querySelectorAll() { return [nativeIndicator]; },
	createElementNS(namespaceURI, tag) {
		return {
			tag, namespaceURI, attrs: {}, children: [],
			setAttribute(key, value) { this.attrs[key] = value; },
			appendChild(child) { this.children.push(child); }
		};
	},
	getElementById(id) { return nodes[id]; },
	addEventListener() {}
};
let battery = { Photonicat: { valid: true, charging: false, percentage: 81,
	indicator_enabled: true, low_alert: false, power_page: true } };
let header = {
	cellular: { connection: 'yes', generation: '5G', bars: 4, rsrp: '-75' },
	ethernet: [ { name: 'eth0', label: 'WAN', linked: true },
		{ name: 'eth1', label: 'LAN', linked: false } ],
	wifi: [ { phy: 'phy0', driver: 'mt7915e', enabled: true },
		{ phy: 'phy1', driver: 'mt7915e', enabled: false } ],
	mode: 'car'
};
const calls = [];
const rpc = { declare(options) {
	return () => Promise.resolve(options.object === 'luci.battstatus' ? battery : header);
} };
const storage = {};
const sessionStorage = { getItem(key) { return storage[key] || null; },
	setItem(key, value) { storage[key] = value; }, removeItem(key) { delete storage[key]; } };
const createApp = (provider) => new Function('ui', 'rpc', 'poll', 'baseclass', 'E', 'L', 'document',
	'sessionStorage', '_', source)(
	{ hideIndicator() {}, showIndicator() { nativeShown++; }, addNotification() {} }, provider,
	{ add(fn, seconds) { calls.push(seconds); } }, { extend(value) { return value; } },
	node, { bind: (fn, self) => fn.bind(self), url: x => x, resource: x => x },
	document, sessionStorage, x => x);
const app = createApp(rpc);

async function run() {
	app.__init__();
	assert.equal(nodes['photonicat-status'], undefined,
		'first load waits for both replies instead of flashing partial placeholders');
	await Promise.resolve();
	await Promise.resolve();
	assert.deepEqual(calls, [5, 15]);
	let strip = nodes['photonicat-status'];
	assert.equal(strip.children.length, 7, 'dual PHY appears as two separate Wi-Fi icons');
	for (const status of strip.children) {
		const picture = status.children[0];
		assert.equal(picture.namespaceURI, 'http://www.w3.org/2000/svg', 'icon is a real SVG element');
		assert.ok(picture.children.length > 0, 'icon has drawable SVG shapes');
		assert.ok(picture.children.every(child => child.namespaceURI === picture.namespaceURI),
			'all SVG paths use the SVG namespace');
	}
	assert.equal(strip.children[0].children.length, 2, 'modem name is not rendered');
	assert.equal(strip.children[0].children[1].children[0], '5G');
	assert.match(strip.children[0].attrs.title, /5G · RSRP -75 dBm/);
	assert.doesNotMatch(strip.children[0].attrs.title, /RM520N/);
	assert.equal(strip.children[0].children[0].children.filter(child => child.tag === 'rect' && child.attrs.opacity === '1').length,
		4, 'QModem RSRP lights all four steps');
	assert.equal(strip.children[1].attrs['data-state'], 'on');
	assert.equal(strip.children[2].attrs['data-state'], 'off');
	assert.equal(strip.children[0].attrs.href, 'admin/modem/qmodem');
	assert.equal(strip.children[1].attrs.href, 'admin/network/network');
	assert.equal(strip.children[2].attrs.href, 'admin/network/network');
	assert.equal(strip.children[3].attrs.href, 'admin/network/wireless');
	assert.equal(strip.children[4].attrs.href, 'admin/network/wireless');
	assert.match(strip.children[3].attrs.title, /phy0.*已开启/);
	assert.match(strip.children[4].attrs.title, /phy1.*未开启/);
	assert.match(strip.children[5].attrs.title, /车载/);
	assert.match(strip.children[6].attrs.title, /81%/);
	assert.equal(strip.children[6].children.length, 1, 'battery has no separate percentage label');
	assert.equal(strip.children[6].children[0].children.find(child => child.tag === 'text').textContent,
		'81', 'percentage is drawn inside the battery SVG');
	assert.equal(strip.children[6].children[0].children.some(child => child.attrs.class === 'pcat-charge-bolt'),
		false, 'battery power does not show a charging bolt');
	const unchangedPort = strip.children[1];
	await app.updateIndicator();
	assert.strictEqual(strip.children[1], unchangedPort, 'identical polling keeps existing icons');
	battery.Photonicat.percentage = 80;
	await app.updateIndicator();
	assert.strictEqual(strip.children[1], unchangedPort, 'battery changes leave the port icon in place');
	assert.match(strip.children[6].attrs.title, /80%/);
	battery.Photonicat.charging = true;
	battery.Photonicat.percentage = 100;
	await app.updateIndicator();
	assert.ok(strip.children[6].children[0].children.some(child => child.attrs.class === 'pcat-charge-bolt'),
		'external power adds the SVG bolt while preserving the live percentage');
	assert.equal(strip.children[6].children[0].children.find(child => child.tag === 'text').textContent,
		'100', 'the battery number comes from the PMU RPC');

	header = { cellular: { connection: 'no', generation: '', bars: 0 },
		ethernet: header.ethernet, wifi: [], mode: 'timer' };
	await app.updateHeader();
	strip = nodes['photonicat-status'];
	assert.equal(strip.children.length, 5, 'no Wi-Fi icons without a loaded PHY');
	assert.match(strip.children[0].attrs.title, /无服务/);
	assert.equal(strip.children[0].attrs['data-state'], 'off');
	header.cellular = { connection: 'yes', generation: '4G', bars: 2, rsrp: '-92' };
	await app.updateHeader();
	assert.match(strip.children[0].attrs.title, /4G · RSRP -92 dBm/);
	assert.equal(strip.children[0].attrs['data-state'], 'on');
	header.cellular = { connection: 'unknown', generation: '', bars: 0 };
	await app.updateHeader();
	assert.equal(strip.children[0].attrs.title, '读取中', 'a failed status request is not called no service');
	assert.match(strip.children[3].attrs.title, /定时/);
	assert.equal(strip.children[3].children[0].namespaceURI, 'http://www.w3.org/2000/svg');
	const timerIcon = strip.children[3].children[0];
	header.mode = 'manual';
	await app.updateHeader();
	assert.match(strip.children[3].attrs.title, /手动/);
	assert.notStrictEqual(strip.children[3].children[0], timerIcon, 'mode changes update only its icon');
	header.mode = 'car';
	await app.updateHeader();
	assert.match(strip.children[3].attrs.title, /车载/);
	assert.equal(strip.children[3].attrs.href, 'admin/system/photonicat-power');

	battery = { Photonicat: { ...battery.Photonicat, indicator_enabled: false } };
	await app.updateIndicator();
	assert.equal(strip.children.length, 4, 'existing battery display switch is respected');
	isAurora = false;
	battery = { Photonicat: { ...battery.Photonicat, indicator_enabled: true, percentage: 19 } };
	await app.updateIndicator();
	assert.equal(nativeShown, 1, 'other themes retain the native battery indicator');
	assert.equal(nativeAttrs['data-power-link'], '1', 'native battery remains linked to management');
	assert.equal(nativeStyle.color, 'Red', 'native low battery color remains');

	isAurora = true;
	header.cellular = { connection: 'yes', generation: '5G', bars: 3, rsrp: '-83' };
	await app.updateHeader();
	assert.ok(storage['photonicat-header-cache-v1'], 'recent status is kept for navigation');
	nodes.indicators = node('div');
	delete nodes['photonicat-status'];
	delete nodes['photonicat-header-style'];
	document.head = node('head');
	styleImmediate = false;
	const pendingRpc = { declare() { return () => new Promise(() => {}); } };
	const nextPage = createApp(pendingRpc);
	nextPage.__init__();
	assert.equal(nodes['photonicat-status'], undefined, 'icons wait for their stylesheet to avoid a flash');
	nodes['photonicat-header-style'].sheet = {};
	nodes['photonicat-header-style'].dispatchEvent('load');
	assert.match(nodes['photonicat-status'].children[0].attrs.title, /5G · RSRP -83 dBm/,
		'navigation shows the recent status before either new reply');
	const expired = JSON.parse(storage['photonicat-header-cache-v1']);
	expired.updatedAt = Date.now() - 61000;
	storage['photonicat-header-cache-v1'] = JSON.stringify(expired);
	delete nodes['photonicat-status'];
	const stalePage = createApp(pendingRpc);
	stalePage.__init__();
	assert.equal(nodes['photonicat-status'], undefined, 'expired status is not shown as live data');
	console.log('Photonicat header: links, steady polling, navigation cache and radio states passed');
}
run().catch(error => { console.error(error); process.exitCode = 1; });
