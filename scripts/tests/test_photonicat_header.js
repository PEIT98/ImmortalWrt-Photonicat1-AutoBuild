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
const document = {
	head: node('head'),
	querySelector() { return {}; },
	getElementById(id) { return nodes[id]; },
	addEventListener() {}
};
let battery = { Photonicat: { valid: true, charging: false, percentage: 81,
	indicator_enabled: true, low_alert: false, power_page: true } };
let header = {
	cellular: { name: 'RM520N', generation: '5G', bars: 3, rsrp: '-91' },
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
	{ hideIndicator() {}, showIndicator() {}, addNotification() {} }, rpc,
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
	assert.match(strip.children[0].attrs.title, /RM520N · 5G · -91 dBm/);
	assert.equal(strip.children[1].attrs['data-state'], 'on');
	assert.equal(strip.children[2].attrs['data-state'], 'off');
	assert.match(strip.children[3].attrs.title, /phy0.*已开启/);
	assert.match(strip.children[4].attrs.title, /phy1.*未开启/);
	assert.match(strip.children[5].attrs.title, /车载/);
	assert.match(strip.children[6].attrs.title, /81%/);

	header = { cellular: { name: 'RM520N', generation: '', bars: 0 },
		ethernet: header.ethernet, wifi: [], mode: 'timer' };
	await app.updateHeader();
	strip = nodes['photonicat-status'];
	assert.equal(strip.children.length, 6, 'no loaded radio uses one explanatory placeholder');
	assert.match(strip.children[0].attrs.title, /无服务/);
	assert.equal(strip.children[0].attrs['data-state'], 'off');
	assert.match(strip.children[3].attrs.title, /未检测到已加载/);
	assert.match(strip.children[4].attrs.title, /定时/);

	battery = { Photonicat: { ...battery.Photonicat, indicator_enabled: false } };
	await app.updateIndicator();
	assert.equal(strip.children.length, 5, 'existing battery display switch is respected');
	console.log('Photonicat header: dual PHY, link, no-service, mode and battery states passed');
}
run().catch(error => { console.error(error); process.exitCode = 1; });
