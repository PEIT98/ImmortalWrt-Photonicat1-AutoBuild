const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname,
    '../../packages/luci-app-online-upgrade/root/www/luci-static/resources/view/system/swrt-upgrade.js'), 'utf8');

class Element {
    constructor(tag, attrs = {}, children = []) {
        this.tag = tag;
        this.attrs = attrs;
        this.children = [].concat(children || []);
        this.textContent = typeof children === 'string' ? children : '';
        this.disabled = Object.hasOwn(attrs, 'disabled');
        this.checked = false;
        this.dataset = {};
        this.handlers = {};
        if (attrs.click) this.handlers.click = attrs.click;
    }
    addEventListener(event, fn) { this.handlers[event] = fn; }
    appendChild(child) { this.children.push(child); }
    remove() {}
    submit() {}
    fire(event) { if (!(event === 'click' && this.disabled)) return this.handlers[event]?.(); }
}
function walk(node) {
    if (!(node instanceof Element)) return [];
    return [node, ...node.children.flatMap(walk)];
}
function harness(phase = 'available', readonly = false) {
    const state = { ok: true, eligible: true, current: '1.9', filesystem: 'squashfs', source: 'proxy', channel: 'prerelease', keep_default: true,
        state: { phase, message: '测试状态' }, downloaded_bytes: 0,
        release: { version: 'photonicat1-20261102-222244-55', prerelease: true, name: 'immortalwrt-photonicat-1-squashfs-sysupgrade-2.0.img.gz',
            size: 104857600, sha256: 'a'.repeat(64), notes: '<script>never HTML</script>' } };
    const h = { state, calls: [], modal: null, polls: [], notices: [], root: null };
    const context = {
        view: { extend: obj => obj },
        rpc: { declare: spec => (...args) => {
            h.calls.push([spec.method, args]);
            if (spec.method === 'status') return h.statusOffline ? Promise.reject(new Error('network offline')) : Promise.resolve(h.state);
            if (spec.method === 'check' && h.error) return Promise.resolve({ ok: false, message: h.error });
            if (spec.method === 'download') h.state.state.phase = 'downloading';
            if (spec.method === 'set_source') {
                if (h.sourceError) return Promise.resolve({ ok: false, message: h.sourceError });
                h.state.source = args[0]; h.state.release = null; h.state.state.phase = 'idle';
            }
            if (spec.method === 'set_channel') {
                h.state.channel = args[0]; h.state.release = null; h.state.state.phase = 'idle';
            }
            if (spec.method === 'install') {
                h.state.state.phase = 'preparing';
                if (h.installResponseLost) {
                    h.statusOffline = true;
                    return Promise.reject(new Error('Upgrade response lost'));
                }
            }
            return Promise.resolve({ ok: true });
        }, getSessionID: () => 'fixture-session' },
        E: (tag, attrs, children) => new Element(tag, attrs, children),
        L: { hasViewPermission: () => !readonly, resource: s => {
            assert.match(s, /^[a-zA-Z0-9_.%/,-]+$/, 'L.resource takes a path, not a path containing query parameters');
            return '/resources/' + s;
        },
            url: s => '/cgi-bin/luci/' + s, env: { cgi_base: '/cgi-bin' } },
        ui: { addNotification: (...args) => h.notices.push(args),
            showModal: (title, children) => { h.modal = new Element('modal', { title }, children); },
            hideModal: () => { h.modal = null; }, awaitReconnect: () => {} },
        poll: { add: fn => h.polls.push(fn) },
        document: { getElementById: id => walk(h.root).find(n => n.attrs.id === id) },
        window: { location: { host: '172.16.0.1' } }, console
    };
    h.view = vm.runInNewContext('(function(){' + source + '\n})()', context);
    h.root = h.view.render(h.state);
    h.button = text => walk(h.root).find(n => n.tag === 'button' && n.textContent === text);
    h.keep = walk(h.root).find(n => n.tag === 'input' && n.attrs.type === 'checkbox');
    h.source = walk(h.root).find(n => n.attrs.id === 'swrt-update-source');
    h.channel = walk(h.root).find(n => n.attrs.id === 'swrt-update-channel');
    return h;
}
const flush = async () => { await new Promise(resolve => setImmediate(resolve)); };

(async () => {
    const available = harness();
    assert.deepEqual(walk(available.root).filter(n => n.tag === 'link').map(n => n.attrs.href), [
        '/resources/swrt-upgrade.css?v=2.0.0-3'
    ]);
    const restore = walk(available.root).find(n => n.tag === 'a' && n.textContent === '恢复配置备份');
    assert.equal(restore.attrs.href, '/cgi-bin/luci/admin/system/flash', 'Restore uses the native upload and restore workflow');
    assert.ok(walk(available.root).filter(n => n.tag === 'details').every(n => Object.hasOwn(n.attrs, 'open')),
        'Firmware details and release notes are expanded by default');
    assert.equal(available.calls.length, 0, 'Rendering must not download or flash');
    assert.equal(available.keep.checked, true, 'Existing configuration is preserved by default');
    assert.equal(available.source.value, 'proxy', 'Domestic accelerator is selected by default');
    assert.equal(available.button('确认升级').disabled, true);

    const switched = harness('ready');
    switched.source.value = 'github';
    await switched.source.fire('change');
    assert.deepEqual(switched.calls.find(c => c[0] === 'set_source')[1], ['github']);
    assert.equal(switched.source.value, 'github');
    assert.equal(walk(switched.root).find(n => n.textContent === '查看发布页面').href,
        'https://github.com/PEIT98/ImmortalWrt-Photonicat1-AutoBuild/releases');
    assert.equal(switched.button('确认升级').disabled, true, 'Switching source invalidates old ready image');
    assert.equal(switched.button('下载并校验').disabled, true);
    const channel = harness('ready');
    assert.equal(channel.channel.value, 'prerelease');
    channel.channel.value = 'stable';
    await channel.channel.fire('change');
    assert.equal(channel.channel.value, 'stable');
    assert.equal(channel.button('确认升级').disabled, true);
    assert.deepEqual(channel.calls.find(c => c[0] === 'set_channel')[1], ['stable']);
    const refused = harness('ready');
    refused.sourceError = '保存失败'; refused.source.value = 'github';
    await refused.source.fire('change');
    assert.equal(refused.source.value, 'proxy', 'Rejected source change restores previous selection');
    assert.equal(refused.notices[0][1].textContent, '保存失败');
    const busy = harness('downloading');
    assert.equal(busy.source.disabled, true);
    await busy.source.fire('change');
    assert.equal(busy.calls.length, 0, 'Cannot switch source during a worker task');
    available.button('下载并校验').fire('click');
    await flush();
    assert.equal(available.calls.filter(c => c[0] === 'download').length, 1);
    assert.equal(available.calls.filter(c => c[0] === 'install').length, 0);
    assert.equal(available.button('确认升级').disabled, true);

    const ready = harness('ready');
    ready.button('确认升级').fire('click');
    const confirm = walk(ready.modal).find(n => n.tag === 'button' && n.textContent === '开始刷写并重启');
    assert.equal(confirm.disabled, true, 'Confirmation requires backup acknowledgement');
    confirm.fire('click');
    assert.equal(ready.calls.length, 0);
    const acknowledgement = walk(ready.modal).find(n => n.tag === 'input');
    acknowledgement.checked = true;
    acknowledgement.fire('change');
    confirm.fire('click');
    await flush();
    const install = ready.calls.find(c => c[0] === 'install');
    assert.equal(install[1][0], 1);
    assert.equal(install[1][1], 'a'.repeat(64));

    const failed = harness('ready');
    failed.state = { ...failed.state, state: { phase: 'failed', message: 'SHA256 校验失败' } };
    await failed.polls[0]();
    assert.equal(failed.button('确认升级').disabled, true, 'A failed task must clear stale ready state');
    const stale = harness('current');
    assert.equal(stale.button('下载并校验').disabled, true);
    assert.equal(stale.button('确认升级').disabled, true);
    const offline = harness('ready');
    offline.statusOffline = true;
    await offline.polls[0]();
    assert.equal(offline.button('确认升级').disabled, true, 'An unavailable status must disable stale flash action');

    const initialFailure = harness('ready');
    initialFailure.statusOffline = true;
    const unavailable = await initialFailure.view.load();
    assert.equal(unavailable.ok, false, 'Initial RPC failure must still render a recoverable page');
    initialFailure.root = initialFailure.view.render(unavailable);
    assert.equal(initialFailure.button('确认升级').disabled, true);
    initialFailure.statusOffline = false;
    await initialFailure.polls.at(-1)();
    assert.equal(initialFailure.button('确认升级').disabled, false, 'Polling recovers after service returns');

    const restarting = harness('installing');
    restarting.statusOffline = true;
    await restarting.polls[0]();
    await restarting.polls[0]();
    assert.equal(restarting.modal.attrs.title, '等待设备重新连接');

    const lostReply = harness('ready');
    lostReply.installResponseLost = true;
    lostReply.button('确认升级').fire('click');
    const lostAck = walk(lostReply.modal).find(n => n.tag === 'input');
    lostAck.checked = true; lostAck.fire('change');
    walk(lostReply.modal).find(n => n.tag === 'button' && n.textContent === '开始刷写并重启').fire('click');
    await flush();
    await lostReply.polls[0]();
    assert.equal(lostReply.modal.attrs.title, '等待设备重新连接',
        'Losing the install response does not prove that flashing failed');
    assert.equal(lostReply.calls.filter(c => c[0] === 'install').length, 1, 'Never resend an ambiguous flash request');

    const preparing = harness('preparing');
    preparing.statusOffline = true;
    await preparing.polls[0](); await preparing.polls[0]();
    assert.equal(preparing.modal.attrs.title, '等待设备重新连接');

    const read = harness('ready', true);
    assert.equal(read.source.disabled, true);
    await read.source.fire('change');
    assert.equal(read.calls.length, 0);
    for (const text of ['检查更新', '下载并校验', '确认升级', '下载配置备份'])
        assert.equal(read.button(text).disabled, true);

    const error = harness();
    error.error = 'GitHub API 访问受限';
    error.button('检查更新').fire('click');
    await flush();
    assert.equal(error.notices[0][1].textContent, 'GitHub API 访问受限');
    assert.ok(walk(error.root).some(n => n.tag === 'pre' && n.textContent === '<script>never HTML</script>'),
        'Release notes must remain text, never HTML');
    console.log('Online upgrade UI: download/flash separation, confirmation, stale state and read-only access passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
