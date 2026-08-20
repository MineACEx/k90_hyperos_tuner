#!/system/bin/sh
# ============================================================
#  全局触控采样率固件配置 v3.2（touch_ini.sh）
#
#  原理：K90 的 Goodix GT9916 触控采样率由固件配置
#        /odm/firmware/annibale_gtp_thp_config.ini 决定，
#        官方触控驱动（libtouchreport_alg_goodix.so）按里面
#        report_rate 段的 normal/game/game_super 三档跑采样率。
#
#  本脚本在开机早期（post-fs-data）：
#    1) 从原厂配置复制一份
#    2) 只把采样率三档改成 config.sh 里的值
#    3) bind-mount 覆盖原厂文件（不写坏 /odm，卸载即还原）
#  这样是【官方驱动自己跑 240Hz】，软兼容、真正全局生效。
# ============================================================

apply_touch_ini() {
    [ -f "$TOUCH_INI_SRC" ] || { logp "触控INI: 原厂文件不存在，跳过"; return 1; }

    # 目标：模块目录里的生成文件（bind 源）
    INI_OUT="$MODDIR/odm/firmware/annibale_gtp_thp_config.ini"
    mkdir -p "$(dirname "$INI_OUT")" 2>/dev/null

    # 复制原厂并改采样率三档（其余保持原厂，最安全）
    # 注意：INI 行有前导空格，sed 不要用 ^ 锚点
    cp "$TOUCH_INI_SRC" "$INI_OUT" 2>/dev/null || { logp "触控INI: 复制失败"; return 1; }

    sed -i "s/ic_rate_normal=.*/ic_rate_normal=${TOUCH_NORMAL:-240}/" "$INI_OUT"
    sed -i "s/rate_normal=.*/rate_normal=${TOUCH_NORMAL:-240}/" "$INI_OUT"
    sed -i "s/ic_rate_game=.*/ic_rate_game=${TOUCH_GAME:-480}/" "$INI_OUT"
    sed -i "s/rate_game=.*/rate_game=${TOUCH_GAME:-480}/" "$INI_OUT"
    sed -i "s/ic_rate_game_super=.*/ic_rate_game_super=${TOUCH_GAME_SUPER:-480}/" "$INI_OUT"
    sed -i "s/rate_game_super=.*/rate_game_super=${TOUCH_GAME_SUPER:-480}/" "$INI_OUT"

    # 校验一下改对了没
    CUR=$(grep -E "rate_(normal|game|game_super)=" "$INI_OUT" | tr '\n' ' ')
    logp "触控INI: 已生成 $CUR"

    # bind-mount 覆盖原厂文件（mount --bind 不写坏 /odm，卸载可还原）
    if mount --bind "$INI_OUT" "$TOUCH_INI_SRC" 2>/dev/null; then
        restorecon "$TOUCH_INI_SRC" 2>/dev/null
        logp "触控INI: bind-mount 成功 → 官方驱动将按 ${TOUCH_NORMAL:-240}Hz 日常/ ${TOUCH_GAME:-480}Hz 游戏/ ${TOUCH_GAME_SUPER:-480}Hz 极速 运行"
        return 0
    else
        logp "触控INI: bind-mount 失败（保持原厂配置，不影响开机）"
        return 1
    fi
}
