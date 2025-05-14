#!/bin/sh

set -e

check_requirements() {
  echo "[+] Updating packages..."
  opkg update

  for pkg in curl jq coreutils-base64; do
    if ! opkg list-installed | grep -q "^$pkg"; then
      echo "[+] Installing $pkg..."
      opkg install "$pkg"
    fi
  done
}

install_awg() {
  echo "[+] Installing AmneziaWG packages..."
  PKGARCH=$(opkg print-architecture | awk 'BEGIN {max=0} {if ($3 > max) {max = $3; arch = $2}} END {print arch}')
  VERSION=$(ubus call system board | jsonfilter -e '@.release.version')
  TARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f 1)
  SUBTARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f 2)
  PKGPOSTFIX="_v${VERSION}_${PKGARCH}_${TARGET}_${SUBTARGET}.ipk"
  BASE_URL="https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/v${VERSION}"

  mkdir -p /tmp/amneziawg
  cd /tmp/amneziawg

  for pkg in kmod-amneziawg amneziawg-tools luci-app-amneziawg; do
    FILE="${pkg}${PKGPOSTFIX}"
    if ! opkg list-installed | grep -q "^$pkg"; then
      echo "[+] Downloading $FILE..."
      wget -q "${BASE_URL}/${FILE}" -O "$FILE"
      opkg install "$FILE"
    else
      echo "[✓] $pkg already installed"
    fi
  done
}

get_warp_config() {
  echo "[+] Getting WARP config from online service..."
  RESPONSE=$(curl -s 'https://warp.llimonix.pw/api/warp' \
    -H 'Content-Type: application/json' \
    --data-raw '{"selectedServices":[],"siteMode":"all","deviceType":"computer"}')

  echo "$RESPONSE" | jq -r '.content.configBase64' | base64 -d
}

parse_and_configure() {
  CONFIG=$(get_warp_config)

  echo "$CONFIG" > /tmp/warp.conf
  echo "[+] Parsing WARP config..."

  PRIVATE_KEY=$(grep PrivateKey /tmp/warp.conf | cut -d= -f2 | tr -d ' ')
  ADDRESS=$(grep Address /tmp/warp.conf | cut -d= -f2 | tr -d ' ')
  PUBLIC_KEY=$(grep PublicKey /tmp/warp.conf | cut -d= -f2 | tr -d ' ')
  ENDPOINT=$(grep Endpoint /tmp/warp.conf | cut -d= -f2 | tr -d ' ')
  ENDPOINT_IP=$(echo "$ENDPOINT" | cut -d: -f1)
  ENDPOINT_PORT=$(echo "$ENDPOINT" | cut -d: -f2)

  echo "[+] Applying UCI configuration..."

  uci set network.awg10=interface
  uci set network.awg10.proto='amneziawg'
  uci set network.awg10.private_key="$PRIVATE_KEY"
  uci add_list network.awg10.addresses="$ADDRESS"
  uci set network.awg10.awg_jc='3'
  uci set network.awg10.awg_jmin='30'
  uci set network.awg10.awg_jmax='40'
  uci set network.awg10.awg_s1='3'
  uci set network.awg10.awg_s2='2'
  uci set network.awg10.awg_h1='1'
  uci set network.awg10.awg_h2='2'
  uci set network.awg10.awg_h3='3'
  uci set network.awg10.awg_h4='4'
  uci set network.awg10.nohostroute='1'

  uci add network amneziawg_awg10
  uci set network.@amneziawg_awg10[-1].name='awg10_peer'
  uci set network.@amneziawg_awg10[-1].public_key="$PUBLIC_KEY"
  uci set network.@amneziawg_awg10[-1].endpoint_host="$ENDPOINT_IP"
  uci set network.@amneziawg_awg10[-1].endpoint_port="$ENDPOINT_PORT"
  uci set network.@amneziawg_awg10[-1].persistent_keepalive='25'
  uci set network.@amneziawg_awg10[-1].allowed_ips='0.0.0.0/0'
  uci commit network

  if ! uci show firewall | grep -q "@zone.*name='awg'"; then
    uci add firewall zone
    uci set firewall.@zone[-1].name='awg'
    uci set firewall.@zone[-1].network='awg10'
    uci set firewall.@zone[-1].input='REJECT'
    uci set firewall.@zone[-1].output='ACCEPT'
    uci set firewall.@zone[-1].forward='REJECT'
    uci set firewall.@zone[-1].masq='1'
    uci set firewall.@zone[-1].mtu_fix='1'
    uci commit firewall
  fi

  if ! uci show firewall | grep -q "@forwarding.*dest='awg'"; then
    uci add firewall forwarding
    uci set firewall.@forwarding[-1].src='lan'
    uci set firewall.@forwarding[-1].dest='awg'
    uci commit firewall
  fi
}

restart_services() {
  echo "[+] Restarting services..."
  /etc/init.d/network restart
  /etc/init.d/firewall restart
}

main() {
  check_requirements
  install_awg
  parse_and_configure
  restart_services
  echo "[✓] AmneziaWG auto-configuration completed"
}

main
