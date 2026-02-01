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

# check ModemManager state in cycle
for i in {1..10}; do
    if systemctl is-active --quiet ModemManager; then
        break
    fi
    echo "Ожидание запуска ModemManager... ($i)"
    sleep 2
done   

mmcli -L

# Получаем номера модемов
MODEM1=$(mmcli -L | grep -oP '/Modem/\K[0-9]+' | sed -n '1p')
MODEM2=$(mmcli -L | grep -oP '/Modem/\K[0-9]+' | sed -n '2p')

if [ -z "$MODEM1" ] || [ -z "$MODEM2" ]; then
    echo -e "${RED}Не удалось обнаружить оба модема!${NC}"
    echo "Найдено модемов: $(mmcli -L | grep -c Modem || echo 0)"
    exit 1
fi

echo -e "${GREEN}Найдены модемы: $MODEM1 и $MODEM2${NC}"

echo -e "${YELLOW}Шаг 3: Включение и подключение модемов${NC}"

# Функция для подключения модема (идемпотентная)
connect_modem() {
    local MODEM=$1
    echo "Настройка модема $MODEM..."
    
    # Получаем полную информацию о модеме
    MODEM_INFO=$(mmcli -m $MODEM)
    
    # Проверяем состояние модема (используем несколько вариантов grep)
    if echo "$MODEM_INFO" | grep -q "state.*disabled"; then
        echo "  Модем выключен, включаем..."
        mmcli -m $MODEM -e || {
            echo "  Не удалось включить модем (возможно уже включен)"
        }
        sleep 3
    fi
    
    # Проверяем подключение
    MODEM_INFO=$(mmcli -m $MODEM)
    
    if echo "$MODEM_INFO" | grep -q "state.*connected"; then
        echo "  Модем уже подключен к сети"
    else
        echo "  Подключение к сети (APN: $APN)..."
        mmcli -m $MODEM --simple-connect="apn=$APN" || {
            echo "  Ошибка подключения или модем уже подключается"
        }
        sleep 5
    fi
    
    # Показываем итоговое состояние
    echo "  Состояние модема:"
    mmcli -m $MODEM | grep -E "state|signal|operator" || echo "  Информация недоступна"
}

connect_modem $MODEM1
echo ""
connect_modem $MODEM2

sleep 5

echo -e "${YELLOW}Шаг 4: Определение сетевых интерфейсов${NC}"

# Показываем все сетевые интерфейсы для отладки
echo "Доступные интерфейсы:"
ip link show | grep -E "^[0-9]+:" | awk '{print $2}'

# Находим интерфейсы wwan
WWAN_IFACES=($(ip link | grep -oP 'wwan\d+'))

if [ ${#WWAN_IFACES[@]} -lt 2 ]; then
    echo -e "${RED}Найдено интерфейсов wwan: ${#WWAN_IFACES[@]} (нужно 2)${NC}"
    echo "Ожидаем появления интерфейсов..."
    
    # Ждем до 30 секунд
    for i in {1..30}; do
        WWAN_IFACES=($(ip link | grep -oP 'wwan\d+'))
        if [ ${#WWAN_IFACES[@]} -ge 2 ]; then
            break
        fi
        sleep 1
    done
fi

if [ ${#WWAN_IFACES[@]} -lt 2 ]; then
    echo -e "${RED}Так и не появились оба интерфейса wwan!${NC}"
    echo "Проверьте подключение модемов и статус ModemManager"
    exit 1
fi

IFACE1=${WWAN_IFACES[0]}
IFACE2=${WWAN_IFACES[1]}

echo -e "${GREEN}Интерфейсы: $IFACE1 и $IFACE2${NC}"

# Поднимаем интерфейсы если они down
ip link set $IFACE1 up 2>/dev/null || true
ip link set $IFACE2 up 2>/dev/null || true

sleep 2

echo -e "${YELLOW}Шаг 5: Получение IP адресов${NC}"

# Ждем получения IP адресов
echo "Ожидание получения IP адресов (до 60 сек)..."
for i in {1..60}; do
    IP1=$(ip -4 addr show $IFACE1 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1 || echo "")
    IP2=$(ip -4 addr show $IFACE2 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1 || echo "")
    
    if [ -n "$IP1" ] && [ -n "$IP2" ]; then
        echo -e "${GREEN}IP адреса получены!${NC}"
        break
    fi
    
    if [ $((i % 10)) -eq 0 ]; then
        echo "  Ожидание... ($i сек)"
    fi
    sleep 1
done

if [ -z "$IP1" ] || [ -z "$IP2" ]; then
    echo -e "${RED}Не удалось получить IP адреса!${NC}"
    echo "IP1 ($IFACE1): ${IP1:-не получен}"
    echo "IP2 ($IFACE2): ${IP2:-не получен}"
    echo ""
    echo "Информация об интерфейсах:"
    ip addr show $IFACE1
    echo ""
    ip addr show $IFACE2
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