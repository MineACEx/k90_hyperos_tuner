#!/system/bin/sh
# 卸载清理：杀守护、解除触控INI挂载、还原触控采样率、还原Scene配置、删日志与备份
MODDIR=/data/adb/modules/k90_hyperos_tuner

# 1) 杀掉守护进程
pkill -f "$MODDIR/game_daemon.sh" 2>/dev/null
pkill -f "game_daemon.sh" 2>/dev/null

# 2) 解除触控固件配置的 bind-mount（还原 /odm/firmware 原厂）
umount /odm/firmware/annibale_gtp_thp_config.ini 2>/dev/null

# 3) 还原触控采样率 sysfs 到修改前的值（如果有备份）
if [ -f "$MODDIR/.touch_backup" ]; then
    while IFS='=' read -r node old; do
        [ -n "$node" ] && [ -n "$old" ] && echo "$old" > "$node" 2>/dev/null
    done < "$MODDIR/.touch_backup"
    rm -f "$MODDIR/.touch_backup" "$MODDIR/.touch_nodes" 2>/dev/null
fi

# 4) 还原 Scene 的 swap_config.conf（我们改过它，留了备份）
if [ -f "$MODDIR/swap_config.conf.bak" ]; then
    cp "$MODDIR/swap_config.conf.bak" /data/swap_config.conf 2>/dev/null
fi

# 5) 清理
rm -f "$MODDIR/tuner.log" 2>/dev/null
rm -f "$MODDIR/user_config.conf" "$MODDIR/.profile" "$MODDIR/.detect" "$MODDIR/.current" 2>/dev/null
rm -rf "$MODDIR/odm" 2>/dev/null
exit 0
