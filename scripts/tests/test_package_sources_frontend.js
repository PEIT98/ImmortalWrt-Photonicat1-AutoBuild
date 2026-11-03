const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname,
    '../../packages/luci-app-photonicat-power/htdocs/luci-static/resources/view/photonicat-power.js'), 'utf8');

class Element {
    constructor(tag, attrs = {}, children = []) {
        this.tag = tag; this.attrs = attrs; this.children = [].concat(children || []);
        this.textContent = typeof children === 'string' ? children : '';
        this.value = attrs.value || ''; this.checked = false;
        this.disabled = Object.hasOwn(attrs, 'disabled'); this.handlers = {};
    }
    addEventListener(name, handler) { this.handlers[name] = handler; }
    setAttribute(name, value) { this.attrs[name] = value; }
    fire(name) { if (!(name === 'click' && this.disabled)) return this.handlers[name]?.(); }
}
function walk(node) { return node instanceof Element ? [node, ...node.children.flatMap(walk)] : []; }
function harness(readonly = false, offline = false) {
    const h = { calls: [], polls: [], timers: [], notifications: [],
        settings: { ok: true, source: 'nju', actual: 'nju', supported: true, repositories: 6, pending: false } };
    const context = {
        view: { extend: value => value }, E: (tag, attrs, children) => new Element(tag, attrs, children),
        L: { hasViewPermission: () => !readonly, url: route => '/cgi-bin/luci/' + route },
        rpc: { declare: spec => (...args) => {
            h.calls.push([spec.object, spec.method, args]);
            if (spec.object === 'luci.photonicat_packages') {
                if (spec.method === 'getSettings') return offline ?
                    Promise.reject(new Error('软件源服务未启动')) : Promise.resolve(h.settings);
                if (h.saveError) return Promise.resolve({ ok: false, error: h.saveError });
                h.settings = { ...h.settings, source: args[0], actual: args[0], pending: false };
                return Promise.resolve(h.settings);
            }
            if (spec.object === 'luci.battstatus') return Promise.resolve({ ok: true, enabled: true, low_alert: true, low_threshold: 20 });
            return Promise.resolve({ ok: false, error: 'MCU offline' });
        } },
        ui: { addNotification: (...args) => h.notifications.push(args) },
        poll: { add: (callback, interval) => h.polls.push([callback, interval]) },
        window: { setTimeout: callback => h.timers.push(callback), confirm: () => { throw Error('Unexpected power confirmation'); } },
        document: { dispatchEvent: () => {} }, Event: class {}, console
    };
    h.view = vm.runInNewContext('(function(){' + source + '\n})()', context);
    h.root = h.view.render();
    h.get = id => walk(h.root).find(n => n.attrs.id === id);
    h.writes = () => h.calls.filter(c => c[0] === 'luci.photonicat_packages' && c[1] === 'setSettings');
    h.start = () => h.timers.forEach(callback => callback());
    return h;
}
const flush = () => new Promise(resolve => setImmediate(resolve));

(async () => {
    const h = harness();
    assert.equal(h.writes().length, 0, 'Rendering must not change repositories');
    h.start(); await flush();
    assert.equal(h.get('pcat-package-source').value, 'nju');
    assert.equal(h.get('pcat-package-save').disabled, false, 'Package settings work while the MCU is offline');
    assert.equal(walk(h.root).find(n => n.textContent === '保存电源模式').disabled, true);
    assert.ok(walk(h.root).some(n => n.tag === 'a' && n.attrs.href === '/cgi-bin/luci/admin/system/package-manager'));
    h.get('pcat-package-source').value = 'official';
    for (const [callback] of h.polls) await callback();
    assert.equal(h.get('pcat-package-source').value, 'official', 'Power polling must preserve an unsaved source choice');
    await h.get('pcat-package-save').fire('click');
    assert.deepEqual(h.writes()[0][2], ['official']);
    assert.equal(h.settings.source, 'official');
    assert.equal(h.get('pcat-package-save').disabled, false);
    assert.equal(h.calls.filter(c => c[1] === 'set_mode' || c[1] === 'set_daily').length, 0);

    const read = harness(true);
    read.start(); await flush();
    assert.equal(read.get('pcat-package-source').disabled, true);
    await read.get('pcat-package-save').fire('click');
    assert.equal(read.writes().length, 0, 'Read-only sessions cannot change repositories');

    const failed = harness();
    failed.start(); await flush();
    failed.saveError = '软件源保存失败';
    failed.get('pcat-package-source').value = 'official';
    await failed.get('pcat-package-save').fire('click');
    assert.equal(failed.settings.source, 'nju');
    assert.equal(failed.get('pcat-package-save').disabled, false, 'A failed save can be retried');
    assert.equal(failed.notifications.at(-1)[1].textContent, '软件源保存失败');

    const offline = harness(false, true);
    offline.start(); await flush();
    assert.equal(offline.get('pcat-package-save').disabled, true);
    assert.ok(walk(offline.root).some(n => n.textContent === '软件源服务未启动'));
    console.log('Package source UI: default mirror, MCU independence, permissions, persistence and failure handling passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
