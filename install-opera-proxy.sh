#!/bin/sh
. /etc/rc.common

echo "⚙️ Скачивание и установка opera-proxy..."
cd /tmp
wget -O opera-proxy_1.9.0.ipk "https://github.com/GNabi/Openwrt-proxy-mipsel_24kc/raw/refs/heads/main/opera-proxy_1.9.0_mipsel_24kc.ipk"
opkg install ./opera-proxy_1.9.0.ipk

echo "📁 Создание /etc/config/opera-proxy..."
cat << EOF > /etc/config/opera-proxy
config instance 'default'
  option enabled '1'
  option args '--bind-address 127.0.0.1:18081 --socks-mode'

config instance 'Americas'
  option enabled '1'
  option args '--bind-address 127.0.0.1:18082 --country AM --socks-mode'

config instance 'Asia'
  option enabled '1'
  option args '--bind-address 127.0.0.1:18083 --country AS --socks-mode'
EOF

echo "⚙️ Создание /etc/init.d/opera-proxy..."
cat << 'EOF' > /etc/init.d/opera-proxy
#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1

PROG=/usr/bin/opera-proxy

opera_proxy_instance() {
    local section="$1"
    local enabled
    local args

    config_get_bool enabled "$section" enabled 0
    [ "$enabled" -eq 0 ] && return 0

    config_get args "$section" args ""

    procd_open_instance
    procd_set_param command "$PROG"
    [ -n "$args" ] && procd_append_param command $args
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}

start_service() {
    config_load opera-proxy
    config_foreach opera_proxy_instance instance
}

service_triggers() {
    procd_add_reload_trigger opera-proxy
}
EOF

chmod +x /etc/init.d/opera-proxy
/etc/init.d/opera-proxy enable
/etc/init.d/opera-proxy restart

echo "✅ Установка завершена. opera-proxy перезапущен."
