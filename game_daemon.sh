#!/system/bin/sh
# ============================================================
#  多模式守护进程 v3.0（由 service.sh 启动，后台常驻）
#
#  职责：周期检查前台应用 / 手动档位，切换到对应模式（0~4）：
#    0省电  1日常  2均衡  3游戏  4极速
#  并联动触控采样率（高性能固定 240Hz，日常 180~200Hz）
#
#  省电设计：只在“模式变化”时才真正写节点
#  卸载模块后自动退出（检测 $MODDIR 是否还在）
# ============================================================

# 读取配置
MODDIR=/data/adb/modules/k90_hyperos_tuner
[ -f "$MODDIR/config.sh" ] && . "$MODDIR/config.sh"
[ -f "$MODDIR/profiles.sh" ] && . "$MODDIR/profiles.sh"
[ -f "$MODDIR/touch.sh" ] && . "$MODDIR/touch.sh"

[ "$PROFILE_DETECT" = "off" ] && exit 0

logp() { echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# 取当前前台应用包名（找不到返回空）
get_focus() {
    dumpsys window windows 2>/dev/null \
        | grep -m1 'mCurrentFocus' \
        | sed 's/.*{\([^/]*\)\/.*/\1/' \
        | tr -d ' \r'
}

# 是否命中白名单文件
in_list() {
    local pkg="$1" list="$2" line
    [ -z "$pkg" ] && return 1
    [ -f "$list" ] || return 1
    while IFS= read -r line; do
        line=$(echo "$line" | tr -d ' \r')
        case "$line" in ""|\#*) continue ;; esac
        [ "$line" = "$pkg" ] && return 0
    done < "$list"
    return 1
}

# 电池电量百分比（0~100，读不到返回空）
get_battery() {
    local cap
    cap=$(dumpsys battery 2>/dev/null | grep -m1 'level:' | sed 's/.*level: *\([0-9]*\).*/\1/' | tr -d ' \r')
    [ -n "$cap" ] && [ "$cap" -ge 0 ] 2>/dev/null && echo "$cap" || echo ""
}

# 自动决策当前档位
decide_profile() {
    local focus batt p
    focus=$(get_focus)
    # 电量过低 -> 省电
    if [ "${BATTERY_SAVE_LEVEL:-0}" -gt 0 ] 2>/dev/null; then
        batt=$(get_battery)
        [ -n "$batt" ] && [ "$batt" -le "$BATTERY_SAVE_LEVEL" ] 2>/dev/null && { echo 0; return; }
    fi
    # 命中游戏白名单 -> 游戏档
    if in_list "$focus" "$GAME_LIST"; then echo 3; return; fi
    # 命中省电白名单 -> 省电档
    if in_list "$focus" "$BATTERY_LIST"; then echo 0; return; fi
    # 默认档
    p=$(resolve_default_profile)
    echo "$p"
}

# 返回指定档位的触控目标 Hz（供守护复查）
profile_touch() {
    case "$1" in
        0) echo "$P0_TOUCH" ;;
        1) echo "$P1_TOUCH" ;;
        2) echo "$P2_TOUCH" ;;
        3) echo "$P3_TOUCH" ;;
        4) echo "$P4_TOUCH" ;;
    esac
}

# 运行时识别方式：优先读 WebUI 写入的 $MODDIR/.detect（auto/manual/off）
# 没有则由 config.sh 的 PROFILE_DETECT 决定（WebUI 写入后无需重启守护）
runtime_detect() {
    local d
    d=$(cat "$MODDIR/.detect" 2>/dev/null | tr -d ' \r')
    case "$d" in auto|manual|off) echo "$d"; return 0;; esac
    echo "${PROFILE_DETECT:-auto}"
}

CUR=unknow
logp "多模式守护启动 (detect=$PROFILE_DETECT 间隔 ${POLL_INTERVAL}s 默认档=${DEFAULT_PROFILE})"

while :; do
    # 模块被卸载时自动退出
    [ -d "$MODDIR" ] || { logp "模块已卸载，守护退出"; exit 0; }

    DETECT=$(runtime_detect)

    # 决定目标档位
    if [ "$DETECT" = "manual" ]; then
        TGT=$(cat "$MODDIR/.profile" 2>/dev/null | tr -d ' \r')
        case "$TGT" in 0|1|2|3|4) ;; *) TGT=$(resolve_default_profile) ;; esac
    else
        TGT=$(decide_profile)
    fi

    # 档位变化才应用（省电）
    if [ "$TGT" != "$CUR" ]; then
        apply_profile "$TGT"
        CUR="$TGT"
        echo "$CUR" > "$MODDIR/.current" 2>/dev/null   # 供 WebUI 展示
        logp "切换到档位 [$TGT] (detect=$DETECT 前台=$(get_focus))"
    else
        # 开启守护：每轮复查触控采样率，保持“固定目标值”
        # （K90 Goodix 只有 240/480 两档，被系统改回 480 时立刻写回）
        if [ "$TOUCH_GUARD" = "1" ] && [ "$CUR" != "unknow" ]; then
            want_touch=$(profile_touch "$CUR")
            [ -n "$want_touch" ] && set_touch_fps "$want_touch"
        fi
    fi

    sleep "${POLL_INTERVAL:-5}"
done
