# Архитектура ProxyFarm

## Обзор системы

ProxyFarm — это система управления LTE модемами с HTTP API для ротации IP-адресов и проксирования трафика через мобильные сети. Система работает на Orange Pi Zero 3 под управлением Armbian (Ubuntu).

## Компоненты системы

### 1. Аппаратный уровень
- **Orange Pi Zero 3** - основной контроллер
- **2x LTE модемы** (wwan0, wwan1) - выход в интернет через мобильные сети
- **WiFi (wlan0)** - управление и резервный канал
- **VPS** - публичный прокси-сервер для доступа к системе

### 2. Программный стек

#### Системные компоненты
- **ModemManager** - управление LTE модемами
- **NetworkManager** - управление сетевыми подключениями
- **Linux Kernel Routing** - multipath маршрутизация
- **Squid 6.13** - HTTP/HTTPS прокси-сервер
- **OpenVPN** - защищенное соединение между VPS и Orange Pi

#### Приложение ProxyFarm
- **FastAPI** - HTTP API сервер
- **Python 3.11+** - основной язык
- **asyncio** - асинхронные операции
- **systemd** - управление сервисами

## Архитектура сети

```mermaid
graph TB
    subgraph Internet
        WEB[Web Services]
    end

    subgraph VPS["VPS (138.2.138.243)"]
        SOCAT[Socat Forwarder<br/>:3128]
        VPN_SERVER[OpenVPN Server<br/>10.8.0.1]
    end

    subgraph OrangePi["Orange Pi (192.168.50.111)"]
        VPN_CLIENT[OpenVPN Client<br/>10.8.0.2/tun0]
        SQUID[Squid Proxy<br/>:3128]
        API[FastAPI Service<br/>:8080]

        subgraph Network["Network Layer"]
            KERNEL[Linux Kernel<br/>Multipath Routing]
            WIFI[WiFi/wlan0<br/>192.168.50.111<br/>WAN: 188.169.117.42]
            WWAN0[LTE Modem 0/wwan0<br/>LAN: 10.231.254.x<br/>WAN: 91.151.136.x]
            WWAN1[LTE Modem 1/wwan1<br/>LAN: 10.223.35.x<br/>WAN: 91.151.137.x]
        end

        MM[ModemManager]
        NM[NetworkManager]
    end

    CLIENT[Client] -->|HTTP CONNECT| SOCAT
    SOCAT -->|via VPN tunnel| VPN_CLIENT
    VPN_CLIENT --> SQUID
    SQUID --> KERNEL

    KERNEL -->|default route<br/>multipath| WWAN0
    KERNEL -->|default route<br/>multipath| WWAN1
    KERNEL -->|backup<br/>metric 1000| WIFI

    WWAN0 --> WEB
    WWAN1 --> WEB
    WIFI --> WEB

    API --> MM
    API --> NM
    API --> SQUID

    style WWAN0 fill:#90EE90
    style WWAN1 fill:#90EE90
    style WIFI fill:#FFE4B5
    style SQUID fill:#87CEEB
```

## Поток данных

### Запрос через прокси

```mermaid
sequenceDiagram
    participant Client
    participant VPS
    participant Squid as Squid (OrangePi)
    participant Kernel as Linux Kernel
    participant Modem1 as wwan0 (LTE Modem 1)
    participant Modem2 as wwan1 (LTE Modem 2)
    participant Target as Target Server

    Client->>VPS: HTTP CONNECT через :3128
    Note over VPS: Socat перенаправляет<br/>на 10.8.0.2:3128
    VPS->>Squid: Через VPN tunnel

    Squid->>Kernel: Запрос к target server
    Note over Kernel: Multipath routing<br/>выбирает модем<br/>по L4 hash

    alt Hash направляет на wwan0
        Kernel->>Modem1: Пакеты через wwan0
        Modem1->>Target: Source IP: 91.151.136.x
        Target->>Modem1: Ответ
        Modem1->>Kernel: Пакеты обратно
    else Hash направляет на wwan1
        Kernel->>Modem2: Пакеты через wwan1
        Modem2->>Target: Source IP: 91.151.137.x
        Target->>Modem2: Ответ
        Modem2->>Kernel: Пакеты обратно
    end

    Kernel->>Squid: Ответ от сервера
    Squid->>VPS: Через VPN tunnel
    VPS->>Client: HTTP ответ
```

## Логика маршрутизации

### Текущая проблема

```mermaid
graph LR
    subgraph "Проблема"
        A[Squid делает запрос] --> B{Routing Table}
        B -->|default via WiFi| C[WiFi Gateway]
        C --> D[Исходящий IP:<br/>188.169.117.42]
    end

    subgraph "Желаемое поведение"
        E[Squid делает запрос] --> F{Multipath Route}
        F -->|50% трафика| G[wwan0 Gateway]
        F -->|50% трафика| H[wwan1 Gateway]
        G --> I[Исходящий IP:<br/>91.151.136.x]
        H --> J[Исходящий IP:<br/>91.151.137.x]
    end

    style D fill:#FFB6C1
    style I fill:#90EE90
    style J fill:#90EE90
```

### Решение: Multipath Routing

Таблица маршрутизации должна выглядеть так:

```bash
# Приоритетный маршрут - multipath через оба модема
default
    nexthop via 10.231.254.1 dev wwan0 weight 1
    nexthop via 10.223.35.1 dev wwan1 weight 1

# Резервный маршрут через WiFi
default via 192.168.50.1 dev wlan0 metric 1000
```

Kernel использует L4 hash (source IP, dest IP, source port, dest port) для выбора nexthop, что обеспечивает:
- Одно TCP соединение всегда идет через один модем
- Разные соединения распределяются между модемами
- Балансировка нагрузки

## Структура API

```mermaid
graph TD
    API[FastAPI Application :8080]

    API --> MODEMS[/api/v1/modems]
    API --> USSD[/api/v1/ussd]
    API --> PROXY[/api/v1/proxy]
    API --> SYSTEM[/api/v1/system]

    MODEMS --> LIST[GET / - Список модемов]
    MODEMS --> GET[GET /{id} - Инфо о модеме]
    MODEMS --> ROTATE[POST /{id}/rotate - Ротация IP]
    MODEMS --> ENABLE[POST /{id}/enable - Включить]
    MODEMS --> DISABLE[POST /{id}/disable - Выключить]

    USSD --> SEND[POST /{id}/ussd - USSD команда]

    PROXY --> STATUS[GET /status - Статус Squid]
    PROXY --> RECONFIG[POST /reconfigure - Перенастроить]

    SYSTEM --> SYSSTATUS[GET /status - Статус системы]
    SYSTEM --> HEALTH[GET /health - Health check]

    style API fill:#87CEEB
    style MODEMS fill:#FFE4B5
    style USSD fill:#FFE4B5
    style PROXY fill:#FFE4B5
    style SYSTEM fill:#FFE4B5
```

## Core модули

```mermaid
graph TB
    subgraph API Layer
        ROUTER[API Router]
    end

    subgraph Core Layer
        MODEM[ModemManager<br/>mmcli wrapper]
        NETWORK[NetworkManager<br/>nmcli wrapper]
        USSD[USSD Manager]
        ROTATION[IP Rotator]
        SQUID[Squid Manager]
    end

    subgraph System Layer
        MMCLI[mmcli]
        NMCLI[nmcli]
        IPROUTE[ip route]
        SYSTEMCTL[systemctl]
    end

    ROUTER --> MODEM
    ROUTER --> NETWORK
    ROUTER --> USSD
    ROUTER --> ROTATION
    ROUTER --> SQUID

    MODEM --> MMCLI
    NETWORK --> NMCLI
    ROTATION --> NMCLI
    ROTATION --> IPROUTE
    ROTATION --> SQUID
    SQUID --> SYSTEMCTL
    USSD --> MMCLI
```

## Процесс ротации IP

```mermaid
sequenceDiagram
    participant Client
    participant API
    participant Rotator as IP Rotator
    participant NM as NetworkManager
    participant MM as ModemManager
    participant Squid
    participant Kernel

    Client->>API: POST /api/v1/modems/0/rotate
    API->>Rotator: rotate(modem_id=0)

    Note over Rotator: Шаг 1: Получить текущий IP
    Rotator->>MM: Получить bearer info
    MM-->>Rotator: Текущий IP: 91.151.136.100

    Note over Rotator: Шаг 2: Отключить соединение
    Rotator->>NM: nmcli connection down gsm0
    NM-->>Rotator: OK

    Note over Rotator: Шаг 3: Подождать disconnect
    loop Проверка каждую секунду
        Rotator->>MM: Проверить состояние
        MM-->>Rotator: disconnected
    end

    Note over Rotator: Шаг 4: Подключить заново
    Rotator->>NM: nmcli connection up gsm0
    NM-->>Rotator: OK

    Note over Rotator: Шаг 5: Дождаться нового IP
    loop Проверка каждую секунду
        Rotator->>MM: Получить bearer info
        MM-->>Rotator: Новый IP: 91.151.136.234
    end

    Note over Rotator: Шаг 6: Обновить маршруты
    Rotator->>Kernel: Обновить multipath route

    Note over Rotator: Шаг 7: Перенастроить Squid
    Rotator->>Squid: reconfigure()
    Squid-->>Rotator: OK

    Rotator-->>API: Success: 91.151.136.100 → 91.151.136.234
    API-->>Client: 200 OK + rotation details
```

## Мониторинг (будущая функциональность)

```mermaid
graph TB
    MONITOR[Monitor Service]

    MONITOR -->|каждые 30 сек| CHECK_MODEMS[Проверить статус модемов]
    MONITOR -->|каждые 30 сек| CHECK_IP[Проверить IP адреса]
    MONITOR -->|каждые 60 сек| CHECK_INET[Проверить интернет]
    MONITOR -->|каждые 60 сек| CHECK_ROUTES[Проверить маршруты]

    CHECK_MODEMS -->|connected?| MM[ModemManager]
    CHECK_IP -->|IP changed?| MM
    CHECK_INET -->|curl через каждый модем| KERNEL[Kernel]
    CHECK_ROUTES -->|multipath exists?| KERNEL

    CHECK_MODEMS -->|disconnected| RECOVER[Автовосстановление]
    CHECK_INET -->|no internet| RECOVER
    CHECK_ROUTES -->|route missing| RECOVER

    RECOVER -->|1| RECONNECT[Переподключить модем]
    RECOVER -->|2| RESTORE_ROUTES[Восстановить маршруты]
    RECOVER -->|3| RESTART_SQUID[Перезапустить Squid]
```

## Скрипты и автоматизация

```mermaid
graph TB
    subgraph Setup Scripts
        SETUP_MODEMS[setup_modem_routing.sh]
        SETUP_SQUID[setup_squid.sh]
        SETUP_VPS[setup_vps_proxy_forward.sh]
    end

    subgraph Installation Scripts
        INSTALL_NM[install_nm_dispatcher.sh]
        INSTALL_SERVICE[install_routing_service.sh]
    end

    subgraph Systemd Units
        PROXYFARM_SERVICE[proxyfarm.service<br/>FastAPI app]
        ROUTING_SERVICE[modem-routing.service<br/>Routing setup]
        ROUTING_TIMER[modem-routing.timer<br/>Periodic check]
        SQUID_SERVICE[squid.service<br/>Proxy server]
    end

    subgraph NetworkManager
        NM_DISPATCHER[/etc/NetworkManager/dispatcher.d/<br/>99-modem-routing]
    end

    INSTALL_NM -->|creates| NM_DISPATCHER
    INSTALL_SERVICE -->|creates| ROUTING_SERVICE
    INSTALL_SERVICE -->|creates| ROUTING_TIMER

    NM_DISPATCHER -->|runs on connection change| SETUP_MODEMS
    ROUTING_TIMER -->|runs every 5 min| ROUTING_SERVICE
    ROUTING_SERVICE -->|executes| SETUP_MODEMS

    SETUP_MODEMS -->|calculates gateways| IPROUTE[ip route commands]
    SETUP_SQUID -->|generates config| SQUID_CONF[/etc/squid/squid.conf]

    PROXYFARM_SERVICE -->|manages| API[FastAPI :8080]
    SQUID_SERVICE -->|runs| SQUID[Squid :3128]

    style NM_DISPATCHER fill:#90EE90
    style ROUTING_SERVICE fill:#87CEEB
    style ROUTING_TIMER fill:#87CEEB
```

## Конфигурация

### config.yaml структура

```yaml
api:
  host: "0.0.0.0"
  port: 8080
  api_key: "secret-key-here"

modems:
  apn: "internet"
  expected_count: 2

proxy:
  port: 3128
  allowed_networks:
    - "10.8.0.0/24"  # VPN network
    - "192.168.50.0/24"  # Local network

routing:
  l4_hash_enabled: true  # Use L4 hash for multipath
  wifi_backup_metric: 1000

monitor:
  enabled: true
  interval: 30
  auto_reconnect: true
  health_check_urls:
    - "http://ifconfig.me"
    - "http://api.ipify.org"
```

## Ключевые технические детали

### 1. Multipath Routing

**Алгоритм балансировки:**
- Kernel использует `fib_multipath_hash_policy = 1` (L4 hash)
- Хеш вычисляется по: source IP, dest IP, source port, dest port
- Одно TCP соединение всегда идет через один nexthop
- Разные соединения распределяются между nexthop'ами

**Преимущества:**
- Нет разрыва TCP соединений
- Эффективная балансировка на уровне соединений
- Работает прозрачно для приложений

### 2. Squid конфигурация

**Ключевые директивы:**
```squid
# ACL для доступа только с VPN
acl vpn_network src 10.8.0.0/24
http_access allow vpn_network

# НЕ используем tcp_outgoing_address
# Squid использует kernel routing для выбора интерфейса

# DNS кеширование
dns_nameservers 8.8.8.8 8.8.4.4

# Connection pooling
client_persistent_connections on
server_persistent_connections on
pconn_timeout 1 minute
```

**Почему не используем tcp_outgoing_address:**
- Squid не может балансировать между несколькими IP
- Kernel routing с multipath делает это лучше
- Прозрачность для приложения

### 3. Вычисление Gateway

```bash
# Получаем IP интерфейса
IP0=$(ip -4 addr show wwan0 | grep -oP 'inet \K[\d.]+')
# Пример: 10.231.254.77

# Вычисляем gateway (.1 в той же подсети)
GW0=$(echo $IP0 | sed 's/\.[0-9]*$/\.1/')
# Результат: 10.231.254.1
```

**Почему так работает:**
- Мобильные операторы используют /24 или /30 подсети
- Gateway всегда .1 в подсети
- ModemManager bearer иногда не возвращает gateway

## Проблемы и решения

### Проблема 1: NetworkManager восстанавливает WiFi маршрут

**Причина:** NetworkManager автоматически управляет маршрутами для всех подключений

**Решение 1 (Рекомендуется):** NetworkManager Dispatcher
- Скрипт запускается при любом изменении подключений
- Автоматически восстанавливает multipath routing
- Стандартный механизм Linux

**Решение 2:** Systemd Timer
- Периодически проверяет и восстанавливает маршруты
- Проще для отладки
- Небольшая задержка между нарушением и восстановлением

### Проблема 2: Squid отдает WiFi IP вместо модемного

**Причина:** Default route идет через WiFi, а не через модемы

**Решение:** Multipath route с приоритетом выше, чем WiFi
```bash
# Multipath через модемы (без metric = metric 0 = наивысший приоритет)
default nexthop via 10.231.254.1 dev wwan0 weight 1 \
        nexthop via 10.223.35.1 dev wwan1 weight 1

# WiFi как backup с низким приоритетом
default via 192.168.50.1 dev wlan0 metric 1000
```

### Проблема 3: Медленные запросы через прокси

**Причины:**
- Устаревшие директивы Squid
- Отсутствие DNS кеширования
- Нет connection pooling

**Решение:**
- Удалены obsolete директивы
- Добавлен DNS кеширование (8.8.8.8)
- Включен connection pooling
- Результат: с 29 сек → 1.4-3 сек

## Метрики и мониторинг

### Что отслеживать

1. **Состояние модемов**
   - Статус подключения (connected/disconnected)
   - Сила сигнала
   - Текущий IP адрес

2. **Сеть**
   - Наличие multipath route
   - Metric маршрутов
   - Доступность интернета через каждый модем

3. **Прокси**
   - Squid running/stopped
   - Количество активных соединений
   - Исходящие IP адреса

4. **Производительность**
   - Время ответа прокси
   - Балансировка трафика между модемами
   - Количество ротаций IP

### Логи

```bash
# FastAPI logs
journalctl -u proxyfarm.service -f

# Squid logs
tail -f /var/log/squid/access.log

# Routing logs (если используется timer)
journalctl -u modem-routing.service -f

# NetworkManager dispatcher logs
journalctl -f | grep NM-Dispatcher

# Системные сетевые события
journalctl -f | grep -E "wwan|NetworkManager"
```

## Следующие шаги

1. ✅ Создать FastAPI приложение с базовыми endpoints
2. ✅ Реализовать ротацию IP
3. ✅ Настроить Squid proxy
4. ✅ Настроить VPS forwarding
5. ✅ Оптимизировать производительность прокси
6. ✅ Создать скрипт multipath routing
7. 🔄 **[ТЕКУЩАЯ ЗАДАЧА]** Сделать multipath routing persistent
8. ⏳ Протестировать балансировку нагрузки
9. ⏳ Реализовать фоновый мониторинг
10. ⏳ Добавить автовосстановление при сбоях
11. ⏳ Создать systemd service для FastAPI
12. ⏳ Написать документацию API
