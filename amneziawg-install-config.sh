#!/bin/sh

set -e

# Цветные сообщения
green() {
  echo "\033[32m$1\033[0m"
}
red() {
  echo "\033[31m$1\033[0m"
}

### Проверка репозитория OpenWrt ###
check_repo() {
  green "🔄 Обновление списка пакетов..."
  if ! opkg update; then
    red "❌ Ошибка обновления opkg. Проверьте подключение к интернету или дату (выполните ntpd -p ptbtime1.ptb.de)"
    exit 1
  fi
}

### Установка пакетов AmneziaWG ###
install_awg_packages() {
  PKGARCH=$(opkg print-architecture | awk 'BEGIN {max=0} {if ($3 > max) {max = $3; arch = $2}} END {print arch}')
  TARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f 1)
  SUBTARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f 2)
  VERSION=$(ubus call system board | jsonfilter -e '@.release.version')
  BASE_URL="https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/v${VERSION}"

  mkdir -p /tmp/amneziawg

  for pkg in kmod-amneziawg amneziawg-tools luci-app-amneziawg; do
    FILE="${pkg}_v${VERSION}_${PKGARCH}_${TARGET}_${SUBTARGET}.ipk"
    URL="${BASE_URL}/${FILE}"
    if opkg list-installed | grep -q "$pkg"; then
      green "$pkg уже установлен"
    else
      green "⬇️ Загрузка и установка $pkg"
      wget -O "/tmp/amneziawg/${FILE}" "$URL" || { red "❌ Не удалось скачать $pkg"; exit 1; }
      opkg install "/tmp/amneziawg/${FILE}" || { red "❌ Ошибка установки $pkg"; exit 1; }
    fi
  done
}

### Получение конфигурации WARP ###
fetch_warp_config() {
  green "🌐 Получение WARP-конфигурации..."
  response=$(curl -s 'https://warp.llimonix.pw/api/warp' -H 'Content-Type: application/json' --data-raw '{"siteMode":"all"}')
  success=$(echo "$response" | grep -o '"success":true')
  if [ -n "$success" ]; then
    echo "$response" | jq -r '.content.configBase64' | base64 -d
  else
    red "❌ Не удалось получить WARP-конфигурацию"
    exit 1
  fi
}

### Настройка интерфейса AmneziaWG ###
configure_awg_interface() {
  WARP_CFG=$(fetch_warp_config)

  eval "$(echo "$WARP_CFG" | sed 's/ *= */=/' | while read -r line; do
    key=$(echo "$line" | cut -d= -f1)
    val=$(echo "$line" | cut -d= -f2-)
    echo "$key="$val""
  done)"

  INTERFACE_NAME="awg10"
  CONFIG_NAME="amneziawg_awg10"
  ZONE_NAME="awg"

  uci set network.${INTERFACE_NAME}=interface
  uci set network.${INTERFACE_NAME}.proto='amneziawg'
  uci set network.${INTERFACE_NAME}.private_key="$PrivateKey"
  uci set network.${INTERFACE_NAME}.addresses="$(echo "$Address" | cut -d',' -f1)"
  uci set network.${INTERFACE_NAME}.awg_jc="$Jc"
  uci set network.${INTERFACE_NAME}.awg_jmin="$Jmin"
  uci set network.${INTERFACE_NAME}.awg_jmax="$Jmax"
  uci set network.${INTERFACE_NAME}.awg_s1="$S1"
  uci set network.${INTERFACE_NAME}.awg_s2="$S2"
  uci set network.${INTERFACE_NAME}.awg_h1="$H1"
  uci set network.${INTERFACE_NAME}.awg_h2="$H2"
  uci set network.${INTERFACE_NAME}.awg_h3="$H3"
  uci set network.${INTERFACE_NAME}.awg_h4="$H4"
  uci set network.${INTERFACE_NAME}.mtu=1280

  uci add network "${CONFIG_NAME}" || true
  uci set network.@${CONFIG_NAME}[-1].public_key="$PublicKey"
  uci set network.@${CONFIG_NAME}[-1].endpoint_host="$(echo "$Endpoint" | cut -d: -f1)"
  uci set network.@${CONFIG_NAME}[-1].endpoint_port="$(echo "$Endpoint" | cut -d: -f2)"
  uci set network.@${CONFIG_NAME}[-1].allowed_ips='0.0.0.0/0'
  uci set network.@${CONFIG_NAME}[-1].persistent_keepalive='25'
  uci commit network

  green "✅ Интерфейс AmneziaWG настроен"

  # Настройка фаервола
  if ! uci show firewall | grep -q "@zone.*name='${ZONE_NAME}'"; then
    uci add firewall zone
    uci set firewall.@zone[-1].name=$ZONE_NAME
    uci set firewall.@zone[-1].network=$INTERFACE_NAME
    uci set firewall.@zone[-1].forward='REJECT'
    uci set firewall.@zone[-1].output='ACCEPT'
    uci set firewall.@zone[-1].input='REJECT'
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

  green "✅ Фаервол настроен"
}

### Проверка подключения ###
check_connection() {
  green "⏳ Проверка VPN-подключения..."
  ifdown awg10
  sleep 3
  ifup awg10
  sleep 7

  if ping -I awg10 -c 1 8.8.8.8 >/dev/null 2>&1; then
    green "✅ Подключение работает через awg10"
  else
    red "❌ VPN через awg10 не работает. Проверьте конфигурацию"
  fi
}

### Выполнение ###
check_repo
install_awg_packages
configure_awg_interface
check_connection

green "🎉 Готово. AmneziaWG установлен и настроен."
