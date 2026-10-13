'use strict';
'require baseclass';
'require rpc';

var getPhotonicatInfo = rpc.declare({
  object: 'luci.photonicat1',
  method: 'get_info',
  expect: { '': {} }
});

return baseclass.extend({
  title: _('光影猫固件与 Docker 存储'),

  load: function() {
    return L.resolveDefault(getPhotonicatInfo(), {});
  },

  render: function(data) {
    var info = data || {};
    var build = info.build || {};
    var docker = info.docker || {};
    var table = E('table', { 'class': 'table' });
    var add = function(title, value) {
      table.appendChild(E('tr', { 'class': 'tr' }, [
        E('td', { 'class': 'td left', 'width': '33%' }, [ E('strong', {}, title) ]),
        E('td', { 'class': 'td left' }, [ value == null || value === '' ? '-' : String(value) ])
      ]));
    };
    var sha = function(s) { return s ? String(s).slice(0, 12) : '-'; };
    add(_('设备'), build.device || 'Photonicat1');
    add(_('编译日期'), build.time);
    add(_('内核版本'), build.kernel);
    add(_('编译仓库'), sha(build.builder_sha));
    add(_('ImmortalWrt'), sha(build.immortalwrt_sha));
    add(_('QModem'), sha(build.qmodem_sha));
    add(_('Aurora'), sha(build.aurora_sha));

    add(_('Docker 引擎'), docker.installed ? _('已安装') : _('未安装'));
    add(_('Docker 数据目录'), docker.data_root);
    add(_('当前目录可用空间'), docker.available);
    var mounts = Array.isArray(docker.mounted_storage) ? docker.mounted_storage : [];
    add(_('检测到的存储挂载'), mounts.length ? mounts.join('; ') : _('没有检测到 /mnt 或 /media 下的块设备挂载'));
    if (docker.installed) {
      add(_('Docker 存储提示'), docker.data_on_mounted_storage
        ? _('当前数据目录位于已挂载的存储分区')
        : _('当前数据目录未检测到位于外部挂载分区；如需使用 SSD，请先挂载并手动迁移配置'));
    }
    return table;
  }
});
