#!/bin/bash

# Идемпотентный скрипт настройки двух LTE модемов с балансировкой нагрузки
# Для Orange Pi с модемами Fibocom L850-GL

echo "=== Настройка прокси-фермы с двумя модемами ==="

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Запустите скрипт с правами root (sudo)${NC}"
    exit 1
fi

# Конфигурация
APN="internet"  # Замените на APN вашего оператора
EXPECTED_MODEMS=2  # Ожидаемое количество модемов (0 = ждать стабилизации)

echo -e "${YELLOW}Шаг 1: Установка необходимых пакетов${NC}"
# check last apt update time (проверяем время модификации /var/lib/apt/lists)
APT_CACHE_AGE=86400  # 24 часа в секундах
LAST_UPDATE=$(stat -c %Y /var/lib/apt/lists 2>/dev/null || echo 0)
CURRENT_TIME=$(date +%s)
TIME_DIFF=$((CURRENT_TIME - LAST_UPDATE))

if [ $TIME_DIFF -gt $APT_CACHE_AGE ]; then
    echo "Кэш apt устарел ($(($TIME_DIFF / 3600)) ч), обновляем..."
    apt update
else
    echo "Кэш apt актуален (обновлён $(($TIME_DIFF / 3600)) ч назад), пропускаем apt update"
fi

# check if packages are installed
REQUIRED_PACKAGES=(modemmanager network-manager usb-modeswitch libqmi-utils libmbim-utils iproute2 iptables-persistent)
MISSING_PACKAGES=()
for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! dpkg -s "$pkg" &> /dev/null; then
        MISSING_PACKAGES+=("$pkg")
    fi
done

if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    echo "Установка отсутствующих пакетов: ${MISSING_PACKAGES[*]}"
    apt install -y "${MISSING_PACKAGES[@]}"
fi

echo -e "${YELLOW}Шаг 2: Определение модемов${NC}"
# Перезапуск ModemManager для обновления состояния
systemctl restart ModemManager

# Ждём запуска сервиса
for i in {1..10}; do
    if systemctl is-active --quiet ModemManager; then
        break
    fi
    echo "Ожидание запуска ModemManager... ($i)"
    sleep 2
done

# Функция подсчёта модемов
count_modems() {
    local count
    count=$(mmcli -L 2>/dev/null | grep -c '/Modem/') || true
    echo "${count:-0}"
}

# Ожидание обнаружения модемов
TIMEOUT=60          # Максимальное время ожидания (сек)
STABLE_TIME=5       # Время стабильности (сек) — если количество не меняется
PREV_COUNT=0
STABLE_COUNT=0
ELAPSED=0

echo "Ожидание обнаружения модемов..."

while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
    CURRENT_COUNT=$(count_modems)

    if [ "$CURRENT_COUNT" -ne "$PREV_COUNT" ]; then
        # Количество изменилось — сбрасываем счётчик стабильности
        echo "  Обнаружено модемов: $CURRENT_COUNT"
        PREV_COUNT=$CURRENT_COUNT
        STABLE_COUNT=0
    else
        STABLE_COUNT=$((STABLE_COUNT + 1))
    fi

    # Если задано ожидаемое количество и оно достигнуто — выходим
    if [ "$EXPECTED_MODEMS" -gt 0 ] && [ "$CURRENT_COUNT" -ge "$EXPECTED_MODEMS" ]; then
        echo "  Найдено ожидаемое количество модемов: $CURRENT_COUNT"
        break
    fi

    # Если количество стабильно STABLE_TIME секунд и есть хотя бы один модем
    if [ "$STABLE_COUNT" -ge "$STABLE_TIME" ] && [ "$CURRENT_COUNT" -gt 0 ]; then
        echo "  Количество модемов стабильно: $CURRENT_COUNT"
        break
    fi

    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

mmcli -L

# Получаем номера модемов
MODEM1=$(mmcli -L | grep -oP '/Modem/\K[0-9]+' | sed -n '1p')
MODEM2=$(mmcli -L | grep -oP '/Modem/\K[0-9]+' | sed -n '2p')

MODEM_COUNT=$(count_modems)
if [ "$MODEM_COUNT" -lt 2 ]; then
    echo -e "${RED}Найдено модемов: $MODEM_COUNT (нужно минимум 2)${NC}"
    echo "Проверьте подключение модемов и USB-кабели"
    exit 1
fi

echo -e "${GREEN}Найдены модемы: $MODEM1 и $MODEM2${NC}"

echo -e "${YELLOW}Шаг 3: Настройка подключений через NetworkManager${NC}"

# Убеждаемся, что NetworkManager управляет модемами
systemctl enable --now NetworkManager 2>/dev/null || true

# Функция для получения device-id модема (уникальный идентификатор)
get_modem_device_id() {
    local MODEM=$1
    mmcli -m $MODEM | grep -oP "device-id:\s+\K\S+" || echo ""
}

# Функция для получения primary port модема
get_modem_primary_port() {
    local MODEM=$1
    mmcli -m $MODEM | grep -oP "primary port:\s+\K\S+" || echo ""
}

# Функция для создания/обновления NM connection
setup_nm_connection() {
    local MODEM=$1
    local CON_NAME=$2

    echo "Настройка подключения $CON_NAME для модема $MODEM..."

    # Получаем device-id для привязки к конкретному модему
    local DEVICE_ID=$(get_modem_device_id $MODEM)
    local PRIMARY_PORT=$(get_modem_primary_port $MODEM)
    echo "  Device ID: $DEVICE_ID"
    echo "  Primary port: $PRIMARY_PORT"

    # Удаляем старое подключение если есть
    nmcli connection delete "$CON_NAME" 2>/dev/null || true

    # Создаём новое GSM подключение с привязкой к device-id
    if [ -n "$DEVICE_ID" ]; then
        nmcli connection add \
            type gsm \
            con-name "$CON_NAME" \
            ifname "*" \
            gsm.apn "$APN" \
            gsm.device-id "$DEVICE_ID" \
            connection.autoconnect yes \
            ipv4.method auto \
            ipv6.method disabled
    else
        # Fallback: используем primary port
        nmcli connection add \
            type gsm \
            con-name "$CON_NAME" \
            ifname "$PRIMARY_PORT" \
            gsm.apn "$APN" \
            connection.autoconnect yes \
            ipv4.method auto \
            ipv6.method disabled
    fi

    echo "  Подключение создано, активируем..."

    # Активируем подключение
    nmcli connection up "$CON_NAME" || {
        echo "  Первая попытка не удалась, ждём и пробуем снова..."
        sleep 5
        nmcli connection up "$CON_NAME" || {
            echo -e "${RED}  Не удалось активировать подключение $CON_NAME${NC}"
            echo "  Проверьте логи: journalctl -u NetworkManager -n 50"
            return 1
        }
    }

    # Показываем состояние
    echo "  Состояние модема:"
    mmcli -m $MODEM | grep -E "state|signal|operator" || echo "  Информация недоступна"
}

setup_nm_connection $MODEM1 "lte-modem1"
echo ""
setup_nm_connection $MODEM2 "lte-modem2"

sleep 5

echo -e "${YELLOW}Шаг 4: Определение сетевых интерфейсов${NC}"

# Показываем все сетевые интерфейсы для отладки
echo "Доступные интерфейсы:"
ip link show | grep -E "^[0-9]+:" | awk '{print $2}'

# Ждём пока NetworkManager активирует подключения и назначит интерфейсы
echo "Ожидание активации интерфейсов NetworkManager..."
sleep 5

# NM показывает cdc-wdm* как device, но IP назначается на wwan* (data interface)
# Нужно использовать wwan* интерфейсы для работы с IP

# Ожидаем появления wwan интерфейсов (до 30 сек)
echo "Поиск wwan интерфейсов..."
for i in {1..30}; do
    WWAN_IFACES=($(ip link | grep -oP 'wwan\d+'))

    if [ ${#WWAN_IFACES[@]} -ge 2 ]; then
        break
    fi

    if [ $((i % 10)) -eq 0 ]; then
        echo "  Ожидание интерфейсов... ($i сек), найдено: ${#WWAN_IFACES[@]}"
    fi
    sleep 1
done

if [ ${#WWAN_IFACES[@]} -lt 2 ]; then
    echo -e "${RED}Не удалось найти 2 wwan интерфейса!${NC}"
    echo "Найдено: ${WWAN_IFACES[*]}"
    echo ""
    echo "Состояние NetworkManager:"
    nmcli device status
    nmcli connection show
    exit 1
fi

# Определяем соответствие модем <-> wwan интерфейс через номер в имени
# cdc-wdm0 соответствует wwan0, cdc-wdm1 -> wwan1
get_wwan_for_modem() {
    local MODEM=$1
    local CDM_PORT=$(get_modem_primary_port $MODEM)  # например cdc-wdm0
    local NUM=$(echo "$CDM_PORT" | grep -oP '\d+$')   # извлекаем номер
    echo "wwan${NUM}"
}

IFACE1=$(get_wwan_for_modem $MODEM1)
IFACE2=$(get_wwan_for_modem $MODEM2)

# Проверяем что интерфейсы существуют
if ! ip link show $IFACE1 &>/dev/null; then
    echo -e "${YELLOW}Интерфейс $IFACE1 не найден, используем первый доступный wwan${NC}"
    IFACE1=${WWAN_IFACES[0]}
fi
if ! ip link show $IFACE2 &>/dev/null; then
    echo -e "${YELLOW}Интерфейс $IFACE2 не найден, используем второй доступный wwan${NC}"
    IFACE2=${WWAN_IFACES[1]}
fi

# Поднимаем интерфейсы
ip link set $IFACE1 up 2>/dev/null || true
ip link set $IFACE2 up 2>/dev/null || true

echo -e "${GREEN}Интерфейсы: $IFACE1 и $IFACE2${NC}"

echo -e "${YELLOW}Шаг 5: Получение IP адресов${NC}"

# Показываем состояние NM подключений
echo "Состояние NetworkManager подключений:"
nmcli connection show --active | grep -E "lte-modem|gsm" || echo "  Нет активных GSM подключений"

# Функция для получения IP из bearer и ручной настройки интерфейса
configure_ip_from_bearer() {
    local MODEM=$1
    local IFACE=$2

    echo "  Пробуем получить IP из bearer для модема $MODEM -> $IFACE"

    # Получаем номер bearer
    local BEARER=$(mmcli -m $MODEM 2>/dev/null | grep -oP 'Bearer/\K[0-9]+' | head -1)
    if [ -z "$BEARER" ]; then
        echo "    Bearer не найден"
        return 1
    fi

    echo "    Bearer: $BEARER"

    # Получаем информацию из bearer
    local BEARER_INFO=$(mmcli -b $BEARER 2>/dev/null)
    local IP=$(echo "$BEARER_INFO" | grep -oP 'address:\s+\K[\d.]+' | head -1)
    local GW=$(echo "$BEARER_INFO" | grep -oP 'gateway:\s+\K[\d.]+' | head -1)
    local PREFIX=$(echo "$BEARER_INFO" | grep -oP 'prefix:\s+\K\d+' | head -1)
    local DNS=$(echo "$BEARER_INFO" | grep -oP 'dns:\s+\K[\d.]+' | head -1)

    if [ -z "$IP" ] || [ -z "$GW" ]; then
        echo "    IP или Gateway не найдены в bearer"
        echo "    Bearer info: $BEARER_INFO"
        return 1
    fi

    PREFIX=${PREFIX:-24}
    echo "    IP: $IP/$PREFIX, Gateway: $GW"

    # Удаляем старый IP если есть
    ip addr flush dev $IFACE 2>/dev/null || true

    # Назначаем IP
    ip addr add $IP/$PREFIX dev $IFACE
    ip link set $IFACE up

    echo "    IP назначен на $IFACE"
    return 0
}

# Ждем получения IP адресов (сначала автоматически)
echo "Ожидание получения IP адресов (до 30 сек)..."
for i in {1..30}; do
    IP1=$(ip -4 addr show $IFACE1 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1 || echo "")
    IP2=$(ip -4 addr show $IFACE2 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1 || echo "")

    if [ -n "$IP1" ] && [ -n "$IP2" ]; then
        echo -e "${GREEN}IP адреса получены автоматически!${NC}"
        break
    fi

    if [ $((i % 10)) -eq 0 ]; then
        echo "  Ожидание... ($i сек)"
    fi
    sleep 1
done

# Если автоматически не получилось - пробуем вручную из bearer
if [ -z "$IP1" ]; then
    echo -e "${YELLOW}IP для $IFACE1 не получен автоматически, пробуем из bearer...${NC}"
    configure_ip_from_bearer $MODEM1 $IFACE1
    IP1=$(ip -4 addr show $IFACE1 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1 || echo "")
fi

if [ -z "$IP2" ]; then
    echo -e "${YELLOW}IP для $IFACE2 не получен автоматически, пробуем из bearer...${NC}"
    configure_ip_from_bearer $MODEM2 $IFACE2
    IP2=$(ip -4 addr show $IFACE2 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1 || echo "")
fi

if [ -z "$IP1" ] || [ -z "$IP2" ]; then
    echo -e "${RED}Не удалось получить IP адреса!${NC}"
    echo "IP1 ($IFACE1): ${IP1:-не получен}"
    echo "IP2 ($IFACE2): ${IP2:-не получен}"
    echo ""
    echo "Диагностика:"
    echo "Модем 1 bearer:"
    BEARER1=$(mmcli -m $MODEM1 2>/dev/null | grep -oP 'Bearer/\K[0-9]+' | head -1)
    [ -n "$BEARER1" ] && mmcli -b $BEARER1 || echo "  Bearer не найден"
    echo ""
    echo "Модем 2 bearer:"
    BEARER2=$(mmcli -m $MODEM2 2>/dev/null | grep -oP 'Bearer/\K[0-9]+' | head -1)
    [ -n "$BEARER2" ] && mmcli -b $BEARER2 || echo "  Bearer не найден"
    echo ""
    echo "Состояние модемов:"
    mmcli -m $MODEM1 | grep -E "state|bearer"
    mmcli -m $MODEM2 | grep -E "state|bearer"
    exit 1
fi

# Получаем шлюзы
echo "Определение шлюзов..."
sleep 2

GW1=$(ip route show dev $IFACE1 | grep default | awk '{print $3}' | head -1)
GW2=$(ip route show dev $IFACE2 | grep default | awk '{print $3}' | head -1)

# Если шлюзы не найдены автоматически, пробуем альтернативный метод
if [ -z "$GW1" ]; then
    GW1=$(ip route | grep $IFACE1 | grep default | awk '{print $3}' | head -1)
fi
if [ -z "$GW2" ]; then
    GW2=$(ip route | grep $IFACE2 | grep default | awk '{print $3}' | head -1)
fi

if [ -z "$GW1" ] || [ -z "$GW2" ]; then
    echo -e "${RED}Не удалось определить шлюзы!${NC}"
    echo "Gateway1 ($IFACE1): ${GW1:-не найден}"
    echo "Gateway2 ($IFACE2): ${GW2:-не найден}"
    echo ""
    echo "Таблица маршрутизации:"
    ip route show
    exit 1
fi

echo -e "${GREEN}Модем 1: IP=$IP1, Gateway=$GW1, Interface=$IFACE1${NC}"
echo -e "${GREEN}Модем 2: IP=$IP2, Gateway=$GW2, Interface=$IFACE2${NC}"

echo -e "${YELLOW}Шаг 6: Очистка предыдущих настроек${NC}"

# Удаляем существующие правила ip rule (игнорируем ошибки)
while ip rule del table modem1 2>/dev/null; do :; done
while ip rule del table modem2 2>/dev/null; do :; done
while ip rule del from $IP1 2>/dev/null; do :; done
while ip rule del from $IP2 2>/dev/null; do :; done

# Очищаем таблицы маршрутизации
ip route flush table modem1 2>/dev/null || true
ip route flush table modem2 2>/dev/null || true

echo -e "${YELLOW}Шаг 7: Настройка таблиц маршрутизации${NC}"

# Добавляем таблицы в rt_tables (идемпотентно)
grep -qxF "1 modem1" /etc/iproute2/rt_tables || echo "1 modem1" >> /etc/iproute2/rt_tables
grep -qxF "2 modem2" /etc/iproute2/rt_tables || echo "2 modem2" >> /etc/iproute2/rt_tables

# Настройка маршрутов для каждого модема
ip route add default via $GW1 dev $IFACE1 table modem1
ip route add default via $GW2 dev $IFACE2 table modem2

# Правила маршрутизации
ip rule add from $IP1 table modem1 priority 100
ip rule add from $IP2 table modem2 priority 100

# Удаляем старый default route если есть multipath
ip route del default 2>/dev/null || true

# Основной маршрут с балансировкой 50/50
ip route add default scope global \
    nexthop via $GW1 dev $IFACE1 weight 1 \
    nexthop via $GW2 dev $IFACE2 weight 1

echo -e "${YELLOW}Шаг 8: Настройка NAT (iptables)${NC}"

# Очищаем цепочку POSTROUTING в таблице nat
iptables -t nat -F POSTROUTING

# Добавляем правила MASQUERADE
iptables -t nat -A POSTROUTING -o $IFACE1 -j MASQUERADE
iptables -t nat -A POSTROUTING -o $IFACE2 -j MASQUERADE

# Сохранение правил iptables
netfilter-persistent save 2>/dev/null || iptables-save > /etc/iptables/rules.v4

echo -e "${YELLOW}Шаг 9: Включение IP forwarding${NC}"
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-ip-forward.conf
sysctl -w net.ipv4.ip_forward=1 >/dev/null

echo ""
echo -e "${GREEN}=== Настройка завершена! ===${NC}"
echo ""
echo "Статус модемов:"
echo "Модем 1:"
mmcli -m $MODEM1 | grep -E "state|signal quality|access tech" || echo "Информация недоступна"
echo ""
echo "Модем 2:"
mmcli -m $MODEM2 | grep -E "state|signal quality|access tech" || echo "Информация недоступна"
echo ""
echo "Таблица маршрутизации:"
ip route show
echo ""
echo "Правила маршрутизации:"
ip rule show | grep -E "modem|$IP1|$IP2"
echo ""
echo -e "${GREEN}Оба модема настроены. Трафик балансируется 50/50.${NC}"
echo ""
echo "Для проверки выполните:"
echo "  curl --interface $IFACE1 ifconfig.me"
echo "  curl --interface $IFACE2 ifconfig.me"
echo "  curl ifconfig.me  # Будет использовать балансировку"