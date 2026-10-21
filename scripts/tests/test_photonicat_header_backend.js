// Run the real read-only RPC parser against the shape returned by QModem.
// The router-only ubus and jshn functions are mocked; no AT port is touched.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const root = path.resolve(__dirname, '../..');
const source = fs.readFileSync(path.join(root,
	'packages/luci-app-photonicat-power/root/usr/libexec/rpcd/luci.photonicat_header'), 'utf8');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'photonicat-qmodem-'));

try {
	const jshn = `
json_load() {
    JSON_RAW="$1"
    JSON_PATH=''
    printf '%s' "$JSON_RAW" | jq -e . >/dev/null 2>&1
}
json_select() {
    if [ "$1" = .. ]; then JSON_PATH="\${JSON_PATH%/*}"; return 0; fi
    next="$JSON_PATH/$1"
    printf '%s' "$JSON_RAW" | jq -e --arg p "$next" \
        'getpath(($p|split("/")|map(select(length>0))|map(if test("^[0-9]+$") then tonumber else . end))) != null' \
        >/dev/null 2>&1 || return 1
    JSON_PATH="$next"
}
json_get_keys() {
    keys="$(printf '%s' "$JSON_RAW" | jq -r --arg p "$JSON_PATH" \
        'getpath(($p|split("/")|map(select(length>0))|map(if test("^[0-9]+$") then tonumber else . end)))|keys_unsorted|.[]' \
        | tr '\\n' ' ')"
    eval "$1=\\$keys"
}
json_get_var() {
    JSHN_RESULT="$(printf '%s' "$JSON_RAW" | jq -r --arg p "$JSON_PATH/$2" \
        'getpath(($p|split("/")|map(select(length>0))|map(if test("^[0-9]+$") then tonumber else . end))) // empty')"
    eval "$1=\\$JSHN_RESULT"
}
`;
	fs.writeFileSync(path.join(temp, 'jshn.sh'), jshn);
	fs.writeFileSync(path.join(temp, 'config.sh'),
		'config_load() { :; }\nconfig_foreach() { "$1" modem1; }\nconfig_get() { eval "$1=1"; }\n');
	fs.writeFileSync(path.join(temp, 'qmodem.config'), 'config modem-device modem1\n');
	const ubus = `#!/bin/sh
case "$*" in
    *'list qmodem'*) exit 0 ;;
    *'get_connect_status'*) cat "$QMODEM_TEST_CONNECT" ;;
    *'cell_info'*) cat "$QMODEM_TEST_CELL" ;;
    *'network_info'*) cat "$QMODEM_TEST_NETWORK" ;;
    *) exit 1 ;;
esac
`;
	fs.writeFileSync(path.join(temp, 'ubus'), ubus, { mode: 0o755 });
	const instrumented = source
		.replace('. /usr/share/libubox/jshn.sh', '. "$QMODEM_TEST_JSHN"')
		.replace('. /lib/functions.sh', '. "$QMODEM_TEST_FUNCTIONS"')
		.replace('[ -f /etc/config/qmodem ]', '[ -f "$QMODEM_TEST_CONFIG" ]')
		.replace('# The PMU status method already contains both auto-start and schedule state.',
			'printf "%s|%s|%s|%s\\n" "$connection" "$generation" "$bars" "$rsrp"; exit 0');
	fs.writeFileSync(path.join(temp, 'header'), instrumented);

	function run(connect, cell, network) {
		fs.writeFileSync(path.join(temp, 'connect.json'), connect);
		fs.writeFileSync(path.join(temp, 'cell.json'), JSON.stringify(cell));
		fs.writeFileSync(path.join(temp, 'network.json'), JSON.stringify(network));
		return execFileSync('sh', [path.join(temp, 'header'), 'call', 'status'], {
			encoding: 'utf8', timeout: 10000,
			env: { ...process.env, PATH: temp + path.delimiter + process.env.PATH,
				QMODEM_TEST_JSHN: path.join(temp, 'jshn.sh'),
				QMODEM_TEST_FUNCTIONS: path.join(temp, 'config.sh'),
				QMODEM_TEST_CONFIG: path.join(temp, 'qmodem.config'),
				QMODEM_TEST_CONNECT: path.join(temp, 'connect.json'),
				QMODEM_TEST_CELL: path.join(temp, 'cell.json'),
				QMODEM_TEST_NETWORK: path.join(temp, 'network.json') }
		}).trimEnd();
	}
	const cell = (mode, rsrp, rat) => ({ result: {}, modem_info: [
		{ key: 'network_mode', value: mode, class: 'Cell Information' },
		{ key: 'RSRP', value: rsrp, extra_info: rat, type: 'progress_bar',
			min_value: '-140', max_value: '-44', unit: 'dBm' }
	] });
	const network = { modem_info: [ { key: 'Network Type', value: 'LTE' } ] };
	assert.equal(run('{"connection_status":"Yes"}', cell('NR5G-SA Mode', '-75', 'NR5G-SA'), network),
		'yes|5G|4|-75', 'connected 5G uses the NR RSRP shown by QModem');
	assert.equal(run('{"connection_status":"Yes"}', cell('LTE Mode', '-92', 'LTE'), network),
		'yes|4G|2|-92', 'connected LTE uses the same quality boundaries as QModem');
	assert.equal(run('{"connection_status":"No"}', cell('NR5G-SA Mode', '-75', 'NR5G-SA'), network),
		'no||0|', 'a modem without a data session displays no service');
	assert.equal(run('invalid', cell('NR5G-SA Mode', '-75', 'NR5G-SA'), network),
		'unknown||0|', 'a failed connection query is not mislabeled no service');
	assert.equal(run('{"connection_status":"Yes"}', {}, network),
		'yes|4G|0|', 'current network type is used if cell info is temporarily missing');
	console.log('Photonicat QModem RPC: connection, current RAT and RSRP passed');
} finally {
	fs.rmSync(temp, { recursive: true, force: true });
}
