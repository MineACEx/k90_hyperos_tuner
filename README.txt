# K90 HyperOS 多模式调优（KernelSU 模块）v3.2

针对 REDMI K90（HyperOS4 / Android 17，骁龙 8 Elite）的安全系统less调优模块。
**软兼容官方调度**：不卸载 / 不屏蔽 millet / perfmgr / GameTurbo / 温控，只在官方之上叠加微调。

## 安装
1. 传 `k90_hyperos_tuner_v3.2.zip` 到手机
2. KernelSU 管理器 → 模块 → 从本地安装 → 选择该 zip
3. 重启

## WebUI（推荐）
安装后，在 **KernelSU 管理器 → 模块 → K90 多模式调优** 里点打开：
- **调度**：识别方式（自动/手动/关闭）+ 一键切 5 档 + 实时状态
- **SWAP/ZRAM**：看 swappiness/缓存压力/算法/大小/占用；
  改 swappiness 立即生效并保存；重建 ZRAM（换算法/大小）
- **配置**：触控三档采样率 + 游戏/极速 boost；保存配置、恢复默认、加载外部配置
- 命令行等价操作：`echo manual > /data/adb/modules/k90_hyperos_tuner/.detect`

## 功能
| 项目 | 说明 |
|---|---|
| 全局触控 | 日常 240Hz / 游戏 480Hz / 极速 480Hz（bind 原厂触控固件配置，官方驱动全局生效） |
| WebUI | 换模式 + SWAP/ZRAM 管理 + 配置保存/加载 |
| 5 档调度 | 0省电 / 1日常 / 2均衡 / 3游戏 / 4极速 |
| Scene 集成 | 自动判断并优化 /data/swap_config.conf（备份卸载还原） |
| 自动识别 | 游戏白名单→游戏档；省电白名单→省电档；低电量→省电档 |

## 全局触控采样率（重点）
- K90 触控芯片是 **Goodix GT9916**，采样率由固件配置
  `/odm/firmware/annibale_gtp_thp_config.ini` 决定，分三档：
  - **normal（日常）**：官方原厂 **135Hz**，本模块提到 **240Hz**
  - **game（游戏）**：官方原厂 240Hz，本模块默认提到 **480Hz**
  - **game_super（极速）**：官方原厂 480Hz，保持满血
- 模块在开机早期（post-fs-data）从原厂配置复制一份，只改采样率三档，
  **bind-mount 覆盖**原厂文件（不写坏 /odm，卸载即还原）。
  这样是【官方触控驱动自己跑采样率】，真正全局生效。
- 改法：WebUI「配置」标签里改三档 → 保存 → 重启；或改 config.sh 的
  `TOUCH_NORMAL / TOUCH_GAME / TOUCH_GAME_SUPER`。
- 硬件只有 240 / 480 两档。

## SWAP / ZRAM
- WebUI 里可实时改 swappiness / 缓存压力（立即生效并持久化）。
- 可重建 ZRAM：换算法、换大小（会短暂 swapoff，几秒）。
- **lz4k / lz4kd**：需要修复版内核模块。当前 vendor_boot_lz4k.img
  加载 lz4k.ko 会让内核 **panic**（见下），**先别选**。

## 5 档调度
| 档 | 名称 | 触控 | 说明 |
|---|---|---|---|
| 0 | 省电 | 240Hz | EAS开、零boost偏小核，超长续航 |
| 1 | 日常 | 240Hz | EAS开、低boost偏大核，省电顺滑（默认） |
| 2 | 均衡 | 240Hz | 流畅优先，中boost |
| 3 | 游戏 | 480Hz | 关EAS、高boost、大核最低频抬升 |
| 4 | 极速 | 480Hz | 更高boost与频率下限，接近满核但不锁频 |

## 改数值
编辑 `/data/adb/modules/k90_hyperos_tuner/config.sh`，保存后重启生效（每项都有中文注释）。
WebUI 保存的配置写在 user_config.conf，覆盖 config.sh 默认值。

## 白名单
- 游戏：`games.list`（每行一个包名，命中自动切游戏档）
- 省电：`battery_apps.list`（命中自动切省电档）

## 手动强制档位（不用 WebUI 时）
```sh
echo manual > .../k90_hyperos_tuner/.detect   # 切到手动
echo 0 > .../k90_hyperos_tuner/.profile       # 0省电 1日常 2均衡 3游戏 4极速
echo auto  > .../k90_hyperos_tuner/.detect    # 恢复自动
```

## 卸载
KernelSU 管理器 → 模块 → 卸载。自动：杀守护、解除触控INI挂载、还原触控采样率、
还原 Scene 配置、清理日志。

## 日志
`/data/adb/modules/k90_hyperos_tuner/tuner.log` 查看是否生效（含触控INI/sysfs）。

---

# ⚠️ vendor_boot_lz4k.img 变砖原因与修复（重要）

## 现象
刷入 `vendor_boot_lz4k.img` 后卡第一屏循环重启。

## 已确认根因
- 模块里注入的 `lz4k.ko`（云端编译，vermagic `6.6.57-4k-gf66f8c8bcbe3-dirty`）
  与设备内核 `6.6.118-android15-8-ge56cf6b09cca-ab15511674-4k` **不兼容**。
- 实测：在正常系统上 `insmod lz4k.ko` 直接 **内核 panic → 整机重启**。
- 开机时 init 第一个就加载 lz4k.ko → panic → 循环重启 → 卡第一屏。
- 补充：原厂备份镜像模块 vermagic 是 `6.6.57-...`，也能在 6.6.118 内核加载，
  说明本机内核不严格校验 vermagic（属 MODULE_SIG/MODVERSIONS 宽松态），
  所以不是 vermagic 拒绝，而是 lz4k.ko 的代码/ABI 与 6.6.118 不兼容导致 panic。

## 修复方案（还没做，需要你决定）
必须**用设备同源内核源码重新编译**这些模块：
- 内核源码版本：`6.6.118-android15-8-ge56cf6b09cca-ab15511674-4k`
- 设备内核配置已导出：`D:\GKI\work\device_config.gz`
- 编译目标：`lz4k.ko / lz4k_encode.ko / lz4k_decode.ko / lz4kd* / zram.ko / zsmalloc.ko`
  （zram.ko 需带 lz4k 后端，zsmalloc 需与原厂 ABI 一致）
- 编译好后用 `repack_vendor_boot.py` 重新注入（脚本在 `D:\GKI\deliverables\lz4k_zram_build\`）

需要你提供或确认：K90/annibale 的 6.6.118 android15-8 内核源码仓库地址，
然后我可以帮你配置云端/本地构建。
