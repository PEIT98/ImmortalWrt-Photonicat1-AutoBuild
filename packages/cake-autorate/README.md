# 光影猫 cake-autorate

使用上游稳定分支 `v3.2` 的 **3.2.1**，固定提交 [`495038fd673a2146be08c2c4b76f77125c3c274b`](https://github.com/lynxthecat/cake-autorate/tree/495038fd673a2146be08c2c4b76f77125c3c274b)，下载时核对 SHA256。核心 `cake-autorate.sh`、`defaults.sh`、`lib.sh` 原样安装；本目录只维护 OpenWrt 打包、配置检查及服务接入。

首次默认关闭，安装后不会立即限速。配套内置 **网络 → SQM QoS**；实际带宽需要先测量再填写。CAKE 会占用 CPU，并通过限制队列带宽降低满载延迟，实际效果需要真机测试。

## 配置和启用

1. 在官方 QModem 页面完成拨号。`auto` 从 `mwan3.qmodem_priority3.interface` 读取实际接口，不固定为 `6_1` 或 `6_2`。
2. 查询实际设备（在 LuCI 网页终端执行）：

   ```sh
   iface="$(uci -q get mwan3.qmodem_priority3.interface)"
   ubus call "network.interface.$iface" status
   ```

3. 在防火墙设置中关闭软件/硬件流量分载，在 **网络 → SQM QoS** 选择上一步 `l3_device` 对应的设备，队列规则选择 `cake`，队列脚本可选 `piece_of_cake.qos`。上传和下载均填写大于零的实测速率后启用 SQM。
4. 编辑 `/etc/config/cake-autorate`，填写六项速率，单位均为 **Kbit/s**：`min_download`、`base_download`、`max_download`、`min_upload`、`base_upload`、`max_upload`。每个方向必须满足 **最低 ≤ 基准 ≤ 最高**；基准与 SQM 初始速率保持一致。零表示尚未配置，禁止启动。
5. 核对后启用：

   ```sh
   /usr/libexec/cake-autorate-prepare check
   # 上一条检查成功后执行
   uci set cake-autorate.main.enabled='1'
   uci commit cake-autorate
   /etc/init.d/cake-autorate enable
   /etc/init.d/cake-autorate restart
   logread -e cake-autorate
   ```

停止并关闭自动调整：

```sh
uci set cake-autorate.main.enabled='0'
uci commit cake-autorate
/etc/init.d/cake-autorate stop
/etc/init.d/cake-autorate disable
```

SQM 的固定整形独立运行；如需完全停止限速，在 SQM 页面也关闭对应配置。

## 多 WAN 与更换模组

- 启动前确认所选网络已连接、属于 mwan3 IPv4 接口，并且 SQM 为真实设备启用了唯一的 CAKE 配置。
- 从实际 ingress 重定向读取下载 IFB 设备，上传及下载都必须已有 CAKE 队列。
- 探测包经 `mwan3 use <实际接口> exec` 并绑定真实设备，避免有线 WAN 在线时测错出口。
- QModem 接口上线、更新或离线后重新解析配置。若更换模组导致实际设备变化，需要先在 SQM 页面选择新设备；缺少队列时停止启动并提示，不自动接管其他设备。
- 默认三路 IPv4 探测，每路间隔 1 秒；不将详细日志持续写入闪存。原始上游配置由 UCI 在 `/var/run/photonicat-cake-autorate/` 生成，重启后重新生成。
- 自定义接口可修改 `cake-autorate.main.interface`，仍须满足 mwan3/SQM 检查。

本服务不修改 QModem 源码，不写网络、防火墙或 SQM 配置，也不创建、替换或删除队列。
