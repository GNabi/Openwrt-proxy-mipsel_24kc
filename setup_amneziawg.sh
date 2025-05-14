#!/bin/sh

echo "Запрашиваем конфигурацию WARP..."

warp_response=$(curl --silent --connect-timeout 15 --max-time 30 -H 'Content-Type: application/json' \
  -d '{"selectedServices":[],"siteMode":"all","deviceType":"computer"}' \
  'https://warp.llimonix.pw/api/warp')

success=$(echo "$warp_response" | jsonfilter -e '@.success')

if [ "$success" != "true" ]; then
  echo "Ошибка получения WARP конфигурации"
  exit 1
fi

config_base64=$(echo "$warp_response" | jsonfilter -e '@.content.configBase64')
warp_config=$(echo "$config_base64" | base64 -d)

# Извлекаем параметры
eval $(echo "$warp_config" | awk -F '=' '/=/{gsub(/ /, "", $1); printf("%s=\"%s\"\n", $1, $2)}')

# Обработка
Address=$(echo "$Address" | cut -d',' -f1)
DNS=$(echo "$DNS" | cut -d',' -f1)
AllowedIPs=$(echo "$AllowedIPs" | cut -d',' -f1)
EndpointIP=$(echo "$Endpoint" | cut -d':' -f1)
EndpointPort=$(echo "$Endpoint" | cut -d':' -f2)

# Применяем настройки
INTERFACE_NAME="awg10"
CONFIG_NAME="amneziawg_awg10"
ZONE_NAME="awg"

uci set network.${INTERFACE_NAME}=interface
uci set network.${INTERFACE_NAME}.proto='amneziawg'
uci set network.${INTERFACE_NAME}.private_key="$PrivateKey"
uci del network.${INTERFACE_NAME}.addresses
uci add_list network.${INTERFACE_NAME}.addresses="$Address"
uci set network.${INTERFACE_NAME}.mtu='1280'
uci set network.${INTERFACE_NAME}.awg_jc="$Jc"
uci set network.${INTERFACE_NAME}.awg_jmin="$Jmin"
uci set network.${INTERFACE_NAME}.awg_jmax="$Jmax"
uci set network.${INTERFACE_NAME}.awg_s1="$S1"
uci set network.${INTERFACE_NAME}.awg_s2="$S2"
uci set network.${INTERFACE_NAME}.awg_h1="$H1"
uci set network.${INTERFACE_NAME}.awg_h2="$H2"
uci set network.${INTERFACE_NAME}.awg_h3="$H3"
uci set network.${INTERFACE_NAME}.awg_h4="$H4"
uci set network.${INTERFACE_NAME}.nohostroute='1'

uci set network.${CONFIG_NAME}=amneziawg_peer
uci set network.${CONFIG_NAME}.public_key="$PublicKey"
uci set network.${CONFIG_NAME}.endpoint_host="$EndpointIP"
uci set network.${CONFIG_NAME}.endpoint_port="$EndpointPort"
uci set network.${CONFIG_NAME}.persistent_keepalive='25'
uci set network.${CONFIG_NAME}.allowed_ips="$AllowedIPs"
uci set network.${CONFIG_NAME}.route_allowed_ips='0'
uci commit network

/etc/init.d/network reload
sleep 5
ifup $INTERFACE_NAME

echo "AmneziaWG настроен и запущен."
