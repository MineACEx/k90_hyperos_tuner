#!/system/bin/sh
# ============================================================
#  Scene 的 /data/swap_config.conf 判断与优化
#
#  职责：
#   1) 判断文件是否存在、内容是否合法，非法值自动修正
#   2) 在保留注释/结构的前提下，按需优化里面的值
#   3) 把最终值同时写进 sysfs/sysctl（双保险，不怕 Scene 时序）
#   4) 首次运行先备份原文件，随时可还原
# ============================================================

SCENE_CONF=/data/swap_config.conf
BACKUP="$MODDIR/swap_config.conf.bak"

# 内核是否支持某算法
algo_supported() {
    # 检查 zram 的 comp_algorithm 是否包含该算法（zram 未就绪时查内核符号）
    if [ -e /sys/block/zram0/comp_algorithm ]; then
        cat /sys/block/zram0/comp_algorithm 2>/dev/null | grep -qw "$1" && return 0
    fi
    # 备用判断：该算法是否以内核模块形式存在
    for m in "$1" "$1_compress" "$1_decompress"; do
        [ -e "/sys/module/$m" ] && return 0
    done
    # lz4k/lz4kd 是动态压缩后端：comp_algorithm 初始列表不显示，
    # 但只要 crypto 层已注册（/proc/crypto），写入即可启用，视为可用
    grep -qw "$1" /proc/crypto 2>/dev/null && return 0
    return 1
}

# 判断 + 决定最终 zram 算法
decide_alg() {
    local cur="$1" pref="$ZRAM_ALGO_PREF"
    case "$pref" in
        auto)
            if algo_supported lz4k; then
                echo "lz4k"
            else
                echo "$cur"
            fi
            ;;
        lz4k|lz4kd|zstd|lz4|lzo-rle|lzo)
            if algo_supported "$pref"; then
                echo "$pref"
            else
                logp "算法 [$pref] 内核暂不支持，保留 [$cur]"
                echo "$cur"
            fi
            ;;
        *) echo "$cur" ;;
    esac
}

# 修改配置文件里某一行的值（按 key 查找并原地替换）
conf_set() {
    local key="$1" val="$2" tmp="$MODDIR/.conf_tmp"
    [ -f "$SCENE_CONF" ] || return 1
    if grep -q "^${key}=" "$SCENE_CONF" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$SCENE_CONF" 2>/dev/null
    else
        echo "${key}=${val}" >> "$SCENE_CONF"
    fi
    logp "配置文件已更新: $key=$val"
}

# 应用到一个 sysfs/sysctl（节点不存在跳过）
w2() { [ -e "$1" ] && echo "$2" > "$1" 2>/dev/null; }

run_swap_conf() {
    [ "$MANAGE_SCENE_CONF" = "1" ] || return 0
    [ -f "$SCENE_CONF" ] || { logp "未找到 $SCENE_CONF，跳过 Scene 配置处理"; return 0; }

    # 1) 首次备份
    if [ ! -f "$BACKUP" ]; then
        cp "$SCENE_CONF" "$BACKUP" 2>/dev/null && logp "已备份原配置 -> $BACKUP"
    fi

    logp "=== Scene 配置判断开始 ==="

    # 2) 读取并校验关键值（非法值自动修正）
    local sw=$(grep '^swappiness=' "$SCENE_CONF" | cut -d= -f2)
    local sz=$(grep '^zram_size=' "$SCENE_CONF" | cut -d= -f2)
    local wm=$(grep '^watermark_scale_factor=' "$SCENE_CONF" | cut -d= -f2)
    local efk=$(grep '^extra_free_kbytes=' "$SCENE_CONF" | cut -d= -f2)
    local alg=$(grep '^comp_algorithm=' "$SCENE_CONF" | cut -d= -f2)

    # 判断：swappiness 必须在 0~200
    if [ -n "$sw" ] && { [ "$sw" -lt 0 ] || [ "$sw" -gt 200 ]; }; then
        logp "swappiness=$sw 非法，修正为 20"
        conf_set swappiness 20; sw=20
    fi
    # 判断：watermark_scale_factor 1~1000
    if [ -n "$wm" ] && { [ "$wm" -lt 1 ] || [ "$wm" -gt 1000 ]; }; then
        logp "watermark_scale_factor=$wm 非法，修正为 50"
        conf_set watermark_scale_factor 50; wm=50
    fi
    # 判断：zram_size 上限保护（避免写死内存）
    if [ -n "$sz" ] && { [ "$sz" -gt 16384 ] || [ "$sz" -le 0 ]; }; then
        logp "zram_size=$sz 超范围，修正为 12288"
        conf_set zram_size 12288; sz=12288
    fi

    # 3) 算法：判断内核支持情况后决定（Scene 原值 lzo-rle -> 有 lz4k 则切换）
    if [ -n "$alg" ]; then
        local newalg=$(decide_alg "$alg")
        if [ "$newalg" != "$alg" ]; then
            logp "压缩算法 $alg -> $newalg（内核支持判断通过）"
            conf_set comp_algorithm "$newalg"
            alg="$newalg"
        else
            logp "压缩算法保持 [$alg]"
        fi
    fi

    # 4) swappiness 用户覆盖
    if [ -n "$SWAPPINESS_OVERRIDE" ]; then
        conf_set swappiness "$SWAPPINESS_OVERRIDE"; sw="$SWAPPINESS_OVERRIDE"
    fi

    # 5) 把最终值直接写进系统（双保险）
    if [ -n "$sw" ]; then w2 /proc/sys/vm/swappiness "$sw"; logp "sysctl swappiness=$sw"; fi
    if [ -n "$wm" ]; then w2 /proc/sys/vm/watermark_scale_factor "$wm"; fi
    if [ -n "$efk" ]; then w2 /proc/sys/vm/extra_free_kbytes "$efk"; fi
    if [ -n "$alg" ] && [ -e /sys/block/zram0/comp_algorithm ]; then
        # 只有在 zram 未被占用时才尝试改算法（被占用就靠 boot-completed 的重建流程）
        if ! grep -q zram0 /proc/swaps 2>/dev/null; then
            w2 /sys/block/zram0/comp_algorithm "$alg"
            logp "sysfs comp_algorithm=$alg"
        else
            logp "zram 已被占用，算法切换交给 boot-completed 流程处理"
        fi
    fi

    logp "=== Scene 配置判断完成 ==="
}
