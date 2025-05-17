#!/bin/sh

echo "===> Установка sing-box..."
echo "Скачивание бинарника sing-box..."
wget -O /usr/bin/sing-box https://github.com/GNabi/Openwrt-proxy-mipsel_24kc/raw/refs/heads/main/sing-box_mipsel_24kc
chmod +x /usr/bin/sing-box

echo "Создание конфигурационного файла /etc/config/sing-box..."
cat <<EOF > /etc/config/sing-box
config sing-box 'main'
	option enabled '1'
	option user 'root'
	option conffile '/etc/sing-box/config.json'
	option workdir '/usr/share/sing-box'
EOF

echo "Создание конфигурации /etc/sing-box/config.json..."
mkdir -p /etc/sing-box
cat <<EOF > /etc/sing-box/config.json
{
  "log": {
    "level": "warn"
  },
  "inbounds": [
    {
      "type": "tproxy",
      "listen": "::",
      "listen_port": 1603,
      "sniff": false
    }
  ],
  "outbounds": [
    {
      "type": "socks",
      "server": "127.0.0.1",
      "server_port": 18081,
      "version": "5"
    }
  ],
  "route": {
    "auto_detect_interface": true
  }
}
EOF

echo "Создание init.d-скрипта /etc/init.d/sing-box..."
cat <<'EOF' > /etc/init.d/sing-box
#!/bin/sh /etc/rc.common

USE_PROCD=1
START=99

NAME="sing-box"
PROG="/usr/bin/sing-box"

start_service() {
    config_load "$NAME"

    local enabled user group conffile workdir ifaces
    config_get_bool enabled "main" "enabled" "0"
    [ "$enabled" -eq "1" ] || return 0

    config_get user "main" "user" "root"
    config_get conffile "main" "conffile"
    config_get ifaces "main" "ifaces"
    config_get workdir "main" "workdir" "/usr/share/sing-box"

    mkdir -p "$workdir"
    group="$(id -ng "$user" 2>/dev/null || echo "$user")"
    chown "$user:$group" "$workdir"

    procd_open_instance "$NAME.main"
    procd_set_param command "$PROG" run -c "$conffile" -D "$workdir"
    procd_set_param user "$user"
    procd_set_param file "$conffile"
    [ -z "$ifaces" ] || procd_set_param netdev $ifaces
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param respawn
    procd_close_instance
}

service_triggers() {
    local ifaces
    config_load "$NAME"
    config_get ifaces "main" "ifaces"
    procd_open_trigger
    for iface in $ifaces; do
        procd_add_interface_trigger "interface.*.up" "$iface" /etc/init.d/$NAME restart
    done
    procd_close_trigger
    procd_add_reload_trigger "$NAME"
}
EOF

chmod +x /etc/init.d/sing-box

echo "Добавление в автозагрузку и запуск sing-box..."
/etc/init.d/sing-box enable
/etc/init.d/sing-box start

echo "✅ Установка sing-box завершена."
