#!/system/bin/sh
# ============================================================
#  K90 HyperOS 多模式调优 v3.2 - boot-completed.sh
#  运行时机：系统完全启动后（ZRAM 一定已就绪）
#
#  负责：
#   1) 等待并确认 zram 状态
#   2) （可选）把 ZRAM 切换到 lz4k/lz4kd（需已刷入内核模块）
#   3) 复查触控 INI 是否仍生效（系统可能没读，重新 bind 一次）
#   4) 复查 Scene / SWAP 配置是否被系统覆盖
#   5) 复查默认调度档位
#   6) 日志汇总
# ============================================================

MODDIR=/data/adb/modules/k90_hyperos_tuner
[ -f "$MODDIR/config.sh" ] && . "$MODDIR/config.sh"
[ -f "$MODDIR/profiles.sh" ] && . "$MODDIR/profiles.sh"
[ -f "$MODDIR/touch.sh" ] && . "$MODDIR/touch.sh"
[ -f "$MODDIR/touch_ini.sh" ] && . "$MODDIR/touch_ini.sh"
[ -f "$MODDIR/zram_manage.sh" ] && . "$MODDIR/zram_manage.sh"

[ -f "$LOG" ] || touch "$LOG"
log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG"; }

log "===== boot-completed.sh 开始 ====="

# 等待 zram 设备出现（最多 60 秒）
ZRAM_DEV=/sys/block/zram0
for i in $(seq 1 60); do
    [ -d "$ZRAM_DEV" ] && break
    sleep 1
done

if [ -d "$ZRAM_DEV" ]; then
    ALGO=$(cat "$ZRAM_DEV/comp_algorithm" 2>/dev/null)
    SIZE=$(cat "$ZRAM_DEV/disksize" 2>/dev/null)
    INUSE=$(grep zram0 /proc/swaps 2>/dev/null)
    log "ZRAM 已就绪：算法=[$ALGO] 大小=[$SIZE]"
    [ -n "$INUSE" ] && log "ZRAM 已作为 swap 使用" || log "警告：zram 未出现在 swap 中"
else
    log "未发现 zram 设备（异常）"
fi

# ---------- 可选：切换 ZRAM 算法到 lz4k/lz4kd ----------
# （SWITCH_ZRAM_ALGO=1 才执行；失败自动回退原算法，安全）
if [ "${SWITCH_ZRAM_ALGO:-0}" = "1" ] && [ -d "$ZRAM_DEV" ]; then
    log "尝试把 ZRAM 算法切换到 [$TARGET_ALGO] ..."
    zram_rebuild "${TARGET_ALGO:-lz4kd}" "$(( $(cat "$ZRAM_DEV/disksize" 2>/dev/null) / 1024 / 1024 ))"
    log "ZRAM 最终算法: $(cat "$ZRAM_DEV/comp_algorithm" 2>/dev/null)"
fi

# ---------- 复查触控 INI（bind-mount 若失效则重新挂）----------
if [ -f "$MODDIR/odm/firmware/annibale_gtp_thp_config.ini" ]; then
    CUR_INI=$(grep -E "rate_normal=" "$TOUCH_INI_SRC" 2>/dev/null | head -1)
    MY_INI=$(grep -E "rate_normal=" "$MODDIR/odm/firmware/annibale_gtp_thp_config.ini" 2>/dev/null | head -1)
    if [ "$CUR_INI" != "$MY_INI" ]; then
        log "触控INI: 原厂被改回($CUR_INI)，重新 bind"
        apply_touch_ini
    else
        log "触控INI: 正常生效 ($CUR_INI)"
    fi
fi

# ---------- 复查 SWAP 设置 ----------
apply_swap_conf
log "复查 swappiness=$(cat /proc/sys/vm/swappiness 2>/dev/null) vfs=$(cat /proc/sys/vm/vfs_cache_pressure 2>/dev/null)"

# ---------- 复查默认档位（防系统重置）----------
if [ "$PROFILE_DETECT" = "off" ]; then
    P=$(resolve_default_profile)
    apply_profile "$P"
    log "复查：已重新应用默认档 [$P]"
fi

# ---------- 汇总 ----------
log "本机支持的 zram 算法: $(cat "$ZRAM_DEV/comp_algorithm" 2>/dev/null | tr -d '\n')"
log "当前触控采样率        = $(get_touch_fps 2>/dev/null)"
log "===== boot-completed.sh 完成 ====="
exit 0
