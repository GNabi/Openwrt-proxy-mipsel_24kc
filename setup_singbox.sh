#!/bin/sh

# Проверка, установлен ли sing-box
if ! command -v sing-box >/dev/null 2>&1; then
  echo "sing-box не установлен. Установите его через opkg install sing-box"
  exit 1
fi

echo "Создание конфигурации для sing-box..."

# Создание директории конфигурации, если не существует
mkdir -p /etc/sing-box

# Основной config.json
cat <<EOF > /etc/sing-box/config.json
{
  "log": {
    "disabled": true,
    "level": "error"
  },
  "inbounds": [
    {
      "type": "tproxy",
      "listen": "::",
      "listen_port": 1100,
      "sniff": false
    }
  ],
  "outbounds": [
    {
      "type": "http",
      "server": "127.0.0.1",
      "server_port": 18080
    }
  ],
  "route": {
    "auto_detect_interface": true
  }
}
EOF

# Проверка конфигурации
echo "Конфигурация записана в /etc/sing-box/config.json"
cat /etc/sing-box/config.json

# Включение и запуск сервиса
echo "Включение автозапуска и перезапуск сервиса..."
service sing-box enable
service sing-box restart

# Проверка статуса
sleep 1
if pidof sing-box >/dev/null; then
  echo "✅ sing-box запущен успешно"
else
  echo "❌ Ошибка запуска sing-box. Проверьте лог: logread -e sing-box"
fi

