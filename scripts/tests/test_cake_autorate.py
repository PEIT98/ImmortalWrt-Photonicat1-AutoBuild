#!/usr/bin/env python3
"""隔离检查真实配置生成器，模拟 UCI/ubus/tc，不修改主机网络。"""
import json
import os
import re
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
PREPARE = REPO / 'packages/cake-autorate/files/cake-autorate-prepare'

MOCK = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
state = json.loads(Path(os.environ['CAKE_TEST_STATE']).read_text())
name = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['CAKE_TEST_CALLS'], 'a') as f:
    f.write(json.dumps([name, *args]) + '\n')
if name == 'uci':
    args = [arg for arg in args if arg != '-q']
    if args[0] == 'get':
        value = state['uci'].get(args[1])
        if value is None: sys.exit(1)
        print(value)
    elif args == ['show', 'sqm']:
        print('\n'.join('sqm.' + name + '=queue' for name in state['queues']))
    elif os.environ.get('CAKE_TEST_WRITABLE') == '1' and args[0] in ('set', 'delete', 'commit'):
        if args[0] == 'set':
            key, value = args[1].split('=', 1)
            state['uci'][key] = value
        elif args[0] == 'delete': state['uci'].pop(args[1], None)
        Path(os.environ['CAKE_TEST_STATE']).write_text(json.dumps(state))
    else:
        raise RuntimeError('禁止修改 UCI: ' + repr(args))
elif name == 'ubus':
    print(json.dumps(state['status']))
elif name == 'tc':
    if args[:2] == ['qdisc', 'show']:
        if args[-1] in state['cake_devices']:
            print('qdisc cake 8001: root refcnt 2 bandwidth 20Mbit')
        else:
            print('qdisc fq_codel 0: root refcnt 2')
    elif args[:3] == ['-j', 'filter', 'show']:
        print(json.dumps(state['filters']))
    else:
        raise RuntimeError('禁止修改队列: ' + repr(args))
elif name == 'jsonfilter':
    data = json.load(sys.stdin)
    expr = args[args.index('-e') + 1]
    if expr == '@.up': print(str(data['up']).lower())
    elif expr == '@.l3_device': print(data.get('l3_device', ''))
    elif expr == '@[*].options.actions[*].to_dev':
        for item in data:
            for action in item.get('options', {}).get('actions', []):
                if 'to_dev' in action: print(action['to_dev'])
    else: raise RuntimeError(expr)
elif name == 'cake-service':
    pass
'''


class CakeAutorateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        mock = self.root / 'mock'
        mock.write_text(MOCK)
        mock.chmod(0o755)
        for name in ('uci', 'ubus', 'tc', 'jsonfilter', 'cake-service'):
            (self.bin / name).symlink_to(mock)
        self.state = {
            'uci': {
                'cake-autorate.main.interface': 'auto',
                'mwan3.qmodem_priority3.interface': '6_2',
                'network.6_2': 'interface',
                'network.6_2.modem_config': 'modem2',
                'qmodem.modem2': 'modem-device',
                'mwan3.6_2.family': 'ipv4',
                'sqm.mobile.enabled': '1',
                'sqm.mobile.interface': 'wwan0_2',
                'sqm.mobile.qdisc': 'cake',
                'cake-autorate.main.min_download': '5000',
                'cake-autorate.main.base_download': '30000',
                'cake-autorate.main.max_download': '150000',
                'cake-autorate.main.min_upload': '1000',
                'cake-autorate.main.base_upload': '10000',
                'cake-autorate.main.max_upload': '40000',
                'cake-autorate.main.reflector': '223.5.5.5 119.29.29.29 1.1.1.1',
            },
            'status': {'up': True, 'l3_device': 'wwan0_2'},
            'queues': ['mobile'],
            'cake_devices': ['wwan0_2', 'ifb-real2'],
            'filters': [{'options': {'actions': [{'kind': 'mirred', 'to_dev': 'ifb-real2'}]}}],
        }

    def run_prepare(self, mode='check'):
        state = self.root / 'state.json'
        state.write_text(json.dumps(self.state))
        env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                   CAKE_TEST_STATE=str(state), CAKE_TEST_CALLS=str(self.root / 'calls'),
                   CAKE_AUTORATE_CONFIG_DIR=str(self.root / 'runtime'))
        return subprocess.run(['sh', str(PREPARE), mode], env=env, capture_output=True, text=True, timeout=15)

    def rejected(self, message):
        result = self.run_prepare('config')
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(message, result.stderr)
        self.assertFalse((self.root / 'runtime/config.primary.sh').exists())

    def test_check_uses_actual_devices_without_writing(self):
        result = self.run_prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('6_2', result.stdout)
        self.assertIn('ifb-real2', result.stdout)
        self.assertFalse((self.root / 'runtime').exists())

    def test_generate_binds_probes_to_selected_mwan_interface(self):
        result = self.run_prepare('config')
        self.assertEqual(result.returncode, 0, result.stderr)
        config = Path(result.stdout.strip())
        self.assertEqual(config.stat().st_mode & 0o777, 0o600)
        self.assertEqual(subprocess.run(['bash', '-n', str(config)]).returncode, 0)
        text = config.read_text()
        self.assertIn('dl_if="ifb-real2"', text)
        self.assertIn('ul_if="wwan0_2"', text)
        self.assertIn('mwan3 use 6_2 exec', text)
        self.assertIn('-4 -I wwan0_2', text)
        self.assertIn('log_to_file=0', text)

    def test_missing_modem_interface(self):
        del self.state['uci']['mwan3.qmodem_priority3.interface']
        self.rejected('尚未发现')

    def test_auto_selection_rejects_non_modem(self):
        self.state['uci']['qmodem.modem2'] = 'other'
        self.rejected('不是有效的 QModem')

    def test_disconnected_link(self):
        self.state['status']['up'] = False
        self.rejected('未连接')

    def test_not_in_mwan_ipv4(self):
        self.state['uci']['mwan3.6_2.family'] = 'ipv6'
        self.rejected('IPv4')

    def test_offloading_must_be_disabled(self):
        self.state['uci']['firewall.@defaults[0].flow_offloading_hw'] = '1'
        self.rejected('流量分载')

    def test_missing_sqm_queue(self):
        self.state['queues'] = []
        self.rejected('唯一的 CAKE')

    def test_duplicate_sqm_queues(self):
        self.state['queues'].append('duplicate')
        self.state['uci'].update({'sqm.duplicate.enabled': '1', 'sqm.duplicate.interface': 'wwan0_2', 'sqm.duplicate.qdisc': 'cake'})
        self.rejected('唯一的 CAKE')

    def test_non_cake_sqm(self):
        self.state['uci']['sqm.mobile.qdisc'] = 'fq_codel'
        self.rejected('未使用 CAKE')

    def test_non_cake_upload(self):
        self.state['cake_devices'].remove('wwan0_2')
        self.rejected('上传 CAKE')

    def test_non_cake_download(self):
        self.state['cake_devices'].remove('ifb-real2')
        self.rejected('下载 CAKE')

    def test_missing_download_redirect(self):
        self.state['filters'] = []
        self.rejected('唯一的下载 IFB')

    def test_ambiguous_download_redirect(self):
        self.state['filters'][0]['options']['actions'].append({'to_dev': 'ifb-other'})
        self.rejected('唯一的下载 IFB')

    def test_unconfigured_rates(self):
        self.state['uci']['cake-autorate.main.base_download'] = '0'
        self.rejected('实测速率')

    def test_invalid_rate_order(self):
        self.state['uci']['cake-autorate.main.min_download'] = '300000'
        self.rejected('最低 <= 基准 <= 最高')

    def test_shell_text_in_rates_is_rejected(self):
        self.state['uci']['cake-autorate.main.base_download'] = '$(touch bad)'
        self.rejected('正整数')

    def test_octal_like_rates_are_rejected(self):
        self.state['uci']['cake-autorate.main.base_download'] = '080000'
        self.rejected('正整数')

    def test_invalid_reflector_is_rejected(self):
        self.state['uci']['cake-autorate.main.reflector'] = '223.5.5.5 999.1.1.1'
        self.rejected('IPv4 地址')

    def test_device_change_requires_corresponding_sqm(self):
        self.state['status']['l3_device'] = 'wwan1'
        self.rejected('唯一的 CAKE')

    def run_integration_script(self, name, *, writable=False, custom_statistics=False, custom_sqm=False):
        state = self.root / 'state.json'
        state.write_text(json.dumps(self.state))
        (self.root / 'etc/config').mkdir(parents=True, exist_ok=True)
        (self.root / 'rom/etc/config').mkdir(parents=True, exist_ok=True)
        for rel in ('etc/config/travelmate', 'etc/config/luci_statistics', 'rom/etc/config/luci_statistics', 'etc/config/sqm', 'rom/etc/config/sqm'):
            (self.root / rel).write_text('config statistics collectd\n')
        if custom_statistics:
            (self.root / 'etc/config/luci_statistics').write_text('# user configuration\n')
        if custom_sqm:
            (self.root / 'etc/config/sqm').write_text('# user sqm\n')
        source = REPO / ('files/etc/uci-defaults/92-photonicat-network-tools' if name == 'defaults' else 'packages/cake-autorate/files/98-cake-autorate')
        text = source.read_text()
        replacements = {'/rom/': str(self.root / 'rom') + '/',
                        '/etc/config/': str(self.root / 'etc/config') + '/',
                        '/etc/init.d/cake-autorate': str(self.bin / 'cake-service'),
                        '/var/run/photonicat-cake-autorate/': str(self.root / 'runtime') + '/'}
        text = re.sub('|'.join(map(re.escape, replacements)), lambda match: replacements[match.group()], text)
        script = self.root / 'integration.sh'
        script.write_text(text)
        env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                   CAKE_TEST_STATE=str(state), CAKE_TEST_CALLS=str(self.root / 'calls'),
                   CAKE_TEST_WRITABLE='1' if writable else '0', ACTION='ifup', INTERFACE='6_2')
        result = subprocess.run(['sh', str(script)], env=env, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.state = json.loads(state.read_text())
        return [json.loads(line) for line in (self.root / 'calls').read_text().splitlines()]

    def test_first_boot_binds_wwan_and_keeps_travelmate_off(self):
        self.run_integration_script('defaults', writable=True)
        values = self.state['uci']
        self.assertEqual(values['network.wwan.proto'], 'dhcp')
        self.assertEqual(values['travelmate.global.trm_iface'], 'wwan')
        self.assertEqual(values['travelmate.global.trm_enabled'], '0')
        self.assertEqual(values['luci_statistics.collectd_rrdtool.DataDir'], '/tmp/rrd')
        self.assertEqual(values['luci_statistics.collectd_ping.Interval'], '60')
        self.assertEqual(values['sqm.mobile.enabled'], '0')

    def test_existing_wwan_is_not_reconfigured(self):
        self.state['uci'].update({'network.wwan': 'interface', 'network.wwan.proto': 'static', 'network.wwan.metric': '55'})
        self.run_integration_script('defaults', writable=True)
        self.assertEqual(self.state['uci']['network.wwan.proto'], 'static')
        self.assertEqual(self.state['uci']['network.wwan.metric'], '55')

    def test_existing_travelmate_and_statistics_are_preserved(self):
        self.state['uci'].update({'travelmate.global.trm_iface': 'my_wifi', 'travelmate.global.trm_enabled': '1', 'luci_statistics.collectd.Interval': '15'})
        self.run_integration_script('defaults', writable=True, custom_statistics=True)
        self.assertEqual(self.state['uci']['travelmate.global.trm_iface'], 'my_wifi')
        self.assertEqual(self.state['uci']['travelmate.global.trm_enabled'], '1')
        self.assertEqual(self.state['uci']['luci_statistics.collectd.Interval'], '15')

    def test_first_boot_respects_enabled_autorate(self):
        self.state['uci']['cake-autorate.main.enabled'] = '1'
        calls = self.run_integration_script('defaults', writable=True)
        self.assertFalse(any(call[0] == 'cake-service' for call in calls))

    def test_first_boot_preserves_custom_sqm(self):
        self.run_integration_script('defaults', writable=True, custom_sqm=True)
        self.assertEqual(self.state['uci']['sqm.mobile.enabled'], '1')

    def test_default_hotplug_does_not_start_autorate(self):
        self.state['uci']['cake-autorate.main.enabled'] = '0'
        calls = self.run_integration_script('hotplug')
        self.assertFalse(any(call[0] == 'cake-service' for call in calls))

    def test_hotplug_restarts_for_actual_modem(self):
        self.state['uci']['cake-autorate.main.enabled'] = '1'
        calls = self.run_integration_script('hotplug')
        self.assertIn(['cake-service', 'restart'], calls)

    def test_hotplug_ignores_unrelated_interface(self):
        self.state['uci'].update({'cake-autorate.main.enabled': '1', 'mwan3.qmodem_priority3.interface': 'other'})
        del self.state['uci']['network.6_2.modem_config']
        calls = self.run_integration_script('hotplug')
        self.assertFalse(any(call[0] == 'cake-service' for call in calls))


if __name__ == '__main__':
    unittest.main()
