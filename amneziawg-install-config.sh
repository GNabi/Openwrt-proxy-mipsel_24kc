#!/bin/sh

# 1. Установка необходимых пакетов для AmneziaWG
opkg update
# Определяем архитектуру, цель (target) и версию прошивки OpenWrt:contentReference[oaicite:9]{index=9}
PKGARCH="$(opkg print-architecture | awk 'BEGIN {max=0} {if ($3>max){max=$3; arch=$2}} END {print arch}')"
TARGET="$(ubus call system board | jsonfilter -e '@.release.target' | cut -d'/' -f1)"
SUBTARGET="$(ubus call system board | jsonfilter -e '@.release.target' | cut -d'/' -f2)"
VERSION="$(ubus call system board | jsonfilter -e '@.release.version')"
PKGPOSTFIX="_v${VERSION}_${PKGARCH}_${TARGET}_${SUBTARGET}.ipk"
BASE_URL="https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/v${VERSION}/"
DOWNLOAD_DIR="/tmp/amneziawg"
mkdir -p "$DOWNLOAD_DIR"

# Установка kmod-amneziawg (модуль ядра WireGuard с поддержкой AmneziaWG)
if opkg list-installed | grep -q '^kmod-amneziawg'; then
    echo "kmod-amneziawg уже установлен."
else
    KMOD_FILE="kmod-amneziawg${PKGPOSTFIX}"
    echo "Скачиваем пакет $KMOD_FILE..."
    wget -q -O "$DOWNLOAD_DIR/$KMOD_FILE" "${BASE_URL}${KMOD_FILE}"
    if [ $? -ne 0 ]; then
        echo "Ошибка: не удалось загрузить $KMOD_FILE. Установите kmod-amneziawg вручную и повторите."
        exit 1
    fi
    opkg install "$DOWNLOAD_DIR/$KMOD_FILE" || { echo "Ошибка установки $KMOD_FILE."; exit 1; }
fi

# Установка amneziawg-tools (пользовательские инструменты AmneziaWG)
if opkg list-installed | grep -q '^amneziawg-tools'; then
    echo "amneziawg-tools уже установлен."
else
    TOOLS_FILE="amneziawg-tools${PKGPOSTFIX}"
    echo "Скачиваем пакет $TOOLS_FILE..."
    wget -q -O "$DOWNLOAD_DIR/$TOOLS_FILE" "${BASE_URL}${TOOLS_FILE}"
    if [ $? -ne 0 ]; then
        echo "Ошибка: не удалось загрузить $TOOLS_FILE. Установите amneziawg-tools вручную и повторите."
        exit 1
    fi
    opkg install "$DOWNLOAD_DIR/$TOOLS_FILE" || { echo "Ошибка установки $TOOLS_FILE."; exit 1; }
fi

# Установка luci-app-amneziawg (web-интерфейс LuCI для управления AmneziaWG)
if opkg list-installed | grep -q '^luci-app-amneziawg'; then
    echo "luci-app-amneziawg уже установлен."
else
    LUCI_FILE="luci-app-amneziawg${PKGPOSTFIX}"
    echo "Скачиваем пакет $LUCI_FILE..."
    wget -q -O "$DOWNLOAD_DIR/$LUCI_FILE" "${BASE_URL}${LUCI_FILE}"
    if [ $? -ne 0 ]; then
        echo "Ошибка: не удалось загрузить $LUCI_FILE. Установите luci-app-amneziawg вручную и повторите."
        exit 1
    fi
    opkg install "$DOWNLOAD_DIR/$LUCI_FILE" || { echo "Ошибка установки $LUCI_FILE."; exit 1; }
fi

# 2. Получение конфигурации Cloudflare WARP
WARP_CONF="/tmp/warp.conf"
rm -f "$WARP_CONF"
# Последовательно пробуем несколько сервисов генерации WARP-конфига:contentReference[oaicite:10]{index=10}
for url in \
    "https://warp.llimonix.pw/api/warp" \
    "https://topor-warp.vercel.app/generate" \
    "https://warp-gen.vercel.app/generate-config" \
    "https://config-generator-warp.vercel.app/warp"
do
    echo "Запрос конфигурации WARP: $url"
    wget -q -O "$WARP_CONF" "$url"
    if [ $? -eq 0 ] && grep -q "PrivateKey" "$WARP_CONF"; then
        echo "WARP-конфигурация получена с $url"
        break
    fi
    # Если не удалось получить или конфиг некорректен, очищаем и пробуем следующий
    rm -f "$WARP_CONF"
done

if [ ! -f "$WARP_CONF" ]; then
    echo "Ошибка: не удалось получить WARP-конфиг ни с одного из сервисов."
    exit 1
fi

# 3. Настройка интерфейса AmneziaWG (awg0) на основе полученного конфига
echo "Настраиваем интерфейс AmneziaWG (awg0)..."
# Извлекаем параметры [Interface] из конфигурации
PRIVATE_KEY="$(sed -n 's/^PrivateKey *= *//p' "$WARP_CONF")"
ADDRESS_LINE="$(sed -n 's/^Address *= *//p' "$WARP_CONF")"
# Заменяем запятую на пробел (если указано несколько адресов IPv4/IPv6)
ADDRESS="$(echo "$ADDRESS_LINE" | sed 's/, */ /g')"
JC="$(sed -n 's/^Jc *= *//p' "$WARP_CONF")"
JMIN="$(sed -n 's/^Jmin *= *//p' "$WARP_CONF")"
JMAX="$(sed -n 's/^Jmax *= *//p' "$WARP_CONF")"
S1="$(sed -n 's/^S1 *= *//p' "$WARP_CONF")"
S2="$(sed -n 's/^S2 *= *//p' "$WARP_CONF")"
H1="$(sed -n 's/^H1 *= *//p' "$WARP_CONF")"
H2="$(sed -n 's/^H2 *= *//p' "$WARP_CONF")"
H3="$(sed -n 's/^H3 *= *//p' "$WARP_CONF")"
H4="$(sed -n 's/^H4 *= *//p' "$WARP_CONF")"
# Извлекаем параметры [Peer] из конфигурации
PUBLIC_KEY="$(sed -n 's/^PublicKey *= *//p' "$WARP_CONF")"
ALLOWED_IPS="$(sed -n 's/^AllowedIPs *= *//p' "$WARP_CONF")"
ENDPOINT="$(sed -n 's/^Endpoint *= *//p' "$WARP_CONF")"
PRESHARED_KEY="$(sed -n 's/^PresharedKey *= *//p' "$WARP_CONF")"

# Разбиваем Endpoint на хост и порт (учитывая возможный IPv6 в квадратных скобках)
if echo "$ENDPOINT" | grep -q '\]:'; then
    # Формат [IPv6]:PORT
    ENDPOINT_HOST="$(echo "$ENDPOINT" | sed -r 's/^\[([^]]+)\]:.*$/\1/')"
    ENDPOINT_PORT="$(echo "$ENDPOINT" | sed -r 's/^\[[^]]+\]:(.*)$/\1/')"
else
    # Формат IPv4:PORT или hostname:PORT
    ENDPOINT_HOST="${ENDPOINT%%:*}"
    ENDPOINT_PORT="${ENDPOINT##*:}"
fi

# Удаляем старую конфигурацию awg0, если существует, чтобы избежать дублирования
uci -q delete network.awg0
while uci -q delete network.@amneziawg_awg0[0]; do :; done

# Создаем интерфейс awg0 типа 'amneziawg' и задаем параметры:contentReference[oaicite:11]{index=11}
uci set network.awg0="interface"
uci set network.awg0.proto="amneziawg"
uci set network.awg0.private_key="$PRIVATE_KEY"
uci set network.awg0.addresses="$ADDRESS"
uci set network.awg0.listen_port="51820"
uci set network.awg0.awg_jc="$JC"
uci set network.awg0.awg_jmin="$JMIN"
uci set network.awg0.awg_jmax="$JMAX"
uci set network.awg0.awg_s1="$S1"
uci set network.awg0.awg_s2="$S2"
uci set network.awg0.awg_h1="$H1"
uci set network.awg0.awg_h2="$H2"
uci set network.awg0.awg_h3="$H3"
uci set network.awg0.awg_h4="$H4"
uci set network.awg0.auto="1"    # включаем автозапуск интерфейса при загрузке

# Добавляем peer (WireGuard Peer) для awg0 с параметрами сервера WARP:contentReference[oaicite:12]{index=12}
uci add network amneziawg_awg0
uci set network.@amneziawg_awg0[-1].name="awg0_warp_peer"
uci set network.@amneziawg_awg0[-1].public_key="$PUBLIC_KEY"
[ -n "$PRESHARED_KEY" ] && uci set network.@amneziawg_awg0[-1].preshared_key="$PRESHARED_KEY"
uci set network.@amneziawg_awg0[-1].route_allowed_ips="0"
uci set network.@amneziawg_awg0[-1].persistent_keepalive="25"
uci set network.@amneziawg_awg0[-1].endpoint_host="$ENDPOINT_HOST"
uci set network.@amneziawg_awg0[-1].endpoint_port="$ENDPOINT_PORT"
uci set network.@amneziawg_awg0[-1].allowed_ips="$ALLOWED_IPS"

# 4. Настройка firewall: создаем зону 'awg' и разрешаем трафик LAN->AWG
echo "Настраиваем firewall-зону 'awg'..."
# Удаляем старую зону/правила awg, если они были
old_zone_idx="$(uci show firewall | grep -m1 -E "@zone.*name='awg'" | sed -r "s/^firewall\.@zone\[([0-9]+)\].*$/\1/")"
[ -n "$old_zone_idx" ] && uci delete firewall.@zone["$old_zone_idx"]
old_fwd_idx="$(uci show firewall | grep -m1 -E "@forwarding.*src='lan'.*dest='awg'" | sed -r "s/^firewall\.@forwarding\[([0-9]+)\].*$/\1/")"
[ -n "$old_fwd_idx" ] && uci delete firewall.@forwarding["$old_fwd_idx"]

# Добавляем новую зону 'awg' в файервол:contentReference[oaicite:13]{index=13}
uci add firewall zone
uci set firewall.@zone[-1].name="awg"
uci set firewall.@zone[-1].network="awg0"
uci set firewall.@zone[-1].input="REJECT"
uci set firewall.@zone[-1].output="ACCEPT"
uci set firewall.@zone[-1].forward="REJECT"
uci set firewall.@zone[-1].masq="1"
uci set firewall.@zone[-1].mtu_fix="1"
uci set firewall.@zone[-1].family="ipv4"

# Разрешаем форвардинг с LAN в зону AWG (LAN -> AWG):contentReference[oaicite:14]{index=14}
uci add firewall forwarding
uci set firewall.@forwarding[-1].src="lan"
uci set firewall.@forwarding[-1].dest="awg"
uci set firewall.@forwarding[-1].name="lan_to_awg"
uci set firewall.@forwarding[-1].family="ipv4"

# Применяем конфигурации и перезапускаем службы сети и фаервола
uci commit network
uci commit firewall
/etc/init.d/network restart
/etc/init.d/firewall restart

# Тестируем подключение через новый интерфейс (ping 8.8.8.8 с исходящим интерфейсом awg0)
echo "Проверка VPN-подключения (ping через awg0)..."
if ping -I awg0 -c4 8.8.8.8 >/dev/null 2>&1; then
    echo "✅ Настройка AmneziaWG завершена успешно! Трафик LAN направлен через Cloudflare WARP."
else
    echo "⚠️ Интерфейс AmneziaWG настроен, но тестовый ping не получил ответ. Проверьте конфигурацию."
fi
