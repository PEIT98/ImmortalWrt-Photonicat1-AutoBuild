/* 用模拟 LuCI 环境检查真实前端，不连接路由器或执行升级。 */
'use strict';
const assert = require('assert');
const fsNative = require('fs');
const vm = require('vm');

const nodes = new Map();
const timers = new Map();
const requests = [];
let timerId = 0;
let status = 'checking';
function E(tag, attrs, children) {
    attrs = attrs || {};
    const element = {tag, attrs, children, value: attrs.value || '', style: {}, disabled: false, textContent: '', appendChild(child) { this.child = child; }};
    if (typeof attrs.style === 'string') {
        attrs.style.split(';').forEach(entry => { const p = entry.split(':'); if (p.length > 1) element.style[p[0].trim()] = p.slice(1).join(':'); });
    }
    if (attrs.id) nodes.set(attrs.id, element);
    return element;
}
const document = {getElementById: id => nodes.get(id), body: {appendChild() {}}};
const config = {repo: 'PEIT98/ImmortalWrt-Photonicat1-AutoBuild', tag: 'auto', proxy: 'https://proxy.example/', firmware_pattern: 'photonicat'};
const context = {
    E, document,
    view: {extend: value => value},
    fs: {exec(path, args) {
        requests.push({path, args});
        return Promise.resolve({code: 0, stderr: '', stdout: path === '/bin/cat' ? status : ''});
    }},
    uci: {load: () => Promise.resolve(), get: (pkg, section, option) => config[option]},
    ui: {addNotification() {}},
    L: {url: path => '/cgi-bin/luci/' + path},
    window: {addEventListener() {}, location: {reload() {}}},
    confirm: () => true,
    setTimeout: () => 0,
    setInterval(fn) { const id = ++timerId; timers.set(id, fn); return id; },
    clearInterval(id) { timers.delete(id); },
};
vm.createContext(context);
const source = fsNative.readFileSync(process.argv[2], 'utf8');
const page = vm.runInContext('(function() {\n' + source + '\n})()', context);
const drain = () => new Promise(resolve => setImmediate(resolve));
async function tick() {
    [...timers.values()].forEach(fn => fn());
    await drain();
}

(async () => {
    await page.load();
    page.render();
    assert.equal(nodes.get('cfg-repo').value, config.repo);
    assert.equal(nodes.get('cfg-tag').value, 'auto');
    assert.equal(nodes.get('cfg-proxy').value, config.proxy);
    assert.equal(nodes.has('btn-manual-restore'), false);
    assert.equal(nodes.has('manual-backup-file'), false);

    nodes.get('btn-upgrade').attrs.click();
    await drain();
    assert(requests.some(r => r.path === '/usr/bin/online-upgrade.sh' && r.args[0] === 'background'));
    for (let i = 0; i < 8; i++) await tick();
    assert.equal(nodes.has('reboot-overlay'), false, '等待期间不得按计时伪报重启或升级完成');
    assert.equal(nodes.get('progress-bar').style.width, '5%');

    status = 'failed:文件校验未通过';
    await tick();
    assert.equal(timers.size, 0);
    assert.equal(nodes.has('reboot-overlay'), false);
    assert.equal(nodes.get('btn-check').disabled, false);
    assert(nodes.get('upgrade-result').textContent.includes('文件校验未通过'));

    status = 'checking';
    nodes.get('btn-force').attrs.click();
    await drain();
    assert(requests.some(r => r.path === '/usr/bin/online-upgrade.sh' && r.args[0] === 'background-force'));
    status = 'sysupgrade';
    await tick();
    assert.equal(nodes.has('reboot-overlay'), true, '只有后端进入系统升级阶段才显示等待重启');
    assert.equal(nodes.get('progress-bar').style.width, '95%');
    assert(!source.includes('固件刷写完成'));
    assert(!source.includes('/cgi-bin/online-upgrade-restore'));

    process.stdout.write('在线升级前端：配置显示、真实进度、失败处理、后台模式和恢复入口检查通过。\n');
})().catch(error => { console.error(error); process.exitCode = 1; });
