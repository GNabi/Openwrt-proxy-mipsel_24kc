#!/bin/sh

set -e

# Цвета для вывода
GREEN="\033[32;1m"
RESET="\033[0m"

log() {
  printf "${GREEN}%s${RESET}\n" "$1"
}

check_repo() {
  log "Проверка подключения к репозиториям OpenWRT..."
  opkg update | grep -q "Failed to download" && {
    log "Ошибка opkg. Проверьте интернет или дату. Попробуй: ntpd -p ptbtime1.ptb.de"
    exit 1
  }
}

install_awg_packages() {
  PKGARCH=$(opkg print-architecture | awk 'BEGIN {max=0} {if ($3 > max) {max=$3; arch=$2}} END {print arch}')
  TARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f 1)
  SUBTARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f 2)
  VERSION=$(ubus call system board | jsonfilter -e '@.release.version')
  PKGPOSTFIX="_v${VERSION}_${PKGARCH}_${TARGET}_${SUBTARGET}.ipk"
  BASE_URL="https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/v${VERSION}"

  mkdir -p /tmp/awg
  for pkg in kmod-amneziawg amneziawg-tools luci-app-amneziawg; do
    FILENAME="${pkg}${PKGPOSTFIX}"
    wget -O "/tmp/awg/$FILENAME" "$BASE_URL/$FILENAME" || { echo "Ошибка загрузки $FILENAME"; exit 1; }
    opkg install "/tmp/awg/$FILENAME" || { echo "Ошибка установки $FILENAME"; exit 1; }
  done
  rm -rf /tmp/awg
}

fetch_warp_config() {
  log "Получение WARP-конфигурации..."
  response=$(curl -s https://warp.llimonix.pw/api/warp --data-raw '{"selectedServices":[],"siteMode":"all","deviceType":"computer"}')
  config=$(echo "$response" | grep -o '"configBase64":"[^"]*' | cut -d '"' -f4)
  echo "$config" | base64 -d
}

configure_awg_interface() {
  config=$(fetch_warp_config)
  eval $(echo "$config" | grep =)

  INTERFACE_NAME="awg10"
  CONFIG_NAME="amneziawg_awg10"
  ZONE_NAME="awg"

  uci set network.${INTERFACE_NAME}=interface
  uci set network.${INTERFACE_NAME}.proto=amneziawg
  uci set network.${INTERFACE_NAME}.private_key="$PrivateKey"
  uci del network.${INTERFACE_NAME}.addresses
  uci add_list network.${INTERFACE_NAME}.addresses="$(echo "$Address" | cut -d',' -f1)"
  uci set network.${INTERFACE_NAME}.awg_jc="$Jc"
  uci set network.${INTERFACE_NAME}.awg_jmin="$Jmin"
  uci set network.${INTERFACE_NAME}.awg_jmax="$Jmax"
  uci set network.${INTERFACE_NAME}.awg_s1="$S1"
  uci set network.${INTERFACE_NAME}.awg_s2="$S2"
  uci set network.${INTERFACE_NAME}.awg_h1="$H1"
  uci set network.${INTERFACE_NAME}.awg_h2="$H2"
  uci set network.${INTERFACE_NAME}.awg_h3="$H3"
  uci set network.${INTERFACE_NAME}.awg_h4="$H4"

  if ! uci show network | grep -q ${CONFIG_NAME}; then
    uci add network ${CONFIG_NAME} >/dev/null
  fi

  uci set network.@${CONFIG_NAME}[-1].public_key="$PublicKey"
  uci set network.@${CONFIG_NAME}[-1].endpoint_host="$(echo "$Endpoint" | cut -d: -f1)"
  uci set network.@${CONFIG_NAME}[-1].endpoint_port="$(echo "$Endpoint" | cut -d: -f2)"
  uci set network.@${CONFIG_NAME}[-1].allowed_ips='0.0.0.0/0'
  uci set network.@${CONFIG_NAME}[-1].persistent_keepalive='25'
  uci set network.@${CONFIG_NAME}[-1].route_allowed_ips='0'
  uci commit network

  if ! uci show firewall | grep -q "@zone.*name='${ZONE_NAME}'"; then
    uci add firewall zone
    uci set firewall.@zone[-1].name=$ZONE_NAME
    uci set firewall.@zone[-1].network=$INTERFACE_NAME
    uci set firewall.@zone[-1].input='REJECT'
    uci set firewall.@zone[-1].output='ACCEPT'
    uci set firewall.@zone[-1].forward='REJECT'
    uci set firewall.@zone[-1].masq='1'
    uci set firewall.@zone[-1].mtu_fix='1'
    uci commit firewall
  fi

  if ! uci show firewall | grep -q "@forwarding.*dest='${ZONE_NAME}'"; then
    uci add firewall forwarding
    uci set firewall.@forwarding[-1].src='lan'
    uci set firewall.@forwarding[-1].dest=$ZONE_NAME
    uci commit firewall
  fi

  /etc/init.d/network restart
}

check_connection() {
  sleep 5
  ping -I awg10 -c 2 8.8.8.8 >/dev/null 2>&1 && {
    log "WARP подключение успешно работает через awg10"
  } || {
    log "❌ WARP не подключился"
  }
}

### Выполнение ###
check_repo
install_awg_packages
configure_awg_interface
check_connection
