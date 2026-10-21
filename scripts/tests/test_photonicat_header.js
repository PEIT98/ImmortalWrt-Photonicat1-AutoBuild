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
function node(tag, attrs, children) {
	const result = {
		tag, attrs: attrs || {}, children: Array.isArray(children) ? children : children == null ? [] : [children],
		appendChild(child) { this.children.push(child); if (child.attrs.id) nodes[child.attrs.id] = child; },
		prepend(child) { this.children.unshift(child); if (child.attrs.id) nodes[child.attrs.id] = child; },
		replaceChildren(...items) { this.children = items; }
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
const app = new Function('ui', 'rpc', 'poll', 'baseclass', 'E', 'L', 'document',
	'sessionStorage', '_', source)(
	{ hideIndicator() {}, showIndicator() { nativeShown++; }, addNotification() {} }, rpc,
	{ add(fn, seconds) { calls.push(seconds); } }, { extend(value) { return value; } },
	node, { bind: (fn, self) => fn.bind(self), url: x => x, resource: x => x },
	document, { getItem() { return null; }, setItem() {}, removeItem() {} }, x => x);

async function run() {
	app.__init__();
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
	assert.match(strip.children[3].attrs.title, /phy0.*已开启/);
	assert.match(strip.children[4].attrs.title, /phy1.*未开启/);
	assert.match(strip.children[5].attrs.title, /车载/);
	assert.match(strip.children[6].attrs.title, /81%/);
	assert.equal(strip.children[6].children.length, 1, 'battery has no separate percentage label');
	assert.equal(strip.children[6].children[0].children.find(child => child.tag === 'text').textContent,
		'81', 'percentage is drawn inside the battery SVG');

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

	battery = { Photonicat: { ...battery.Photonicat, indicator_enabled: false } };
	await app.updateIndicator();
	assert.equal(strip.children.length, 4, 'existing battery display switch is respected');
	isAurora = false;
	battery = { Photonicat: { ...battery.Photonicat, indicator_enabled: true, percentage: 19 } };
	await app.updateIndicator();
	assert.equal(nativeShown, 1, 'other themes retain the native battery indicator');
	assert.equal(nativeAttrs['data-power-link'], '1', 'native battery remains linked to management');
	assert.equal(nativeStyle.color, 'Red', 'native low battery color remains');
	console.log('Photonicat header: dual PHY, link, no-service, mode and battery states passed');
}
run().catch(error => { console.error(error); process.exitCode = 1; });
