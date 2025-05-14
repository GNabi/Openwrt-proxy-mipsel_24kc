#!/bin/sh

INTERFACE_NAME="awg10"
CONFIG_NAME="amneziawg_awg10"
ZONE_NAME="awg"

# Пример значений, замени на реальные
PrivateKey="REPLACE_WITH_PRIVATE_KEY"
Address="192.168.100.2/24"
MTU="1280"

S1="200"
S2="400"
Jc="500"
Jmin="100"
Jmax="1000"
H1="cdn.cloudflare.com"
H2="speed.cloudflare.com"
H3="one.one.one.one"
H4="dns.cloudflare.com"

PublicKey="REPLACE_WITH_PUBLIC_KEY"
EndpointIP="warp.example.com"
EndpointPort="51820"

# Настройка интерфейса AmneziaWG
uci set network.${INTERFACE_NAME}=interface
uci set network.${INTERFACE_NAME}.proto='amneziawg'
uci set network.${INTERFACE_NAME}.private_key="$PrivateKey"
uci del network.${INTERFACE_NAME}.addresses
uci add_list network.${INTERFACE_NAME}.addresses="$Address"
uci set network.${INTERFACE_NAME}.mtu="$MTU"
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

# Настройка peer
uci add network $CONFIG_NAME
uci set network.@$CONFIG_NAME[-1].description="${INTERFACE_NAME}_peer"
uci set network.@$CONFIG_NAME[-1].public_key="$PublicKey"
uci set network.@$CONFIG_NAME[-1].endpoint_host="$EndpointIP"
uci set network.@$CONFIG_NAME[-1].endpoint_port="$EndpointPort"
uci set network.@$CONFIG_NAME[-1].persistent_keepalive='25'
uci set network.@$CONFIG_NAME[-1].allowed_ips='0.0.0.0/0'
uci set network.@$CONFIG_NAME[-1].route_allowed_ips='0'
uci commit network

# Настройка firewall зоны
if ! uci show firewall | grep -q "@zone.*name='${ZONE_NAME}'"; then
  uci add firewall zone
  uci set firewall.@zone[-1].name="$ZONE_NAME"
  uci set firewall.@zone[-1].network="$INTERFACE_NAME"
  uci set firewall.@zone[-1].forward='REJECT'
  uci set firewall.@zone[-1].output='ACCEPT'
  uci set firewall.@zone[-1].input='REJECT'
  uci set firewall.@zone[-1].masq='1'
  uci set firewall.@zone[-1].mtu_fix='1'
  uci set firewall.@zone[-1].family='ipv4'
fi

# Проброс из LAN в зону AWG
if ! uci show firewall | grep -q "@forwarding.*dest='${ZONE_NAME}'"; then
  uci add firewall forwarding
  uci set firewall.@forwarding[-1].src='lan'
  uci set firewall.@forwarding[-1].dest="$ZONE_NAME"
  uci set firewall.@forwarding[-1].family='ipv4'
fi

uci commit firewall

# Применение конфигурации
/etc/init.d/network restart
/etc/init.d/firewall restart

# Поднять интерфейс вручную
ifup $INTERFACE_NAME
