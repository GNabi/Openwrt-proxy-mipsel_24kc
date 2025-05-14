#!/bin/sh

set -e

check_repo() {
    printf "\033[32;1mChecking OpenWrt repo availability...\033[0m\n"
    opkg update | grep -q "Failed to download" && {
        printf "\033[31;1mOPKG failed. Check internet or date.\nForce sync: ntpd -p ptbtime1.ptb.de\033[0m\n"
        exit 1
    }
}

install_awg_packages() {
    PKGARCH=$(opkg print-architecture | awk 'BEGIN {max=0} {if ($3 > max) {max = $3; arch = $2}} END {print arch}')
    TARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f 1)
    SUBTARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f 2)
    VERSION=$(ubus call system board | jsonfilter -e '@.release.version')
    PKGPOSTFIX="_v${VERSION}_${PKGARCH}_${TARGET}_${SUBTARGET}.ipk"
    BASE_URL="https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/"

    AWG_DIR="/tmp/amneziawg"
    mkdir -p "$AWG_DIR"

    for pkg in kmod-amneziawg amneziawg-tools luci-app-amneziawg; do
        if opkg list-installed | grep -q "$pkg"; then
            echo "$pkg already installed"
        else
            FILENAME="${pkg}${PKGPOSTFIX}"
            DOWNLOAD_URL="${BASE_URL}v${VERSION}/${FILENAME}"
            wget -O "$AWG_DIR/$FILENAME" "$DOWNLOAD_URL" || {
                echo "Error downloading $pkg. Please install manually."
                exit 1
            }
            opkg install "$AWG_DIR/$FILENAME" || {
                echo "Error installing $pkg."
                exit 1
            }
        fi
    done

    rm -rf "$AWG_DIR"
}

auto_configure_amneziawg_interface() {
    printf "\033[32;1mAuto-configuring AmneziaWG WARP...\033[0m\n"

    warp_response=$(curl -s --connect-timeout 15 --max-time 30 \
      -H 'Content-Type: application/json' \
      -d '{"selectedServices":[],"siteMode":"all","deviceType":"computer"}' \
      'https://warp.llimonix.pw/api/warp')

    success=$(echo "$warp_response" | jsonfilter -e '@.success')
    [ "$success" != "true" ] && {
        echo "\033[31;1mFailed to fetch WARP config\033[0m"
        exit 1
    }

    config_base64=$(echo "$warp_response" | jsonfilter -e '@.content.configBase64')
    warp_config=$(echo "$config_base64" | base64 -d)

    eval $(echo "$warp_config" | awk -F '=' '/=/{gsub(/ /, "", $1); printf("%s=\"%s\"\n", $1, $2)}')

    Address=$(echo "$Address" | cut -d',' -f1)
    EndpointIP=$(echo "$Endpoint" | cut -d':' -f1)
    EndpointPort=$(echo "$Endpoint" | cut -d':' -f2)

    INTERFACE_NAME="awg1"
    CONFIG_NAME="amneziawg_awg1"
    ZONE_NAME="awg1"

    uci set network.${INTERFACE_NAME}=interface
    uci set network.${INTERFACE_NAME}.proto='amneziawg'
    uci set network.${INTERFACE_NAME}.private_key="$PrivateKey"
    uci del network.${INTERFACE_NAME}.addresses
    uci add_list network.${INTERFACE_NAME}.addresses="$Address"
    uci set network.${INTERFACE_NAME}.awg_jc="$Jc"
    uci set network.${INTERFACE_NAME}.awg_jmin="$Jmin"
    uci set network.${INTERFACE_NAME}.awg_jmax="$Jmax"
    uci set network.${INTERFACE_NAME}.awg_s1="$S1"
    uci set network.${INTERFACE_NAME}.awg_s2="$S2"
    uci set network.${INTERFACE_NAME}.awg_h1="$H1"
    uci set network.${INTERFACE_NAME}.awg_h2="$H2"
    uci set network.${INTERFACE_NAME}.awg_h3="$H3"
    uci set network.${INTERFACE_NAME}.awg_h4="$H4"

    uci set network.${CONFIG_NAME}=amneziawg_peer
    uci set network.${CONFIG_NAME}.public_key="$PublicKey"
    uci set network.${CONFIG_NAME}.endpoint_host="$EndpointIP"
    uci set network.${CONFIG_NAME}.endpoint_port="$EndpointPort"
    uci set network.${CONFIG_NAME}.persistent_keepalive='25'
    uci set network.${CONFIG_NAME}.allowed_ips='0.0.0.0/0'
    uci set network.${CONFIG_NAME}.route_allowed_ips='0'
    uci commit network

    if ! uci show firewall | grep -q "@zone.*name='${ZONE_NAME}'"; then
        uci add firewall zone
        uci set firewall.@zone[-1].name=$ZONE_NAME
        uci set firewall.@zone[-1].network=$INTERFACE_NAME
        uci set firewall.@zone[-1].forward='REJECT'
        uci set firewall.@zone[-1].output='ACCEPT'
        uci set firewall.@zone[-1].input='REJECT'
        uci set firewall.@zone[-1].masq='1'
        uci set firewall.@zone[-1].mtu_fix='1'
        uci set firewall.@zone[-1].family='ipv4'
        uci commit firewall
    fi

    ifup $INTERFACE_NAME
    echo "\033[32;1mAmneziaWG WARP is up.\033[0m"
}

check_repo
install_awg_packages
auto_configure_amneziawg_interface
service network restart
