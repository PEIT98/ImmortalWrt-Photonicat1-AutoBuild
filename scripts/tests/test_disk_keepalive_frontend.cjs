const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname,
    '../../packages/luci-app-swrt-disk-keepalive/root/www/luci-static/resources/view/system/swrt-disk-keepalive.js'), 'utf8');
class Element {
    constructor(tag, attrs = {}, children = []) {
        this.tag = tag; this.attrs = attrs; this.children = [].concat(children || []);
        this.textContent = typeof children === 'string' ? children : '';
        this.value = attrs.value || ''; this.checked = false;
        this.disabled = attrs.disabled != null; this.handlers = {};
        if (attrs.click) this.handlers.click = attrs.click;
    }
    addEventListener(name, fn) { this.handlers[name] = fn; }
    fire(name) { if (!(name === 'click' && this.disabled)) return this.handlers[name]?.(); }
}
function walk(n) { return n instanceof Element ? [n, ...n.children.flatMap(walk)] : []; }
const id = 'wwid-' + 'a'.repeat(64);
function harness(readonly = false) {
    const h = { calls: [], polls: [], notices: [], data: {ok:true,enabled:false,usb_awake:true,interval:60,
        selected:[],running:false,devices:[],runtime:[]} };
    const context = {
        view: {extend: x => x}, E:(tag, attrs, children) => new Element(tag, attrs, children),
        rpc:{declare: spec => (...args) => {h.calls.push([spec.method,args]); return Promise.resolve(h.data);}},
        dom:{content:(node, rows) => {node.children = rows;}},
        L:{hasViewPermission:() => !readonly,resource:x => '/resources/' + x},
        poll:{add:fn => h.polls.push(fn)},
        ui:{addNotification:(...args) => h.notices.push(args)},
        document:{getElementById:()=> h.root}, console
    };
    h.view = vm.runInNewContext('(function(){' + source + '\n})()',context);
    h.root = h.view.render(h.data);
    h.find = text => walk(h.root).find(n => n.textContent === text);
    h.get = id => walk(h.root).find(n => n.attrs.id === id);
    return h;
}
(async () => {
    const empty = harness();
    assert.equal(empty.calls.length,0,'Page load must not perform disk reads or modify policy');
    assert.ok(empty.find('未发现 USB 硬盘'));
    assert.equal(empty.find('保存并应用').disabled,true);
    empty.get('dk-enabled').checked = true; empty.get('dk-enabled').fire('change');
    empty.find('保存并应用').fire('click');
    assert.equal(empty.calls.length,0,'No target must prevent enabling keepalive');
    assert.ok(empty.notices.length);
    const h = harness();
    h.data.devices = [{id,name:'sda',model:'ASM1153E Test',bytes:4e12,serial:'123',selectable:true,driver:'uas'}];
    await h.polls[0]();
    const box = walk(h.root).find(n => n.attrs['aria-label'] === '选择硬盘 sda');
    box.checked = true; box.fire('change');
    h.get('dk-interval').value = '30'; h.get('dk-interval').fire('input');
    h.get('dk-enabled').checked = true; h.get('dk-enabled').fire('change');
    await h.polls[0]();
    assert.equal(h.get('dk-interval').value,'30','Poll must preserve unsaved interval');
    assert.equal(h.get('dk-enabled').checked,true,'Poll must preserve unsaved switch');
    assert.equal(walk(h.root).find(n => n.attrs['aria-label'] === '选择硬盘 sda').checked,true);
    h.find('保存并应用').fire('click');
    await new Promise(resolve => setImmediate(resolve));
    const saved = h.calls.find(c => c[0] === 'configure');
    assert.deepEqual(JSON.parse(JSON.stringify(saved[1])),[true,30,true,[id]]);
    const read = harness(true);
    assert.equal(read.get('dk-enabled').disabled,true);
    assert.equal(read.find('保存并应用').disabled,true);
    h.data = {ok:false,message:'连接失败'};
    await h.polls[0]();
    assert.equal(h.find('保存并应用').disabled,true,'Offline service must disable saving');
    console.log('Disk UI: empty state, read-only role, validation, edit preservation and offline state passed');
})().catch(err => {console.error(err);process.exitCode=1;});
