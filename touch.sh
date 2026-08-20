#!/system/bin/sh
# ============================================================
#  触控采样率控制 v3.0（探测式，安全）
#
#  本机触控驱动在 vendor 分区（K90 = Goodix GT9916），
#  模块会【自动探测】常见节点（见 config.sh 的 TOUCH_NODE_CANDIDATES）。
#
#  两种写入方式：
#    1) 普通节点：直接写 Hz 值（如 240）
#    2) 索引式节点（如 Goodix switch_report_rate）：写档位索引，
#       由 config.sh 的 TOUCH_INDEX_NODES 定义「索引 ↔ Hz」映射。
#       K90 实测：写 0 = 240Hz，写 1 = 480Hz（硬件仅两档）。
#
#  找不到节点也不影响系统，只记日志；卸载时按备份还原原值。
# ============================================================

# 节点缓存文件（避免每次重复探测）
TOUCH_CACHE="$MODDIR/.touch_nodes"
# 触控节点原值备份（卸载时还原；索引式存索引值）
TOUCH_BACKUP="$MODDIR/.touch_backup"

logp() { echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# 展开候选列表里的通配符，返回真实存在的路径
expand_candidates() {
    local pat f
    for pat in $TOUCH_NODE_CANDIDATES; do
        case "$pat" in
            *\**) for f in $pat; do [ -e "$f" ] && echo "$f"; done ;;
            *) [ -e "$pat" ] && echo "$pat" ;;
        esac
    done
}

# 探测并缓存可用节点（可读且可写）
find_touch_nodes() {
    local node list="" n
    # 先看缓存（带存在性校验，失效自动重探）
    if [ -f "$TOUCH_CACHE" ]; then
        local valid=""
        while IFS= read -r n; do
            [ -n "$n" ] && [ -w "$n" ] && valid="$valid $n"
        done < "$TOUCH_CACHE"
        [ -n "$valid" ] && { echo "$valid" | tr ' ' '\n' | grep -v '^$'; return 0; }
    fi
    for node in $(expand_candidates); do
        if [ -r "$node" ] && [ -w "$node" ]; then
            list="$list $node"
        fi
    done
    if [ -n "$list" ]; then
        # 去重并写缓存
        echo "$list" | tr ' ' '\n' | grep -v '^$' | sort -u > "$TOUCH_CACHE" 2>/dev/null
        cat "$TOUCH_CACHE" 2>/dev/null
    else
        logp "触控采样率：未探测到可用节点（可在 config.sh 的 TOUCH_NODE_CANDIDATES 补充）"
        return 1
    fi
}

# 查询某节点是否索引式，命中则回显「索引|Hz 索引|Hz ...」
lookup_index_map() {
    local node="$1" pat spec
    for spec in $TOUCH_INDEX_NODES; do
        pat="${spec%%|*}"
        case "$node" in
            $pat) echo "${spec#*|}"; return 0;;
        esac
    done
    return 1
}

# 读节点当前采样率 Hz（如 "touch report rate::480HZ" -> 480；纯数字节点直接返回）
node_current_hz() {
    cat "$1" 2>/dev/null | tr -d ' \r' | grep -o '[0-9][0-9]*' | head -1
}

# 写一个触控节点到目标 Hz（自动识别索引式并换算）
write_touch_hz() {
    local node="$1" want="$2" map pair idx hz diff best_idx="" best_diff=""
    map=$(lookup_index_map "$node")
    if [ -n "$map" ]; then
        # 索引式：优先精确匹配，没有就选最接近的档位
        for pair in $map; do
            idx="${pair%%|*}"; hz="${pair#*|}"
            if [ "$hz" = "$want" ]; then
                echo "$idx" > "$node" 2>/dev/null && return 0
                return 1
            fi
            if [ "$hz" -gt "$want" ] 2>/dev/null; then
                diff=$((hz - want))
            else
                diff=$((want - hz))
            fi
            if [ -z "$best_diff" ] || [ "$diff" -lt "$best_diff" ]; then
                best_diff=$diff; best_idx=$idx
            fi
        done
        [ -n "$best_idx" ] && { echo "$best_idx" > "$node" 2>/dev/null && return 0; }
        logp "触控采样率: $node 无可写档位(${want}Hz)"
        return 1
    fi
    # 普通节点：直接写 Hz
    echo "$want" > "$node" 2>/dev/null
}

# 备份节点原值（索引式换算成索引；原显示值由调用方传入，确保是修改前的值）
backup_touch_node() {
    local node="$1" cur="$2" curhz idx map pair hz
    grep -q "^${node}=" "$TOUCH_BACKUP" 2>/dev/null && return 0   # 已备份过
    map=$(lookup_index_map "$node")
    if [ -n "$map" ]; then
        curhz=$(echo "$cur" | grep -o '[0-9][0-9]*' | head -1)
        for pair in $map; do
            idx="${pair%%|*}"; hz="${pair#*|}"
            if [ "$hz" = "$curhz" ]; then cur="$idx"; break; fi
        done
    fi
    echo "$node=$cur" >> "$TOUCH_BACKUP" 2>/dev/null
}

# 设置触控采样率（want=Hz，如 240 / 480）
set_touch_fps() {
    local want="$1" node cur orig found=""
    [ -z "$want" ] && return 0
    for node in $(find_touch_nodes); do
        cur=$(node_current_hz "$node")
        if [ "$cur" != "$want" ]; then
            orig=$(cat "$node" 2>/dev/null | tr -d ' \r')   # 写入前的原始值
            if write_touch_hz "$node" "$want"; then
                found="$node"
                backup_touch_node "$node" "$orig"
                logp "触控采样率: $node = ${want}Hz (原 ${cur}Hz)"
            fi
        fi
    done
    [ -n "$found" ] && return 0
    return 1
}

# 查询当前触控采样率（返回第一个节点的值）
get_touch_fps() {
    local node hz
    for node in $(find_touch_nodes); do
        hz=$(node_current_hz "$node")
        [ -n "$hz" ] && { echo "${hz}Hz"; return 0; }
    done
    echo "N/A"
}

# 守护：目标采样率、轮询间隔（秒）—— 由 game_daemon 在需要时调用
touch_guard_daemon() {
    local want="$1" interval="$2"
    [ -z "$want" ] && want=240
    [ -z "$interval" ] && interval=10
    while :; do
        [ -d "$MODDIR" ] || exit 0
        set_touch_fps "$want" 2>/dev/null
        sleep "$interval"
    done
}
