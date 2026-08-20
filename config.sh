#!/system/bin/sh
# ============================================================
#  K90 HyperOS 多模式调优 v3.2 - 用户配置
#
#  所有可调项都在这里，每项都带中文说明。
#  修改保存后重启生效（或手动重跑 service.sh）。
#  看不懂的项不要动，默认值是权衡过的。
#
#  ★ WebUI 保存/加载 ★
#  本文件是【默认值】。你在 WebUI 里保存的配置会写入
#  $MODDIR/user_config.conf（key=value），启动时自动叠加在本文件之上，
#  所以 WebUI 改的值会覆盖这里的默认值，想改回默认删掉 user_config.conf 即可。
#
#  ★ 软兼容官方调度 ★
#  不卸载 / 不屏蔽 millet / perfmgr / GameTurbo / 温控，
#  只用官方同一套标准接口（schedtune / sysctl / cpufreq / 触控节点/固件配置）。
# ============================================================

# 模块目录与日志（一般不用改）
MODDIR=/data/adb/modules/k90_hyperos_tuner
LOG=$MODDIR/tuner.log

# ---------- 一、模式选择（核心） ----------
# 档位编号：
#   0 = 省电   （超长续航，CPU 全部偏小核省电）
#   1 = 日常   （默认日用，省电又顺滑）
#   2 = 均衡   （流畅优先，中boost）
#   3 = 游戏   （性能释放，CPU 高频+触控满血，但不过度）
#   4 = 极速   （极致性能，接近满核满频，触控满血）
# 开机默认用哪个档：
DEFAULT_PROFILE=1

# 模式识别方式：
#   auto   = 每 5 秒看前台应用：命中游戏白名单→游戏档(3)；
#            命中省电白名单→省电档(0)；否则→默认档（推荐）
#   manual = 不轮询，用 $MODDIR/.profile 里手动填的档位（0~4）
#   off    = 永远只用 DEFAULT_PROFILE，不自动切换
PROFILE_DETECT=auto

# 轮询间隔(秒)，越小越灵敏但略耗电
POLL_INTERVAL=5

# 游戏白名单文件（每行一个包名，# 开头是注释）
GAME_LIST=$MODDIR/games.list
# 省电白名单文件（这些应用在前台时用省电档；不需要可留空）
BATTERY_LIST=$MODDIR/battery_apps.list

# 电池电量低于该百分比(%)时强制切到省电档（0=关闭这个功能）
BATTERY_SAVE_LEVEL=0

# ---------- 二、各档位 CPU 调度参数（软兼容官调） ----------
# BOOST  = top-app/foreground 的 schedtune.boost（0~200，越大越激进）
# PREFER = 前台任务是否偏向大核（1=是 0=否）
# BKG    = 后台任务是否偏向大核（0=否 省电）
# EAS    = 能耗感知开关（1=开 0=关；关=调度器全力跑性能）
# PMIN   = 大核簇最低频率(HZ)，0=不抬升（由 governor 管理）
#          抬升保证“一点就动”，但绝不锁全核满频
# TOUCH  = 本档要写入 sysfs 触控节点的采样率(HZ)，守护会保持它

# ---- 0 省电档 ----
P0_BOOST=0
P0_PREFER=0
P0_BKG=0
P0_EAS=1
P0_PMIN=0
P0_TOUCH=240

# ---- 1 日常档（默认）----
P1_BOOST=10
P1_PREFER=1
P1_BKG=0
P1_EAS=1
P1_PMIN=0
P1_TOUCH=240

# ---- 2 均衡档 ----
P2_BOOST=40
P2_PREFER=1
P2_BKG=0
P2_EAS=1
P2_PMIN=0
P2_TOUCH=240

# ---- 3 游戏档 ----
P3_BOOST=150
P3_PREFER=1
P3_BKG=0
P3_EAS=0
P3_PMIN=1804800
P3_TOUCH=480

# ---- 4 极速档 ----
P4_BOOST=200
P4_PREFER=1
P4_BKG=0
P4_EAS=0
P4_PMIN=2265600
P4_TOUCH=480

# ---------- 三、全局触控采样率（重要） ----------
# 你的 K90 触控芯片是 Goodix GT9916，固件配置里分三档：
#   normal      = 日常档（官方原厂是 135Hz，本模块提到 240Hz）
#   game        = 游戏档（官方原厂 240Hz，本模块默认提到 480Hz）
#   game_super  = 极速档（官方原厂 480Hz，保持满血）
# 模块会在开机时用这些值生成 annibale_gtp_thp_config.ini 并覆盖原厂配置，
# 让【官方触控驱动】自己把采样率跑起来（这就是“全局 240Hz”的做法）。
# 硬件只有 240 / 480 两档，不要填别的值。
TOUCH_NORMAL=240        # 日常档采样率(HZ) → 240
TOUCH_GAME=480          # 游戏档采样率(HZ) → 480
TOUCH_GAME_SUPER=480    # 极速档采样率(HZ) → 480

# 高性能档（游戏/极速）是否【持续守护】sysfs 采样率不被系统改回
# 1=每轮复查，被系统改回就重新写；0=只在切档时写一次
TOUCH_GUARD=1

# 触控采样率节点（探测式，一般不用改）
# 模块会自动探测这些路径，找到可读可写的就用；
# 也可在这里补你手机的实际节点。每个一行，支持 * 通配符。
TOUCH_NODE_CANDIDATES='
/proc/touchpanel/sampling_rate
/proc/touchpanel/report_rate
/sys/class/touchscreen/*/sampling_rate
/sys/class/touchscreen/*/report_rate
/sys/devices/platform/goodix_ts.*/switch_report_rate
/sys/devices/platform/goodix_ts.*/report_rate
/sys/devices/platform/soc/*/*/*/sampling_rate
/sys/devices/platform/soc/*/*/*/report_rate
/sys/devices/platform/soc/*/*/touch*/*/sampling_rate
/sys/bus/i2c/devices/*/report_rate
/sys/bus/i2c/devices/*/sample_rate
'

# 索引式触控节点（有些驱动节点不写 Hz 而是写档位索引）
# 格式：<节点路径>|<索引1>|<Hz1>|<索引2>|<Hz2>...
# K90 Goodix switch_report_rate：写 0 = 240Hz，写 1 = 480Hz
TOUCH_INDEX_NODES='
/sys/devices/platform/goodix_ts.*/switch_report_rate|0|240|1|480
'

# 触控固件配置文件路径（原厂，模块开机时覆盖它；一般不用改）
TOUCH_INI_SRC=/odm/firmware/annibale_gtp_thp_config.ini

# ---------- 四、SWAP / ZRAM ----------
# 是否接管并优化 Scene 的 /data/swap_config.conf（1=是 0=否）
MANAGE_SCENE_CONF=1

# 想覆盖 swappiness 时填 0~200（留空=用 Scene 原值 20）
SWAPPINESS_OVERRIDE=

# zram 压缩算法偏好：
#   lz4kd = 华为高压缩比，接近 zstd 而更快（Paimon 内核推荐，默认）
#   auto  = 内核有 lz4k/lz4kd 就用（优先 lz4k）
#   直接填 lzo-rle / lz4 / zstd 等强制指定
ZRAM_ALGO_PREF=lz4kd

# 刷入 lz4k 内核模块后，是否开机把 ZRAM 切到 lz4k（0=不切 1=切）
# 注意：现在的 vendor_boot_lz4k.img 会让内核 panic（见 README），
# 请先别开，等修复版内核模块再改 1。
SWITCH_ZRAM_ALGO=0
# 切换目标算法：lz4k / lz4kd（lz4kd 压缩率更高）
TARGET_ALGO=lz4kd

# 是否允许 WebUI 动态调整 zram 大小/算法（1=是 0=否）
# 动态调整会短暂 swapoff→重建 zram，期间内存压力较大，默认开启
ZRAM_DYNAMIC_CTL=1

# ---------- 五、基础内存 / IO（所有档位通用） ----------
# 缓存压力（默认 100；50=更积极保留缓存，更省电更流畅）
VFS_CACHE_PRESSURE=50
# 脏页后台比例（越低越早开始写回，防卡顿）
DIRTY_BACKGROUND_RATIO=5
# 脏页总比例
DIRTY_RATIO=20
# 脏页写回间隔（厘秒）
DIRTY_WRITEBACK_CENTISECS=2000
# 脏页过期时间（厘秒）
DIRTY_EXPIRE_CENTISECS=1000

# ============================================================
#  叠加 WebUI 保存的配置（key=value，会覆盖上面的默认值）
# ============================================================
[ -f "$MODDIR/user_config.conf" ] && . "$MODDIR/user_config.conf"
