# Redmi AX3000 (RA81) OpenWrt

为 **红米 AX3000（RA81 / M81，高通 IPQ5000 + QCN6102，256MB RAM + 128MB NAND）** 编译的 OpenWrt 固件，
重点是**把 2.4G Wi-Fi 真正跑起来**，并沿用原厂无线校准数据（ART / BDF）。

---

## 先说清楚一件事：没人"官方"支持这台机器

查证结果（2026-11）：

| 源码 | 有没有 RA81 适配 | 说明 |
|---|:---:|---|
| OpenWrt 官方（qualcommax/ipq50xx） | ❌ | 只有小米 AX6000、红米 AX5400（同为 IPQ5018 家族），没有 AX3000 |
| ImmortalWrt（master / 24.10） | ❌ | 同上，`ipq50xx.mk` 里没有 `redmi_ax3000` |
| LEDE（coolsnowwolf） | ❌ | 同上 |
| **hzyitc/openwrt-redmi-ax3000** | ✅ | 社区树，mainline 5.15，**唯一公开方案里 2.4G 可用的** |
| lekoOwO/openwrt-redmi-ax3000 | ⚠️ | 新内核，但作者明确写了 5GHz 无法发射 |

所以网上"很多人编译的包"基本是 **hzyitc 那套树**（或 openwrt.ai 之类基于它的在线构建），
而不是 ImmortalWrt 官方源。本仓库因此选定 hzyitc 树为底座，并**钉死 commit**
（`6faaa150`）保证可复现，避免上游改动导致突然变砖或丢 Wi-Fi。

---

## 本仓库做了什么（相对上游）

### 1. 2.4G 的真正病根与加固

2.4G 是 IPQ5000 **集成**射频（ath11k AHB），ath11k 必须拿到正确的 `board_id` 才会 bring-up：

```
M81（红米 AX3000） → 0x24   （wl_pa_type=epa）
M79（小米 CR880x） → 0x10   （wl_pa_type=ipa）
```

上游靠 `strings /dev/mtdblock15 | grep wl_pa_type` 判断，**分区号随固件版本变化**，
判错就默认 M79 的 0x10 → 2.4G 静默起不来（这就是"刷完没有 2.4G"的典型原因）。

本仓库把该 hotplug 脚本换成加固版：

- 依次探测 `mtdblock15/14/16/13/17/12`，任一命中即用（读分区带 3 秒超时，绝不卡启动）
- 读不到时对 `redmi,ax3000` **兜底用 0x24**（M81 正确值），而不是错用 0x10
- 每次判定写入 syslog：`logread -e ra81-wifi`

### 2. 首次启动按"频段"自动配置，而不是按 radio 序号

`/etc/uci-defaults/99-ra81-wifi` 用 `iw phy info` 判断哪个 phy 是 2.4G（含 2412 MHz），
再反查它对应 `radioN`，因此**不依赖 `radio0=2.4G` 这种假设**（探针顺序变了也不会配错）：

| 频段 | 配置 |
|---|---|
| 2.4G（IPQ5000） | `country=CN`、`channel=6`、`HE40` |
| 5G（QCN6102） | `country=CN`、`channel=36`、`HE160` |

### 3. 沿用原厂无线文件

- **BDF**：`ipq-wifi-redmi_ax3000`（2.4G `board-redmi_ax3000.ipq5018` + 5G `board-redmi_ax3000.qcn6122`）
- **校准数据**：开机从原厂 `0:ART` 分区提取（2.4G `0x1000 + 0x20000`，5G `0x26800 + 0x20000`），
  写入 ath11k 的 `caldata.bin` / `caldata_1.bin`

也就是说射频参数完全来自你机器自己的原厂校准，不是通用 BDF 顶替。

### 4. 排障脚本

```sh
ra81-wifi-diag
```

一次性输出：board_name、board_id 当前值、caldata/BDF 是否就位、ath11k dmesg、
每个 phy 的 band、radio↔phy 映射、iwinfo、hotplug 判定日志。

### 5. 预装软件（按 36MB 的槽位挑过）

`rootfs` / `rootfs_1` 各 **36MiB**（`0x02400000`），内核 + squashfs 都得塞进去，
剩下的才是 `/overlay`。所以清单是按「体积/收益」筛的，不是一股脑塞满。

先别把 **128MB NAND** 当成 128MB 可用空间——它是这么切的（`cat /proc/mtd` 实测 22 个分区）：

| 分区 | 偏移 | 大小 | 说明 |
|---|---|---|---|
| `rootfs` | 0x0a8000 | 36MiB | A 槽（当前系统） |
| `rootfs_1` | 0x2e80000 | 36MiB | B 槽（升级目标） |
| `overlay` | 0x5280000 | 31MiB | 原厂数据区，OpenWrt 没用它 |

所以真正能塞固件的只有 **36MiB**，另外 256MB 是 RAM（跑起来的内存，集成在 IPQ5000 里），
既不能拿来装包也不能持久化。

| 类别 | 内容 |
|---|---|
| 代理 | **PassWall 2 + Xray**（nftables 透明代理，含 chinadns-ng、geoip/geosite 规则库） |
| 网络 | SQM（CAKE 限速抗 bufferbloat）、DDNS（含 Cloudflare）、UPnP、WOL、WireGuard |
| 观测 | nlbwmon 流量统计、watchcat、https-dns-proxy、命令面板、uhttpd 设置 |
| 命令行 | curl、wget-ssl、htop、nano、iperf3、mtr、socat、ip-full |
| 内核 | `kmod-tcp-bbr` + `kmod-sched`（BBR 要的 fq）+ `kmod-sched-cake` |

刻意**没装**的：Argon 主题、adblock、frpc、Docker、samba（无 USB）——
都在 1MB 以上且非必需，会把 `/overlay` 挤到没法用。想加就自己 `opkg install`，
构建时也会用 `stat` 卡一道 34MiB 的尺寸守卫，超了直接让 CI 失败，不会发出一个刷不进去的包。

> **规则库做了替换**：PassWall2 默认拉的 Loyalsoldier 规则是 geoip 15.7MiB + geosite 10.7MiB
> = **26.4MiB**，光规则就顶满大半个槽位。改成本仓的 `patches/0001-v2ray-geodata-compact.patch`：
> MetaCubeX `geoip-lite.dat`（0.2MiB，只留 CN 段，"绕过大陆"够用）+ `geosite.dat`（4.1MiB，全量域名分类），
> 合计 4.3MiB，省下 22MiB。如果上游改了 Makefile 结构，这个补丁会直接打失败让 CI 停住，不会静默退回大规则库。

### 6. 其余

- 默认中文 LuCI（base / firewall / opkg / ttyd，以及上面这些 app 的中文包）
- 保留 `iw`、`iwinfo`、`ethtool`、`tcpdump-mini` 便于现场调试
- 构建后自动用 manifest 校验 30+ 个关键包，缺一个就让构建失败

---

## 现状与限制（务必先读）

| 项目 | 状态 |
|---|---|
| 启动 / 交换机 / 有线 | ✅ |
| 2.4G Wi-Fi | ✅（依赖 board_id 判定，本仓库已加固） |
| 5G Wi-Fi | ✅ 但需设对 `country/width/channel`；`HE160` 落在 52–64 时要等 DFS 雷达检测约 60 秒 |
| NSS 硬件加速 | ❌ 上游未启用（树里只有 `qca-nss-dp`/`qca-ssdk`，没有 `nss-drv`/`ecm`），NAT 靠 CPU；已默认开启软件 flow offload + BBR/fq + RPS/XPS 补偿 |
| 内核 / 用户态 | 5.15 / OpenWrt 23.05（**偏老，这是能用 2.4G 的代价**） |
| 内存 | 256MB，双频全开较紧；不建议再装重插件（Docker 免谈） |
| 刷机风险 | 需处理 rootfs / rootfs_1 双槽位，刷错槽位会变砖，UART 是最终保险 |

> 想追新内核（6.12/6.18）就得自己重写板级 DTS + 重新验证 ath11k 双频 bring-up，
> 属于有硬件才能做的工程；本仓库选择"能用"优先。

---

## 刷机

### 方式 A：从原厂固件刷（免拆机，推荐）

1. 原厂固件先开 SSH（用 [xmir-patcher](https://github.com/openwrt-xiaomi/xmir-patcher)，选 1 设网关、2 解锁）
2. 把 release 里的 `openwrt-ipq50xx-arm-redmi_ax3000-squashfs-nand-factory.ubi` 传到 `/tmp`
3. 确认槽位并刷到**另一个**槽：

```sh
cat /proc/mtd                      # 确认 rootfs=mtd18, rootfs_1=mtd19
mtd="$(grep -oE 'ubi.mtd=[a-zA-Z0-9_-]*' /proc/cmdline | cut -d= -f2)"

if [ "$mtd" = "rootfs" ]; then
    ubiformat /dev/mtd19 -f /tmp/openwrt-ipq50xx-arm-redmi_ax3000-squashfs-nand-factory.ubi
    nvram set flag_try_sys2_failed=0; nvram set flag_boot_rootfs=1; nvram set flag_last_success=1
else
    ubiformat /dev/mtd18 -f /tmp/openwrt-ipq50xx-arm-redmi_ax3000-squashfs-nand-factory.ubi
    nvram set flag_try_sys1_failed=0; nvram set flag_boot_rootfs=0; nvram set flag_last_success=0
fi
nvram commit && reboot
```

### 方式 B：UART + U-Boot（刷坏了用这个救）

上游 README 有完整步骤：先用 `MIWIFIRepairTool`（本质 TFTP recovery）恢复原厂并开启 UART，
再在 U-Boot 里 `tftpboot` + `flash rootfs_1` + `setenv` 三个 flag。详见
[hzyitc/README](https://github.com/hzyitc/openwrt-redmi-ax3000#how-to-install)。

### 刷完第一件事

```sh
ra81-wifi-diag          # 看两个 band 是否都起来了、board_id 是不是 0x24
logread -e ra81-wifi    # 看首次启动的判定结果
```

如果 2.4G 仍不出现：把 `ra81-wifi-diag` 输出发出来，
90% 是 `board_id` 判定成了 0x10（M79），或 ART 分区偏移与你的固件版本不同。

### 之后如何升级

release 里**只有 `nand-factory.ubi`，没有 sysupgrade.bin**，这是上游设备定义的决定
（`IMAGES := nand-factory.ubi`）。RA81 是 A/B 双槽，升级就是把这个 `.ubi` 刷进
**当前没在跑的那个槽**，再切 flag：

```sh
# 先备份配置（换槽后会用到新系统的默认配置）
sysupgrade -b /tmp/ra81-backup.tar.gz

cd /tmp && wget <新版本 nand-factory.ubi>
mtd="$(grep -oE 'ubi.mtd=[a-zA-Z0-9_-]*' /proc/cmdline | cut -d= -f2)"
if [ "$mtd" = "rootfs" ]; then
    ubiformat /dev/mtd19 -f openwrt-*nand-factory.ubi -y   # 写 rootfs_1
    fw_setenv flag_try_sys2_failed 0; fw_setenv flag_boot_rootfs 1; fw_setenv flag_last_success 1
else
    ubiformat /dev/mtd18 -f openwrt-*nand-factory.ubi -y   # 写 rootfs
    fw_setenv flag_try_sys1_failed 0; fw_setenv flag_boot_rootfs 0; fw_setenv flag_last_success 0
fi
reboot
```

好处是**旧系统还在另一个槽里**，新固件起不来时改回 `flag_boot_rootfs` 即可回退，
不至于变砖。

---

## 回滚到原厂

用小米官方 `MIWIFIRepairTool` + 原厂固件（`miwifi_ra81_firmware_1dd69c_1.0.33.bin`）走 TFTP 恢复即可。

---

## 构建

GitHub Actions 手动触发 `Build Redmi AX3000`，或每周日 12:00 自动构建。
流程：钉住 commit 拉源码 → 校验板级文件在位 → feeds → 载入 config → Wi-Fi overlay →
defconfig 后校验 9 个关键包 → 编译 → manifest 校验 → 发 release（保留最近 3 个）。

---

## 参考

- [hzyitc/openwrt-redmi-ax3000](https://github.com/hzyitc/openwrt-redmi-ax3000) — 板级支持、ART 校准与 2.4G 方案来源
- [OpenWrt: Xiaomi AX3000T](https://openwrt.org/toh/xiaomi/ax3000t) — 同品牌刷机风险与槽位机制的参考
- [Qualcomm ipq50xx / ath11k](https://git.codelinaro.org/clo/qsdk) — 上游驱动与固件
