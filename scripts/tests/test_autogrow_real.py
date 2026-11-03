"""Run the production preinit helper on disposable sparse disks, never a real eMMC."""
import json
import os
from pathlib import Path
import shutil
import stat
import struct
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ('losetup', 'sfdisk', 'partx', 'blockdev', 'mkfs.f2fs', 'resize.f2fs',
         'mkfs.ext4', 'resize2fs', 'mksquashfs', 'jq', 'hexdump')
AVAILABLE = os.name != 'nt' and os.geteuid() == 0 and all(shutil.which(p) for p in TOOLS)
if os.environ.get('SWRT_REQUIRE_AUTOGROW_TESTS') == '1' and not AVAILABLE:
    raise RuntimeError('Required auto-expansion integration tests cannot run')


@unittest.skipUnless(AVAILABLE, 'Requires root and Linux loop/filesystem tools')
class RealAutoGrowTests(unittest.TestCase):
    def run_cmd(self, *args, **kwargs):
        result = subprocess.run(args, capture_output=True, text=True, **kwargs)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout.strip()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='swrt-autogrow-test-')
        self.base = Path(self.temp.name)
        self.loops = []
        self.mounts = []
        self.disk_handle = None
        self.data_offset = 0
        self.root_mount = self.base / 'root-mount'
        self.root_mount.mkdir()

    def tearDown(self):
        for mount in reversed(self.mounts):
            subprocess.run(['umount', str(mount)], capture_output=True)
        if self.disk_handle:
            self.disk_handle.close()
        for loop in reversed(self.loops):
            subprocess.run(['losetup', '-d', loop], capture_output=True)
        time.sleep(.1)
        self.temp.cleanup()

    def attach(self, source, offset=None, partitions=False):
        args = ['losetup', '--find', '--show']
        if partitions:
            args.append('--partscan')
        if offset is not None:
            args += ['--offset', str(offset)]
        dev = self.run_cmd(*args, str(source))
        self.loops.append(dev)
        return dev

    def mount(self, source, target, kind, readonly=False):
        self.run_cmd('mount', '-t', kind, '-o', 'ro' if readonly else 'rw', source, str(target))
        self.mounts.append(target)

    def unmount(self, target):
        self.run_cmd('umount', str(target))
        self.mounts.remove(target)

    def create(self, gib, kind, extra=False, disk_bytes=None):
        disk_bytes = disk_bytes if disk_bytes is not None else gib * 1024**3
        image = self.base / 'disk.img'
        with image.open('wb') as output:
            output.truncate(disk_bytes)
        disk_loop = self.attach(image, partitions=True)
        private_dev = self.base / 'dev'
        private_dev.mkdir()
        self.disk = str(private_dev / 'mmcblk0')
        os.mknod(self.disk, stat.S_IFBLK | 0o600, os.stat(disk_loop).st_rdev)
        # Unlike a physical eMMC, a loop-backed disk can be auto-detached by
        # the mount utilities when its last reference is closed.
        self.disk_handle = open(self.disk, 'rb', buffering=0)
        layout = ('label: dos\nlabel-id: 0x5452574f\nunit: sectors\n\n'
                  'start=65536,size=32768,type=83,bootable\n'
                  'start=131072,size=2097152,type=83\n')
        if extra:
            layout += 'start=8388608,size=1048576,type=83\n'
        self.run_cmd('sfdisk', '--wipe', 'never', self.disk, input=layout)
        self.run_cmd('partx', '-u', self.disk)
        self.part = self.disk + 'p2'
        for _ in range(100):
            node_info = Path('/sys/class/block') / (Path(disk_loop).name + 'p2') / 'dev'
            if node_info.exists():
                break
            time.sleep(.02)
        self.assertTrue(node_info.exists(), 'Kernel partition did not appear')
        # Keep private block nodes: mdev/udev may asynchronously remove a
        # reused /dev/loopNp2 pathname between successive test cases.
        major, minor = map(int, node_info.read_text().strip().split(':'))
        os.mknod(self.part, stat.S_IFBLK | 0o600, os.makedev(major, minor))
        if extra:
            node_info3 = Path('/sys/class/block') / (Path(disk_loop).name + 'p3') / 'dev'
            major, minor = map(int, node_info3.read_text().strip().split(':'))
            os.mknod(self.disk + 'p3', stat.S_IFBLK | 0o600, os.makedev(major, minor))
        self.before = json.loads(self.run_cmd('sfdisk', '--json', self.disk))['partitiontable']
        # Nonzero boot-code and RK loader sentinels must survive sfdisk -N2.
        self.loader = b'RK-LOADER-MUST-SURVIVE' * 100
        # Write via the same block device used by sfdisk, rather than its
        # backing file, to avoid two independent page-cache views of the MBR.
        with open(self.disk, 'r+b', buffering=0) as output:
            output.write(bytes(range(256)) + bytes(range(184)))
            output.seek(32768)
            output.write(self.loader)
            output.seek(8 * 1024**2)
            output.write(self.loader)
        with open(self.disk, 'rb', buffering=0) as inp:
            self.before_bootcode = inp.read(446)
        self.sentinel = b'configuration and application state must survive expansion\n'
        if kind in ('squashfs', 'fresh'):
            lower = self.base / 'lower'
            lower.mkdir()
            (lower / 'firmware').write_text('SWRT Photonicat 1')
            squash = self.base / 'root.squashfs'
            self.run_cmd('mksquashfs', str(lower), str(squash), '-noappend', '-no-progress', '-quiet', '-processors', '1')
            content = squash.read_bytes()
            self.data_offset = (struct.unpack_from('<Q', content, 40)[0] + 65535) // 65536 * 65536
            with open(self.part, 'r+b', buffering=0) as output:
                output.write(content)
            if kind == 'squashfs':
                data = self.attach(self.part, offset=self.data_offset)
                self.run_cmd('mkfs.f2fs', '-f', data)
                self.mount(data, self.root_mount, 'f2fs')
                (self.root_mount / 'saved-config').write_bytes(self.sentinel)
                self.uuid = self.run_cmd('blkid', '-p', '-o', 'value', '-s', 'UUID', data)
                self.unmount(self.root_mount)
                self.run_cmd('losetup', '-d', data)
                self.loops.remove(data)
            self.mount(self.part, self.root_mount, 'squashfs', readonly=True)
        else:
            self.run_cmd('mkfs.ext4', '-q', '-m', '0', self.part)
            self.mount(self.part, self.root_mount, 'ext4')
            (self.root_mount / 'saved-config').write_bytes(self.sentinel)
            self.uuid = self.run_cmd('blkid', '-p', '-o', 'value', '-s', 'UUID', self.part)
        if extra:
            with open(self.disk + 'p3', 'r+b', buffering=0) as output:
                output.write(b'OTHER-PARTITION-DATA-DO-NOT-TOUCH')
        self.kind = kind
        self.expected = (8388608 if extra else disk_bytes // 1048576 * 2048) - 131072
        self.fake_environment()

    def fake_environment(self):
        sysroot = self.base / 'sys'
        parent = sysroot / 'devices/mmcblk0'
        syspart = parent / 'mmcblk0p2'
        syspart.mkdir(parents=True)
        (syspart / 'partition').write_text('2')
        (parent / 'device').mkdir()
        (parent / 'device/type').write_text('MMC')
        (parent / 'removable').write_text('0')
        (parent / 'queue').mkdir()
        (parent / 'queue/logical_block_size').write_text('512')
        compatible = sysroot / 'firmware/devicetree/base'
        compatible.mkdir(parents=True)
        (compatible / 'compatible').write_bytes(b'ariaboard,photonicat\0rockchip,rk3568\0')
        number = f'{os.major(os.stat(self.part).st_rdev)}:{os.minor(os.stat(self.part).st_rdev)}'
        links = sysroot / 'dev/block'
        links.mkdir(parents=True)
        (links / number).symlink_to(syspart)
        dev = self.base / 'dev'
        mountinfo = self.base / 'mountinfo'
        mountinfo.write_text(f'17 1 {number} / / rw - {"ext4" if self.kind == "ext4" else "squashfs"} /dev/root rw\n')
        mounts = self.base / 'mounts'
        mounts.write_text('proc /proc proc rw 0 0\n')
        self.env = {**os.environ, 'SWRT_AUTOGROW_SYS': str(sysroot),
                    'SWRT_AUTOGROW_DEV': str(dev), 'SWRT_AUTOGROW_MOUNTINFO': str(mountinfo),
                    'SWRT_AUTOGROW_MOUNTS': str(mounts), 'SWRT_AUTOGROW_WORK': str(self.base / 'work')}

    def helper(self, expected_return=0, env=None):
        result = subprocess.run(['sh', str(ROOT / 'files/usr/libexec/swrt-autogrow'), 'grow'],
                                env=env or self.env, capture_output=True, text=True)
        diagnostics = result.stdout + result.stderr
        for file in (self.base / 'work').glob('*.log'):
            diagnostics += '\n' + file.read_text(errors='replace')[-6000:]
        self.assertEqual(result.returncode, expected_return, diagnostics)

    def verify(self, extra=False):
        self.helper()
        after = json.loads(self.run_cmd('sfdisk', '--json', self.disk))['partitiontable']
        expected = json.loads(json.dumps(self.before))
        expected['partitions'][1]['size'] = self.expected
        self.assertEqual(after, expected)
        with open(self.disk, 'rb', buffering=0) as inp:
            self.assertEqual(inp.read(446), self.before_bootcode)
            for offset in (32768, 8 * 1024**2):
                inp.seek(offset)
                self.assertEqual(inp.read(len(self.loader)), self.loader)
        if self.kind in ('squashfs', 'fresh'):
            self.unmount(self.root_mount)
            data = self.attach(self.part, offset=self.data_offset)
            if self.kind == 'fresh':
                # This is the normal first-boot formatting step owned by fstools.
                self.run_cmd('mkfs.f2fs', '-f', data)
            self.mount(data, self.root_mount, 'f2fs')
            source = data
        else:
            source = self.part
        if self.kind != 'fresh':
            self.assertEqual((self.root_mount / 'saved-config').read_bytes(), self.sentinel)
            self.assertEqual(self.run_cmd('blkid', '-p', '-o', 'value', '-s', 'UUID', source), self.uuid)
        stat = os.statvfs(self.root_mount)
        self.assertGreater(stat.f_blocks * stat.f_frsize, (self.expected * 512 - self.data_offset) * .85)
        if extra:
            with open(self.disk + 'p3', 'rb', buffering=0) as inp:
                self.assertEqual(inp.read(len(b'OTHER-PARTITION-DATA-DO-NOT-TOUCH')), b'OTHER-PARTITION-DATA-DO-NOT-TOUCH')
        self.unmount(self.root_mount)
        if self.kind in ('squashfs', 'fresh'):
            self.run_cmd('losetup', '-d', source)
            self.loops.remove(source)
            self.mount(self.part, self.root_mount, 'squashfs', readonly=True)
        self.helper()
        self.assertEqual(json.loads(self.run_cmd('sfdisk', '--json', self.disk))['partitiontable'], after)

    def test_existing_f2fs_8g(self): self.create(8, 'squashfs'); self.verify()
    def test_existing_f2fs_16g(self): self.create(16, 'squashfs'); self.verify()
    def test_existing_f2fs_64g(self): self.create(64, 'squashfs'); self.verify()
    def test_existing_ext4_8g(self): self.create(8, 'ext4'); self.verify()
    def test_existing_ext4_16g(self): self.create(16, 'ext4'); self.verify()
    def test_existing_ext4_64g(self): self.create(64, 'ext4'); self.verify()
    def test_fresh_squashfs_8g(self): self.create(8, 'fresh'); self.verify()
    def test_fresh_squashfs_16g(self): self.create(16, 'fresh'); self.verify()
    def test_fresh_squashfs_64g(self): self.create(64, 'fresh'); self.verify()
    def test_existing_data_partition_is_preserved(self): self.create(8, 'squashfs', extra=True); self.verify(extra=True)

    def test_actual_64gb_emmc_capacity(self):
        self.create(64, 'squashfs', disk_bytes=62545461248)
        self.verify()

    def test_non_mib_aligned_capacity(self):
        self.create(8, 'fresh', disk_bytes=8 * 1024**3 - 512)
        self.verify()

    def test_reboot_boundary_preserves_data_and_resumes(self):
        self.create(8, 'squashfs')
        tools = self.base / 'bin'
        tools.mkdir()
        partx = tools / 'partx'
        partx.write_text('#!/bin/sh\nexit 1\n')
        partx.chmod(0o755)
        self.helper(75, {**self.env, 'PATH': str(tools) + ':' + os.environ['PATH']})
        self.assertEqual(int(self.run_cmd('blockdev', '--getsz', self.part)), 2097152)
        self.assertFalse((self.base / 'work/filesystem.log').exists())
        # A real reboot reloads the MBR. Updating the test kernel's map here
        # gives the second boot the same enlarged block device geometry.
        self.run_cmd('partx', '-u', '-n', '2', self.disk)
        self.verify()

    def test_mounted_overlay_refuses_offline_resize_before_any_write(self):
        self.create(8, 'squashfs')
        Path(self.env['SWRT_AUTOGROW_MOUNTS']).write_text('/dev/loop42 /overlay f2fs rw 0 0\n')
        self.helper(1)
        self.assertEqual(json.loads(self.run_cmd('sfdisk', '--json', self.disk))['partitiontable'], self.before)

    def test_optional_mountinfo_fields_are_supported(self):
        self.create(8, 'squashfs')
        info = Path(self.env['SWRT_AUTOGROW_MOUNTINFO'])
        info.write_text(info.read_text().replace('/ / rw -', '/ /rom rw shared:1 master:2 -'))
        self.verify()


if __name__ == '__main__': unittest.main(verbosity=2)
