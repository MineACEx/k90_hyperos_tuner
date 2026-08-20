#!/system/bin/sh
# ============================================================
#  K90 多模式调优 v3.2 - post-fs-data.sh（开机早期）
#
#  运行时机：/data 挂载后、framework 启动前。
#  做两件事：
#   1) 加载配置
#   2) 生成并 bind-mount 触控固件配置（全局 240Hz 的关键）
#      必须在官方触控驱动读取配置【之前】完成，所以放这里。
# ============================================================

MODDIR=${0%/*}
[ -f "$MODDIR/config.sh" ] && . "$MODDIR/config.sh"
[ -f "$MODDIR/touch_ini.sh" ] && . "$MODDIR/touch_ini.sh"

[ -f "$LOG" ] || touch "$LOG"
log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG"; }
logp() { log "$@"; }

log "===== post-fs-data.sh 开始 ====="

# 全局触控采样率固件配置（bind-mount 覆盖原厂）
apply_touch_ini

log "===== post-fs-data.sh 完成 ====="
exit 0
