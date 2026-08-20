#!/system/bin/sh
# ============================================================
#  K90 多档调度实现 v3.0
#  0省电 / 1日常 / 2均衡 / 3游戏 / 4极速
#
#  ★ 软兼容官方调度 ★
#  - 不卸载、不屏蔽 millet / perfmgr / GameTurbo / 温控
#  - 只用官方同一套标准接口：schedtune(stune)、sysctl、cpufreq
#  - 高负载档位“抬下限 + 提权重”，绝不锁全核满频
# ============================================================

# ---------- 工具函数 ----------
logp() { echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# 写一个 sysfs/sysctl 节点，节点不存在就跳过
w() {
    local f="$1" v="$2"
    if [ -e "$f" ]; then
        echo "$v" > "$f" 2>/dev/null && return 0
        logp "写入失败(跳过): $f = $v"
    fi
    return 1
}

# 读一个节点（不存在返回空）
r() { [ -e "$1" ] && cat "$1" 2>/dev/null; }

# 设置 stune(schedtune) 分组的参数
# 用法: stune 组名 参数名 值
stune() {
    local f="/dev/stune/$1/$2"
    [ -e "$f" ] && echo "$3" > "$f" 2>/dev/null
}

# 从 scaling_available_frequencies 里挑一个 >= 目标的最小合法频率
pick_freq() {
    local cpu="$1" want="$2" avail best=""
    avail=$(r "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_available_frequencies")
    [ -z "$avail" ] && return 1
    for f in $avail; do
        if [ "$f" -ge "$want" ] 2>/dev/null; then
            if [ -z "$best" ] || [ "$f" -lt "$best" ]; then best="$f"; fi
        fi
    done
    [ -n "$best" ] && echo "$best" || return 1
}

# 把大核簇最低频率设置为 target（0=交还 governor 管理）
set_prime_min() {
    local target="$1" c f
    for c in 0 1 2 3 4 5 6 7; do
        if [ -e "/sys/devices/system/cpu/cpu$c/cpufreq/scaling_min_freq" ]; then
            if [ "$target" -gt 0 ] 2>/dev/null; then
                f=$(pick_freq "$c" "$target")
                [ -n "$f" ] && echo "$f" > "/sys/devices/system/cpu/cpu$c/cpufreq/scaling_min_freq" 2>/dev/null
            else
                # 交还 governor：写 0 = 不设人工下限（8 Elite 内核接受 0）
                echo 0 > "/sys/devices/system/cpu/cpu$c/cpufreq/scaling_min_freq" 2>/dev/null
            fi
        fi
    done
}

# ============================================================
#  核心：应用档位 N
#  用法：apply_profile 0|1|2|3|4
# ============================================================
apply_profile() {
    local N="$1"
    local BOOST PREFER BKG EAS PMIN TOUCH NAME

    case "$N" in
        0) BOOST=$P0_BOOST;  PREFER=$P0_PREFER;  BKG=$P0_BKG;  EAS=$P0_EAS;  PMIN=$P0_PMIN;  TOUCH=$P0_TOUCH;  NAME="省电";;
        1) BOOST=$P1_BOOST;  PREFER=$P1_PREFER;  BKG=$P1_BKG;  EAS=$P1_EAS;  PMIN=$P1_PMIN;  TOUCH=$P1_TOUCH;  NAME="日常";;
        2) BOOST=$P2_BOOST;  PREFER=$P2_PREFER;  BKG=$P2_BKG;  EAS=$P2_EAS;  PMIN=$P2_PMIN;  TOUCH=$P2_TOUCH;  NAME="均衡";;
        3) BOOST=$P3_BOOST;  PREFER=$P3_PREFER;  BKG=$P3_BKG;  EAS=$P3_EAS;  PMIN=$P3_PMIN;  TOUCH=$P3_TOUCH;  NAME="游戏";;
        4) BOOST=$P4_BOOST;  PREFER=$P4_PREFER;  BKG=$P4_BKG;  EAS=$P4_EAS;  PMIN=$P4_PMIN;  TOUCH=$P4_TOUCH;  NAME="极速";;
        *) N=1; BOOST=$P1_BOOST; PREFER=$P1_PREFER; BKG=$P1_BKG; EAS=$P1_EAS; PMIN=$P1_PMIN; TOUCH=$P1_TOUCH; NAME="日常(兜底)";;
    esac

    logp "=== 应用档位 [$N $NAME] ==="

    # 1) EAS 能耗感知（1=开 0=关）
    w /proc/sys/kernel/sched_energy_aware "$EAS"

    # 2) schedtune：前台 boost / 大核偏好
    stune top-app schedtune.boost "$BOOST"
    stune top-app schedtune.prefer_idle "$PREFER"
    stune foreground schedtune.boost "$BOOST"
    stune foreground schedtune.prefer_idle "$PREFER"

    # 3) 后台降权（省电、防后台抢资源）
    stune background schedtune.boost 0
    stune background schedtune.prefer_idle "$BKG"

    # 4) 大核最低频（软兼容：只抬下限不锁满频）
    set_prime_min "$PMIN"

    # 5) 触控采样率联动
    if [ -f "$MODDIR/touch.sh" ]; then
        . "$MODDIR/touch.sh"
        set_touch_fps "$TOUCH"
    fi

    logp "档位 [$N $NAME] 应用完成 (boost=$BOOST eas=$EAS pmin=$PMIN touch=$TOUCH)"
    return 0
}

# ---------- 兼容旧接口 ----------
apply_daily() { apply_profile "${DEFAULT_PROFILE:-1}"; }
apply_game()  { apply_profile 3; }

# 读取当前应该生效的“基础档”（default 或 manual）
resolve_default_profile() {
    case "$PROFILE_DETECT" in
        manual)
            m=$(cat "$MODDIR/.profile" 2>/dev/null | tr -d ' \r')
            case "$m" in 0|1|2|3|4) echo "$m"; return 0;; esac
            ;;
    esac
    echo "${DEFAULT_PROFILE:-1}"
}
