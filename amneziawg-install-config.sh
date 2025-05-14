#!/bin/sh

set -e

# Обновить список пакетов
opkg update

# Установка jq, curl, base64
opkg install jq curl coreutils-base64

# Определение архитектуры
PKGARCH=$(opkg print-architecture | awk 'BEGIN {max=0} {if ($3 > max) {max = $3; arch = $2}} END {print arch}')
VERSION=$(ubus call system board | jsonfilter -e '@.release.version')
TARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f 1)
SUBTARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f 2)
PKGPOSTFIX="_v${VERSION}_${PKGARCH}_${TARGET}_${SUBTARGET}.ipk"

BASE_URL="https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/v${VERSION}"
TMP_DIR="/tmp/amneziawg"
mkdir -p "$TMP_DIR"

# Скачиваем и устанавливаем пакеты
for PKG in kmod-amneziawg amneziawg-tools luci-app-amneziawg; do
  FILE="${PKG}${PKGPOSTFIX}"
  URL="${BASE_URL}/${FILE}"
  echo "Installing $PKG..."
  wget -q -O "$TMP_DIR/$FILE" "$URL"
  opkg install "$TMP_DIR/$FILE"
done

# Запрос конфига WARP
warp_config=$(curl -s https://warp.llimonix.pw/api/warp \
  -H "Content-Type: application/json" \
  --data-raw '{"selectedServices":[],"siteMode":"all","deviceType":"computer"}')

success=$(echo "$warp_config" | jq -r '.success')
if [ "$success" != "true" ]; then
  echo "WARP config fetch failed."
  exit 1
fi

b64=$(echo "$warp_config" | jq -r '.content.configBase64')
config=$(echo "$b64" | base64 -d)

# Парсинг WARP конфига
eval $(echo "$config" | grep = | sed 's/\r//' | awk -F= '{printf "%s=\"%s\"\n", $1, $2}')

INTERFACE_NAME="awgwarp"
ZONE_NAME="awg"

# Создание UCI-конфигов
uci batch <<EOF
set network.${INTERFACE_NAME}=interface
set network.${INTERFACE_NAME}.proto='amneziawg'
set network.${INTERFACE_NAME}.private_key='${PrivateKey}'
set network.${INTERFACE_NAME}.awg_jc='${Jc}'
set network.${INTERFACE_NAME}.awg_jmin='${Jmin}'
set network.${INTERFACE_NAME}.awg_jmax='${Jmax}'
set network.${INTERFACE_NAME}.awg_s1='${S1}'
set network.${INTERFACE_NAME}.awg_s2='${S2}'
set network.${INTERFACE_NAME}.awg_h1='${H1}'
set network.${INTERFACE_NAME}.awg_h2='${H2}'
set network.${INTERFACE_NAME}.awg_h3='${H3}'
set network.${INTERFACE_NAME}.awg_h4='${H4}'
add_list network.${INTERFACE_NAME}.addresses='${Address}'
add network amneziawg_peer
set network.@amneziawg_peer[-1].description='warp_peer'
set network.@amneziawg_peer[-1].public_key='${PublicKey}'
set network.@amneziawg_peer[-1].endpoint_host='${EndpointIP}'
set network.@amneziawg_peer[-1].endpoint_port='${EndpointPort}'
set network.@amneziawg_peer[-1].allowed_ips='0.0.0.0/0'
set network.@amneziawg_peer[-1].persistent_keepalive='25'
commit network
EOF

# Настройка файрвола
if ! uci show firewall | grep -q "@zone.*name='${ZONE_NAME}'"; then
  uci add firewall zone
  uci set firewall.@zone[-1].name="$ZONE_NAME"
  uci set firewall.@zone[-1].network="$INTERFACE_NAME"
  uci set firewall.@zone[-1].input='REJECT'
  uci set firewall.@zone[-1].output='ACCEPT'
  uci set firewall.@zone[-1].forward='REJECT'
  uci set firewall.@zone[-1].masq='1'
  uci set firewall.@zone[-1].mtu_fix='1'
fi

uci add firewall forwarding
uci set firewall.@forwarding[-1].src='lan'
uci set firewall.@forwarding[-1].dest="$ZONE_NAME"
uci commit firewall

# Рестарт сети и файрвола
/etc/init.d/network restart
/etc/init.d/firewall restart

# Проверка
sleep 5
ping -I $INTERFACE_NAME -c 3 1.1.1.1 > /dev/null && echo "\033[32mAmneziaWG WARP is working.\033[0m" || echo "\033[31mWARP test failed.\033[0m"
