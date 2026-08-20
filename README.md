# K90 HyperOS 多模式调优 + Paimon 内核刷入教程

让 Redmi K90（HyperOS4 / Android 17）既能用上 **Paimon 自定义内核**（华为 LZ4K 压缩、Xring 内存、slim_walt/hmbird 调度、KernelSU），又配套一个**多模式性能调优 Magisk 模块**（触控采样率、Scene 调度、ZRAM 等）。

> 一句话：**内核用『手工替换』刷，不用 AnyKernel3**——因为 AnyKernel3 在 HOS4/A17 上会变砖，手工替换只动内核段，把变砖点整个绕开。

---

## 一、这个项目能给你什么

### 1. Paimon 内核（可选，强烈推荐）
官方二进制：`6.6.139-android15-8-Paimon-26Y08C14`，内置

- **LZ4K / LZ4KD** 华为压缩算法（crypto 层已注册）
- **Xring 内存压缩方案**（zswapd、zgroup、mctrl、smart_cache）
- **slim_walt 双态调度 + hmbird 自研调速器**
- **KernelSU**（LKM 型，root 走 init_boot）
- version-spoof、UFS/DWC3/DRM 优化等

### 2. K90 调优 Magisk 模块
- 五档性能模式（Balance / 均衡 / 性能 / 电竞 / 极速…，`apply_profile` 统一入口）
- **触控采样率**自动探测并守护（K90 = Goodix GT9916，240Hz 固定/游戏联动）
- **Scene 调度配置** 判断与优化（`/data/swap_config.conf`）
- **Scene 配置可视化编辑器**：读取 `/data/swap_config.conf` 并把**注释+参数映射成表单**，按注释填、一键保存回写、导出到任意路径、支持导入（WebUI 内操作，Scene 负责应用）
- 游戏识别 + 低电量省电
- **不做 ZRAM / SWAP 即改**：SWAP、ZRAM 参数的读写统一交给 **Scene** 管理，避免模块与 Scene 抢占同一份 `swap_config.conf` 而起冲突；WebUI 里只做这只读状态查看 + 配置编辑界。

### 3. 配套 WebUI（KSU/APatch 控制台）
- 高斯模糊玻璃拟态卡片、G2 超贝塞尔圆角、A/B 槽信息、触控采样率实时显示
- 支持亮/暗色切换
- **Scene 配置编辑卡**：读当前配置→表单→保存/导出/导入

---

## 二、为什么必须"手工替换"刷内核（重点）

**AnyKernel3 直刷在 OS3 正常、到 OS4(Android17) 就变砖**，原因是它会把 boot 分区整体重写/重排，在新布局上触发不兼容。

**手工替换只改一件东西**：把原厂 `boot_a` 里的内核段换成 Paimon `Image`，`header / dtb / cmdline / init_boot` 全部原样保留。

### 刷机步骤（Windows + fastboot）

```
# 1) 解包原厂 boot（magiskboot 会把 kernel/kernel_dtb/header 弹到当前目录）
magiskboot --unpack boot_a.img

# 2) 备份原厂内核段，再换成 Paimon
cp kernel kernel.stock
cp Image kernel            # 注意：两边都是 raw ARM64 EFI-stub 内核(MZ魔数)，格式一致

# 3) 重打包 -> 输出 new-boot.img
magiskboot --repack boot_a.img

# 4) 刷入（当前活动槽一般为 a，先 getvar 确认）
fastboot getvar current-slot
fastboot flash boot_a new-boot.img
fastboot reboot
```

> 关键校验：全新内核必须是 `MZ` 开头（32 位 PE/EFI 头 + 0x4d 0x5a），与 `fastboot` 能识别的 raw ARM64 `Image` 一致；不要用 gzip/lz4 压缩容器直接覆盖。

### 回顾 / 回退
```
fastboot flash boot_a boot_a.img               # 原厂 kernel
fastboot flash init_boot_a init_boot_a.img     # 原厂 init_boot（KSU）
```

---

## 三、安装调优模块

1. 已刷 Paimon（含 KernelSU）或使用原厂+init_boot KSU
2. 把本仓库的 `k90_hyperos_tuner/` 打包为 zip 用 Magisk/KSU 管理器刷入
3. 打开 WebUI 设置触控采样率、性能档；SWAP/ZRAM 只需在 **Scene 配置** 卡里改 `/data/swap_config.conf`（模块不做即改，交给 Scene 应用，避免冲突）

配置文件：`config.sh`（全中文注释），改完重启生效。

---

## 四、ZRAM / LZ4K（实测可用）

- **LZ4K / LZ4KD 内核已内置**（`/proc/crypto` 可查），ARMv8 NEON 加速有效。
- **它们就是可用的 zram 压缩后端**：zram 的 `comp_algorithm` **初始列表并不完整**，lz4k/lz4kd 这类动态后端不预先显示，但**写入即激活**。实测 `echo lz4kd > /sys/block/zram0/comp_algorithm` 成功后，`comp_algorithm` 变为 `… [lz4kd]`（方括号即当前生效算法）。
- **推荐 lz4kd**（华为高压缩比、接近 zstd 而更快）。模块已修复检测（`/proc/crypto`），持久化方式同作者做法：在 WebUI 的 **Scene 配置** 卡里把 `/data/swap_config.conf` 的 `comp_algorithm=` 改成 `lz4kd`，Scene 负责应用。

> 自测：`su -c cat /sys/block/zram0/comp_algorithm`，看到 `[lz4kd]` 就是生效了。

---

## 五、特性"能吃上几个"对照（基于实测）

| 特性 | 状态 |
|---|---|
| LZ4K / LZ4KD（crypto 层 + NEON） | ✅ 内核已内置 |
| LZ4K/LZ4KD 作为 **ZRAM 压缩后端** | ✅ 实测可切换（写 `lz4kd` 即激活，推荐） |
| Xring / zswapd / zgroup / mctrl / smart_cache | ✅ 内核内置（对模块透明） |
| slim_walt / hmbird 调度 | ⚠️ 需装作者 KP-N 模块（nemo_*.ko） |
| version-spoof | ✅ 内核内置 |
| UFS / DWC3 / DRM | ✅ 内核内置 |
| KernelSU root | ✅ 走 init_boot |

---

## 六、目录结构（仓库根 = 模块本体）

```
├── README.md              # 本文
├── module.prop
├── customize.sh
├── post-fs-data.sh        # 开机早期挂载/INI
├── service.sh             # 开机早期：内存/存储
├── boot-completed.sh      # 开机完成：ZRAM/触控/Scene 复检
├── config.sh              # 全中文配置
├── profiles.sh            # 五档模式
├── touch.sh               # 触控采样率探测+守护
├── touch_ini.sh           # 触控固件 INI bind-mount
├── zram_manage.sh         # ZRAM 重建（安全回退）+ 算法检测
├── swap_conf.sh           # Scene swap 配置优化 + 算法支持判断
├── game_daemon.sh         # 游戏/省电联动
├── battery_apps.list      # 低电量豁免应用清单
├── games.list             # 游戏识别清单
├── uninstall.sh           # 卸载还原
├── README.txt             # 模块内说明
└── webroot/               # 玻璃拟态 WebUI（index.html）
```

---

## 许可 & 致谢

- **内核（Paimon / NanaIIy）全部版权归原作者 NetizenNemo**。本仓库**不重新分发**任何内核二进制，教程里用到的 `Image`、`6.6-Kernel-Paimon-26Y08C14` 均为该作者的官方产物，请在其官方发布渠道获取。
- **本仓库只提供**：①针对 HyperOS4/Android17 的安全刷入教程（手工替换内核段，绕开 AnyKernel3 变砖）；②自研的调优 Magisk 模块（触控采样率、五档调度、Scene 配置、ZRAM 管理）。
- 模块按需求自制，安全优先（所有回写失败均回退）。
- 刷内核 / 刷模块均有风险，变砖可用原厂分区 + `fastboot` 一键回退，刷前请确认 bootloader 已解锁。