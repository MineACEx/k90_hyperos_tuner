#!/system/bin/sh
# ============================================================
#  K90 HyperOS 多模式调优 v3.2 - service.sh（开机早期）
#
#  做五件事：
#   1) 基础内存/存储参数（缓存/脏页）
#   2) Scene 的 /data/swap_config.conf 判断与优化 + SWAP 设置
#   3) 应用默认调度档位（0省电/1日常/2均衡/3游戏/4极速）
#   4) 启动多模式守护（自动识别前台 + 触控采样率联动）
#   5) 触控采样率全局配置已在 post-fs-data 完成（bind-mount INI）
#
#  【安全设计】
#  - 所有写入都带节点存在性检查，系统不支持的自动跳过
#  - 每一项失败都不影响开机；卸载模块即完全还原
#  - 软兼容官方调度：不卸载 millet/perfmgr/GameTurbo，只做叠加微调
# ============================================================

MODDIR=/data/adb/modules/k90_hyperos_tuner
[ -f "$MODDIR/config.sh" ] && . "$MODDIR/config.sh"
[ -f "$MODDIR/profiles.sh" ] && . "$MODDIR/profiles.sh"
[ -f "$MODDIR/zram_manage.sh" ] && . "$MODDIR/zram_manage.sh"

[ -f "$LOG" ] || touch "$LOG"
log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG"; }

log "===== service.sh 开始 ====="

# ---------- 1) 内存 / 存储 ----------
sysctl -w vm.vfs_cache_pressure="${VFS_CACHE_PRESSURE:-50}" 2>/dev/null && log "vfs_cache_pressure=${VFS_CACHE_PRESSURE:-50}"
sysctl -w vm.dirty_background_ratio="${DIRTY_BACKGROUND_RATIO:-5}" 2>/dev/null
sysctl -w vm.dirty_ratio="${DIRTY_RATIO:-20}" 2>/dev/null
sysctl -w vm.dirty_writeback_centisecs="${DIRTY_WRITEBACK_CENTISECS:-2000}" 2>/dev/null
sysctl -w vm.dirty_expire_centisecs="${DIRTY_EXPIRE_CENTISECS:-1000}" 2>/dev/null
log "基础内存/存储参数已设置"

# ---------- 2) Scene 配置判断与优化 + SWAP 应用 ----------
[ -f "$MODDIR/swap_conf.sh" ] && . "$MODDIR/swap_conf.sh"
run_swap_conf
apply_swap_conf

# ---------- 3) 应用默认调度档位 ----------
P=$(resolve_default_profile)
apply_profile "$P"

# ---------- 4) 启动多模式守护 ----------
# 先杀掉可能残留的旧守护，再启动新的
pkill -f "$MODDIR/game_daemon.sh" 2>/dev/null
[ -f "$MODDIR/game_daemon.sh" ] && \
    nohup sh "$MODDIR/game_daemon.sh" >/dev/null 2>&1 &
log "多模式守护已启动 (detect=$PROFILE_DETECT 默认档=$DEFAULT_PROFILE)"

log "===== service.sh 完成 ====="
exit 0
