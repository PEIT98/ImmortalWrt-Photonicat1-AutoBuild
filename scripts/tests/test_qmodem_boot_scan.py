#!/usr/bin/env python3
"""执行真实启动检查脚本，模拟晚到端口、异步识别和扫描服务失效。"""

import fcntl
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "files/usr/bin/photonicat-qmodem-scan"
DEFAULTS = ROOT / "files/etc/uci-defaults/zz-photonicat-qmodem-usb-scan"
SHELL = os.environ.get("TEST_SH", "sh").split()

# 只替换设备树及外部服务；判断就绪、重试、恢复和退出的是仓库里的真实 shell。
STUB = r'''#!/usr/bin/env python3
import json, os, sys, time
from pathlib import Path
root = Path(os.environ["GUARD_TEST_ROOT"])
state_path = root / "state.json"
state = json.loads(state_path.read_text())
name = Path(sys.argv[0]).name
args = sys.argv[1:]
def save():
    state_path.write_text(json.dumps(state))
def event(kind, value):
    with (root / "events.jsonl").open("a") as f:
        f.write(json.dumps([kind, state.get("tick", 0), value]) + "\n")
if name == "uci":
    args = [x for x in args if x != "-q"]
    op = args[0]
    if op == "show":
        if state.get("hang_uci"):
            time.sleep(60)
        state["tick"] = state.get("tick", 0) + 1
        if state.get("tty_after") == state["tick"]:
            (root / "dev/ttyUSB2").symlink_to("/dev/null")
        if state.get("requests") and state.get("complete_after", 999) <= state["tick"]:
            state["configured"] = True
        save()
        print("qmodem.main=main")
        print("qmodem.main.enable_usb_scan='%s'" % state.get("enabled", "1"))
        print("qmodem.main.block_auto_probe='%s'" % state.get("blocked", "0"))
        if state.get("configured") or state.get("fixed") or state.get("wrong_at"):
            print((root / "device.conf").read_text())
        if state.get("active_other"):
            print("qmodem.custom=modem-device\nqmodem.custom.state='enabled'\nqmodem.custom.network='wan_modem'")
    elif op == "get":
        value = state.get("values", {}).get(args[1])
        if value is None:
            sys.exit(1)
        print(value)
    elif op == "set":
        key, value = args[1].split("=", 1)
        state.setdefault("values", {})[key] = value
        event("set", args[1])
        save()
    elif op == "commit":
        event("commit", args[1])
    else:
        raise RuntimeError(args)
elif name == "modem_scanc":
    if args == ["status"]:
        busy = state.get("busy_until", 0) >= state.get("tick", 0)
        busy |= state.get("mode") == "queued" and state.get("requests", 0) > 0 and not state.get("configured")
        print(json.dumps({"queue": 0, "active": int(busy), "workers": 4}))
        sys.exit(0)
    event("scan", args)
    state["requests"] = state.get("requests", 0) + 1
    if state.get("mode") == "immediate":
        state["configured"] = True
    save()
    print('{"code":0,"message":"deduplicated"}' if state["requests"] > 1 else '{"code":0,"message":"queued"}')
elif name == "qmodem_init":
    event("init", args)
    if state.get("mode") == "recover":
        state["configured"] = True
    save()
elif name == "guard_init":
    event("enable", args)
elif name == "logger":
    event("log", args)
elif name == "jq":
    # 测试环境只需判断 scanner status 的这两个字段；固件使用真正的 jq。
    status = json.loads(sys.stdin.read())
    sys.exit(0 if status.get("queue") == 0 and status.get("active") == 0 else 1)
else:
    raise RuntimeError(name)
'''


class BootScanTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for directory in ("bin", "dev", "run", "sys/class/net", "sys/class/tty"):
            (self.root / directory).mkdir(parents=True, exist_ok=True)
        for command in ("uci", "modem_scanc", "qmodem_init", "guard_init", "logger", "jq"):
            path = self.root / "bin" / command
            path.write_text(STUB)
            path.chmod(0o755)
        self.state = {}
        self.env = dict(os.environ, PATH=f"{self.root / 'bin'}:{os.environ['PATH']}")
        self.env.update({
            "GUARD_TEST_ROOT": str(self.root),
            "PHOTONICAT_QMODEM_SYSFS": str(self.root / "sys"),
            "PHOTONICAT_QMODEM_DEVFS": str(self.root / "dev"),
            "PHOTONICAT_QMODEM_RUNDIR": str(self.root / "run"),
            "PHOTONICAT_QMODEM_SCANC": str(self.root / "bin/modem_scanc"),
            "PHOTONICAT_QMODEM_INIT": str(self.root / "bin/qmodem_init"),
            "PHOTONICAT_QMODEM_GUARD_INIT": str(self.root / "bin/guard_init"),
            "PHOTONICAT_QMODEM_INTERVAL": "0",
            "PHOTONICAT_QMODEM_ROUNDS": "8",
            "PHOTONICAT_QMODEM_RECOVERY_ROUND": "4",
        })

    def hardware(self, slot="6-2", net="enx_dynamic", tty=True, fixed=False, wrong_at=False):
        device = self.root / f"sys/devices/usb6/{slot}"
        serial = device / f"{slot}:1.2"
        network = device / f"{slot}:1.4"
        serial.mkdir(parents=True)
        network.mkdir()
        (device / "idVendor").write_text("2cb7\n")
        (device / "idProduct").write_text("0105\n")
        driver = self.root / "sys/bus/usb/drivers/cdc_ether"
        driver.mkdir(parents=True)
        (network / "driver").symlink_to(driver)
        net_class = self.root / "sys/class/net" / net
        net_class.mkdir()
        (net_class / "device").symlink_to(network)
        tty_class = self.root / "sys/class/tty/ttyUSB2"
        tty_class.mkdir()
        (tty_class / "device").symlink_to(serial)
        if tty:
            (self.root / "dev/ttyUSB2").symlink_to("/dev/null")
        at = "/dev/ttyUSB9" if wrong_at else "/dev/ttyUSB2"
        config = (
            "qmodem.custom_alias=modem-device\n"
            f"qmodem.custom_alias.path='{device}/'\n"
            "qmodem.custom_alias.data_interface='usb'\n"
            "qmodem.custom_alias.state='enabled'\n"
            "qmodem.custom_alias.name='fm160-eau'\n"
            f"qmodem.custom_alias.network='{net}'\n"
            f"qmodem.custom_alias.at_port='{at}'\n"
        )
        if fixed:
            config += "qmodem.custom_alias.fixed_device='1'\n"
            self.state["fixed"] = True
        if wrong_at:
            self.state["wrong_at"] = True
        (self.root / "device.conf").write_text(config)

    def run_script(self, script=HELPER, timeout=20):
        (self.root / "state.json").write_text(json.dumps(self.state))
        result = subprocess.run([*SHELL, str(script)], env=self.env,
                                capture_output=True, text=True, timeout=timeout)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.state = json.loads((self.root / "state.json").read_text())
        events = self.root / "events.jsonl"
        return [json.loads(line) for line in events.read_text().splitlines()] if events.exists() else []

    def test_waits_for_late_tty_then_scans_actual_slot(self):
        self.hardware(tty=False)
        self.state.update(tty_after=3, mode="immediate")
        events = self.run_script()
        scans = [e for e in events if e[0] == "scan"]
        self.assertEqual(scans, [["scan", 3, ["add", "6-2", "usb"]]])
        self.assertTrue(self.state["configured"])
        self.assertFalse(any(e[0] == "init" for e in events))

    def test_asynchronous_deduplicated_task_gets_time_to_finish(self):
        self.hardware()
        self.state.update(mode="queued", complete_after=6)
        self.env["PHOTONICAT_QMODEM_RECOVERY_ROUND"] = "7"
        events = self.run_script()
        self.assertEqual(len([e for e in events if e[0] == "scan"]), 1)
        self.assertTrue(self.state["configured"])
        self.assertFalse(any(e[0] == "init" for e in events))

    def test_existing_busy_scan_is_not_requeued(self):
        self.hardware()
        self.state.update(mode="immediate", busy_until=3)
        self.env["PHOTONICAT_QMODEM_RECOVERY_ROUND"] = "7"
        events = self.run_script()
        scans = [e for e in events if e[0] == "scan"]
        self.assertEqual(scans, [["scan", 4, ["add", "6-2", "usb"]]])
        self.assertFalse(any(e[0] == "init" for e in events))

    def test_stalled_scanner_is_recovered_once(self):
        self.hardware()
        self.state["mode"] = "recover"
        events = self.run_script()
        self.assertEqual([e[2] for e in events if e[0] == "init"], [["restart"]])
        self.assertTrue(self.state["configured"])

    def test_scan_completing_at_recovery_boundary_is_not_restarted(self):
        self.hardware()
        self.state.update(mode="queued", complete_after=5)
        events = self.run_script()
        self.assertTrue(self.state["configured"])
        self.assertFalse(any(e[0] == "init" for e in events))

    def test_failed_recovery_is_not_repeated(self):
        self.hardware()
        events = self.run_script()
        self.assertEqual(len([e for e in events if e[0] == "init"]), 1)
        self.assertLessEqual(self.state["tick"], 9)

    def test_known_modem_with_custom_alias_is_left_alone(self):
        self.hardware()
        self.state["configured"] = True
        events = self.run_script()
        self.assertFalse(any(e[0] in ("scan", "init") for e in events))

    def test_fixed_device_is_left_alone(self):
        self.hardware(fixed=True)
        events = self.run_script()
        self.assertFalse(any(e[0] in ("scan", "init") for e in events))

    def test_existing_other_modem_prevents_recovery(self):
        self.hardware()
        (self.root / "sys/class/net/wan_modem").mkdir()
        self.state["active_other"] = True
        events = self.run_script()
        self.assertTrue(any(e[0] == "scan" for e in events))
        self.assertFalse(any(e[0] == "init" for e in events))

    def test_no_modem_does_not_restart_service(self):
        events = self.run_script()
        self.assertFalse(any(e[0] in ("scan", "init") for e in events))

    def test_missing_or_wrong_at_port_is_not_counted_as_recognized(self):
        self.hardware(wrong_at=True)
        events = self.run_script()
        self.assertTrue(any(e[0] == "scan" for e in events))
        self.assertFalse(any(e[0] == "init" for e in events))

    def test_disabled_scanning_is_respected(self):
        for key, value in (("enabled", "0"), ("blocked", "1")):
            with self.subTest(key=key):
                self.state = {key: value}
                events = self.run_script()
                self.assertFalse(any(e[0] in ("scan", "init") for e in events))

    def test_second_guard_cannot_run_concurrently(self):
        self.hardware()
        with (self.root / "run/photonicat-qmodem-scan.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            events = self.run_script()
        self.assertFalse(any(e[0] in ("scan", "init") for e in events))

    def test_hung_uci_is_bounded_without_timeout_command(self):
        self.state["hang_uci"] = True
        self.env["PHOTONICAT_QMODEM_ROUNDS"] = "1"
        events = self.run_script(timeout=12)
        self.assertFalse(any(e[0] in ("scan", "init") for e in events))

    def test_upgrade_enables_guard_without_resetting_user_settings(self):
        values = {
            "qmodem.main": "main",
            "qmodem.main.photonicat_usb_scan_defaults": "1",
            "qmodem.main.enable_usb_scan": "0",
            "qmodem.main.enable_pcie_scan": "1",
            "qmodem.main.start_delay": "30",
        }
        self.state["values"] = dict(values)
        events = self.run_script(DEFAULTS)
        for key, value in values.items():
            self.assertEqual(self.state["values"][key], value)
        self.assertEqual(len([e for e in events if e[0] == "enable"]), 1)
        self.run_script(DEFAULTS)
        self.assertEqual(len([e for e in self.events() if e[0] == "enable"]), 1)

    def events(self):
        return [json.loads(x) for x in (self.root / "events.jsonl").read_text().splitlines()]

    def test_fresh_image_defaults_to_usb_only(self):
        self.state["values"] = {"qmodem.main": "main"}
        self.run_script(DEFAULTS)
        values = self.state["values"]
        self.assertEqual(values["qmodem.main.enable_usb_scan"], "1")
        self.assertEqual(values["qmodem.main.enable_pcie_scan"], "0")
        self.assertEqual(values["qmodem.main.try_preset_pcie"], "0")


class BootSwitchTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location(
            "boot_patch", ROOT / "scripts/patches/fix-qmodem-boot-scan.py")
        cls.patch = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.patch)

    def run_boot(self, usb, pcie, delay="15"):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            uci = root / "uci"
            uci.write_text('''#!/bin/sh
case "$3" in
qmodem.main.start_delay) echo "$SCAN_DELAY" ;;
qmodem.main.enable_usb_scan) echo "$USB_SCAN" ;;
qmodem.main.enable_pcie_scan) echo "$PCIE_SCAN" ;;
*) exit 1 ;;
esac
''')
            uci.chmod(0o755)
            client = root / "scan"
            client.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$SCAN_EVENTS"\n')
            client.chmod(0o755)
            source = self.patch.patch_source(self.patch.ORIGINAL)
            # 仅替换外部服务路径；执行补丁生成的真实 boot 分支。
            source = source.replace("/usr/share/qmodem/modem_scan.sh", '"$SCAN_CLIENT"')
            source += '\nlogger() { :; }\nsleep() { :; }\nstart() { echo started; }\nboot\nwait\n'
            script = root / "boot.sh"
            script.write_text(source)
            events = root / "events"
            env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}",
                       SCAN_DELAY=delay, USB_SCAN=usb, PCIE_SCAN=pcie,
                       SCAN_CLIENT=str(client), SCAN_EVENTS=str(events))
            result = subprocess.run([*SHELL, str(script)], env=env,
                                    text=True, capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "started")
            return events.read_text().splitlines() if events.exists() else []

    def test_boot_respects_all_scan_switch_combinations(self):
        for usb, pcie, expected in (("1", "0", ["scan usb"]),
                                    ("0", "1", ["scan pcie"]),
                                    ("1", "1", ["scan all"]),
                                    ("0", "0", [])):
            with self.subTest(usb=usb, pcie=pcie):
                self.assertEqual(self.run_boot(usb, pcie), expected)

    def test_zero_delay_keeps_service_start_without_extra_scan(self):
        self.assertEqual(self.run_boot("1", "1", "0"), [])

    def test_patch_is_idempotent_and_keeps_other_functions(self):
        source = '#!/bin/sh\n' + self.patch.ORIGINAL + '\nother() { echo unchanged; }\n'
        patched = self.patch.patch_source(source)
        self.assertEqual(self.patch.patch_source(patched), patched)
        self.assertTrue(patched.endswith('\nother() { echo unchanged; }\n'))

    def test_unrecognized_upstream_layout_is_rejected(self):
        with self.assertRaises(ValueError):
            self.patch.patch_source('boot() { changed_upstream; }')


if __name__ == "__main__":
    if not shutil.which("flock"):
        raise SystemExit("测试需要 flock，与固件现有依赖相同")
    unittest.main()
