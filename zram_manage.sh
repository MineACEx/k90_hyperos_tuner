#!/system/bin/sh
# ============================================================
#  SWAP / ZRAM 管理 v3.2（zram_manage.sh）
#
#  提供 WebUI 和开机脚本共用的函数：
#    zram_status       查询状态
#    zram_rebuild      重建 zram（换算法 / 换大小）
#    swap_set_swappiness 设置 swappiness
#    swap_set_vfs      设置 vfs_cache_pressure
#    apply_swap_conf   按 config.sh/Scene 应用 swap 设置
#
#  所有重建操作都带【失败回退】：换算法失败就换回原来的，
#  确保不会把 zram 弄没导致系统异常。
# ============================================================

logp() { echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# 内核目前可用的 zram 压缩算法全集
# =  zram comp_algorithm 初始列表 ∪ crypto 层动态后端（lz4k/lz4kd 等，写入即启用）
zram_avail_algos() {
    local z=/sys/block/zram0 base extra a
    base=$(cat $z/comp_algorithm 2>/dev/null | tr -d '[]' | tr ' ' '\n' | grep -v '^$')
    for a in lz4k lz4kd; do
        grep -qw "$a" /proc/crypto 2>/dev/null || continue
        echo "$base" | grep -qw "$a" || extra="$extra $a"
    done
    echo "$base$extra"
}

# 查询 zram/swap 当前状态（输出 key=value 便于 WebUI 解析）
zram_status() {
    local z=/sys/block/zram0 algo size comp
    algo=$(cat $z/comp_algorithm 2>/dev/null | tr -d '\n')
    size=$(cat $z/disksize 2>/dev/null)
    [ -n "$size" ] && size=$((size / 1024 / 1024))
    comp=$(grep zram0 /proc/swaps 2>/dev/null | awk '{print $4}')
    echo "algo=$algo"
    echo "avail=$(zram_avail_algos 2>/dev/null | tr -d '\n')"
    echo "size_gb=$size"
    echo "swap_mb=${comp:-0}"
    echo "swappiness=$(cat /proc/sys/vm/swappiness 2>/dev/null)"
    echo "vfs_cache_pressure=$(cat /proc/sys/vm/vfs_cache_pressure 2>/dev/null)"
}

# 重建 zram：换算法或换大小
# 用法：zram_rebuild <算法> <大小GB>   （算法为空=保持不变；大小0=保持不变）
zram_rebuild() {
    local want_algo="$1" want_gb="$2"
    local z=/sys/block/zram0 old_algo old_gb ok=1
    [ "$ZRAM_DYNAMIC_CTL" = "1" ] || { logp "ZRAM 动态调整已被关闭"; return 1; }

    old_algo=$(cat $z/comp_algorithm 2>/dev/null | tr -d '[]' | cut -d' ' -f1)
    old_gb=$(( $(cat $z/disksize 2>/dev/null) / 1024 / 1024 ))
    [ -z "$want_algo" ] && want_algo="$old_algo"
    [ -z "$want_gb" ] || [ "$want_gb" -le 0 ] && want_gb="$old_gb"

    logp "ZRAM 重建: $old_algo/${old_gb}GB → $want_algo/${want_gb}GB"

    # 先关掉 swap，重置
    swapoff /dev/block/zram0 2>/dev/null
    echo 1 > $z/reset 2>/dev/null || { logp "ZRAM reset 失败，中止"; return 1; }

    # 换算法（可能失败：内核不支持）
    if ! echo "$want_algo" > $z/comp_algorithm 2>/dev/null; then
        logp "算法 [$want_algo] 内核不支持，回退 [$old_algo]"
        echo "$old_algo" > $z/comp_algorithm 2>/dev/null
        want_algo="$old_algo"
        ok=0
    fi

    # 设大小
    echo "$((want_gb * 1024 * 1024))" > $z/disksize 2>/dev/null || ok=0

    # 建 swap 并启用
    mkswap /dev/block/zram0 2>/dev/null
    swapon /dev/block/zram0 2>/dev/null || ok=0

    logp "ZRAM 重建完成: 算法=$want_algo 大小=${want_gb}GB"
    [ "$ok" = "1" ]
}

# 设置 swappiness（0~200）
swap_set_swappiness() {
    local v="$1"
    [ -n "$v" ] || return 1
    sysctl -w vm.swappiness="$v" 2>/dev/null
    logp "swappiness=$v"
}

# 设置 vfs_cache_pressure（100 附近）
swap_set_vfs() {
    local v="$1"
    [ -n "$v" ] || return 1
    sysctl -w vm.vfs_cache_pressure="$v" 2>/dev/null
    logp "vfs_cache_pressure=$v"
}

# 按配置应用 swap 相关设置（开机/WebUI 共用）
apply_swap_conf() {
    local SW
    SW=${SWAPPINESS_OVERRIDE:-}
    if [ -z "$SW" ] && [ -f /data/swap_config.conf ]; then
        SW=$(grep '^swappiness=' /data/swap_config.conf 2>/dev/null | cut -d= -f2)
    fi
    [ -n "$SW" ] && swap_set_swappiness "$SW"
    swap_set_vfs "${VFS_CACHE_PRESSURE:-50}"
}
