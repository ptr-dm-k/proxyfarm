# Топология сети ProxyFarm

## Физическая топология

```mermaid
graph TB
    subgraph Internet["Интернет"]
        ISP1[Мобильный оператор 1]
        ISP2[Мобильный оператор 2]
        HOME_ISP[Домашний провайдер]
        CLOUD[VPS Provider]
    end

    subgraph Home["Домашняя сеть 192.168.50.0/24"]
        ROUTER[WiFi Router<br/>192.168.50.1]

        subgraph OrangePi["Orange Pi Zero 3<br/>192.168.50.111"]
            WLAN[wlan0<br/>WiFi адаптер]
            USB1[USB Port]
            USB2[USB Port]
        end

        LAPTOP[MacBook<br/>192.168.50.37]
    end

    subgraph VPS_Cloud["VPS в облаке"]
        VPS[VPS<br/>138.2.138.243]
    end

    subgraph Modems["LTE модемы"]
        MODEM1[LTE Modem 1]
        MODEM2[LTE Modem 2]
    end

    ROUTER <-->|WiFi| WLAN
    ROUTER <--> LAPTOP
    ROUTER <--> HOME_ISP

    USB1 --> MODEM1
    USB2 --> MODEM2

    MODEM1 <-->|LTE| ISP1
    MODEM2 <-->|LTE| ISP2

    VPS <--> CLOUD
    VPS <-.->|OpenVPN tunnel| WLAN

    style OrangePi fill:#FFE4B5
    style VPS fill:#87CEEB
    style MODEM1 fill:#90EE90
    style MODEM2 fill:#90EE90
```

## Логическая топология

```mermaid
graph TB
    subgraph External["Внешний мир"]
        CLIENT[Клиент<br/>любой IP]
        TARGET[Целевой сервер<br/>например, Instagram API]
    end

    subgraph VPS["VPS: 138.2.138.243"]
        VPS_PUBLIC[Публичный IP<br/>138.2.138.243]
        VPS_VPN[VPN IP<br/>10.8.0.1]
        SOCAT[Socat :3128]
        OVPN_S[OpenVPN Server]
    end

    subgraph OrangePi["Orange Pi"]
        subgraph VPN_Layer["VPN Layer"]
            TUN0[tun0<br/>10.8.0.2]
            OVPN_C[OpenVPN Client]
        end

        subgraph App_Layer["Application Layer"]
            SQUID[Squid Proxy<br/>:3128]
            FASTAPI[FastAPI<br/>:8080]
        end

        subgraph Network_Layer["Network Layer"]
            ROUTING[Linux Kernel<br/>Routing Table]
        end

        subgraph Physical_Layer["Physical Layer"]
            WLAN0[wlan0<br/>192.168.50.111<br/>↓<br/>188.169.117.42]
            WWAN0[wwan0<br/>10.231.254.x<br/>↓<br/>91.151.136.x]
            WWAN1[wwan1<br/>10.223.35.x<br/>↓<br/>91.151.137.x]
        end
    end

    CLIENT -->|1. HTTP CONNECT :3128| VPS_PUBLIC
    VPS_PUBLIC --> SOCAT
    SOCAT -->|2. Forward to 10.8.0.2:3128| VPS_VPN
    VPS_VPN <-->|3. VPN Tunnel| TUN0
    TUN0 --> OVPN_C
    OVPN_C --> SQUID

    SQUID -->|4. HTTP request| ROUTING

    ROUTING -->|5a. Multipath<br/>50%| WWAN0
    ROUTING -->|5b. Multipath<br/>50%| WWAN1
    ROUTING -.->|Backup<br/>metric 1000| WLAN0

    WWAN0 -->|6a. From 91.151.136.x| TARGET
    WWAN1 -->|6b. From 91.151.137.x| TARGET
    WLAN0 -.->|❌ From 188.169.117.42| TARGET

    TARGET -->|7. Response| WWAN0
    TARGET -->|7. Response| WWAN1

    WWAN0 --> ROUTING
    WWAN1 --> ROUTING
    ROUTING --> SQUID
    SQUID --> TUN0
    TUN0 --> VPS_VPN
    VPS_VPN --> SOCAT
    SOCAT --> VPS_PUBLIC
    VPS_PUBLIC -->|8. Response| CLIENT

    FASTAPI -.->|Управление| ROUTING
    FASTAPI -.->|Управление| SQUID

    style WWAN0 fill:#90EE90
    style WWAN1 fill:#90EE90
    style WLAN0 fill:#FFE4B5
    style SQUID fill:#87CEEB
    style ROUTING fill:#DDA0DD
```

## IP адреса и интерфейсы

| Интерфейс | LAN IP | WAN IP | Gateway | Metric | Назначение |
|-----------|---------|---------|---------|---------|------------|
| **wwan0** | 10.231.254.x | 91.151.136.x | 10.231.254.1 | 0 (multipath) | LTE модем 1 |
| **wwan1** | 10.223.35.x | 91.151.137.x | 10.223.35.1 | 0 (multipath) | LTE модем 2 |
| **wlan0** | 192.168.50.111 | 188.169.117.42 | 192.168.50.1 | 1000 | WiFi (backup) |
| **tun0** | 10.8.0.2 | - | 10.8.0.1 | - | VPN tunnel |

## Таблица маршрутизации

### Желаемое состояние

```
default
    nexthop via 10.231.254.1 dev wwan0 weight 1
    nexthop via 10.223.35.1 dev wwan1 weight 1
default via 192.168.50.1 dev wlan0 metric 1000
10.8.0.0/24 via 10.8.0.1 dev tun0
10.223.35.0/24 dev wwan1 proto kernel scope link src 10.223.35.97
10.231.254.0/24 dev wwan0 proto kernel scope link src 10.231.254.74
192.168.50.0/24 dev wlan0 proto kernel scope link src 192.168.50.111
```

### Текущая проблема

```
default via 192.168.50.1 dev wlan0 metric 600  ❌
10.8.0.0/24 via 10.8.0.1 dev tun0
10.223.35.0/24 dev wwan1 proto kernel scope link src 10.223.35.97
10.231.254.0/24 dev wwan0 proto kernel scope link src 10.231.254.74
192.168.50.0/24 dev wlan0 proto kernel scope link src 192.168.50.111
```

**Проблема:** NetworkManager постоянно восстанавливает маршрут через WiFi с metric 600, который имеет приоритет над multipath маршрутом.

## Порты и протоколы

| Порт | Протокол | Сервис | Доступ |
|------|----------|--------|--------|
| 3128 | TCP | Squid Proxy | 10.8.0.0/24 (VPN) |
| 8080 | TCP | FastAPI | localhost |
| 1194 | UDP | OpenVPN | VPS ↔ Orange Pi |
| 22 | TCP | SSH | 192.168.50.0/24 |

## Потоки трафика

### Поток 1: Управляющий трафик (SSH)

```
MacBook (192.168.50.37)
    ↓ SSH :22
Orange Pi wlan0 (192.168.50.111)
```

### Поток 2: API управление

```
MacBook (192.168.50.37)
    ↓ HTTP :8080
Orange Pi FastAPI (localhost:8080)
    ↓ Команды управления
ModemManager / NetworkManager / Squid
```

### Поток 3: VPN tunnel

```
VPS (138.2.138.243)
    ↓ OpenVPN UDP :1194
    ↓ через интернет
Orange Pi wlan0 (192.168.50.111)
    ↓ UDP :1194
OpenVPN Client
    ↓ tun0 (10.8.0.1 ↔ 10.8.0.2)
```

### Поток 4: Прокси запросы (желаемый)

```
Клиент (любой IP)
    ↓ HTTP CONNECT 138.2.138.243:3128
VPS Socat
    ↓ Forward через VPN tunnel
Orange Pi tun0 (10.8.0.2)
    ↓ localhost:3128
Squid Proxy
    ↓ Kernel routing
    ├─→ 50% через wwan0 (91.151.136.x)
    └─→ 50% через wwan1 (91.151.137.x)
    ↓ Интернет
Целевой сервер
```

### Поток 5: Прокси запросы (текущая проблема)

```
Клиент (любой IP)
    ↓ HTTP CONNECT 138.2.138.243:3128
VPS Socat
    ↓ Forward через VPN tunnel
Orange Pi tun0 (10.8.0.2)
    ↓ localhost:3128
Squid Proxy
    ↓ Kernel routing
    └─→ ❌ 100% через wlan0 (188.169.117.42)
    ↓ Интернет
Целевой сервер
```

## Зависимости сервисов

```mermaid
graph TD
    subgraph SystemServices["System Services"]
        DBUS[D-Bus]
        NM[NetworkManager]
        MM[ModemManager]
        SQUID_SYS[Squid Service]
        OVPN[OpenVPN]
    end

    subgraph OurServices["ProxyFarm Services"]
        ROUTING[modem-routing.service<br/>или<br/>NM Dispatcher]
        PROXYFARM[proxyfarm.service<br/>FastAPI]
    end

    DBUS --> NM
    DBUS --> MM
    NM --> OVPN
    NM -.-> ROUTING
    MM --> ROUTING

    ROUTING --> SQUID_SYS
    PROXYFARM --> MM
    PROXYFARM --> NM
    PROXYFARM --> SQUID_SYS

    style ROUTING fill:#90EE90
    style PROXYFARM fill:#87CEEB
```

## Сценарии использования

### Сценарий 1: Обычный прокси запрос

```mermaid
sequenceDiagram
    participant C as Клиент
    participant V as VPS
    participant S as Squid
    participant K as Kernel
    participant M1 as wwan0
    participant M2 as wwan1
    participant T as Target

    C->>V: CONNECT instagram.com:443
    V->>S: Forward via VPN
    S->>K: TCP connect to Instagram

    alt Соединение 1 (hash → wwan0)
        K->>M1: Route via wwan0
        M1->>T: SRC: 91.151.136.x
        T-->>M1: Response
        M1-->>K: Packets back
    end

    Note over C,T: Следующий запрос от того же клиента

    C->>V: CONNECT api.instagram.com:443
    V->>S: Forward via VPN
    S->>K: TCP connect to API

    alt Соединение 2 (hash → wwan1)
        K->>M2: Route via wwan1
        M2->>T: SRC: 91.151.137.x
        T-->>M2: Response
        M2-->>K: Packets back
    end

    K-->>S: Response
    S-->>V: Via VPN
    V-->>C: Response
```

### Сценарий 2: Ротация IP

```mermaid
sequenceDiagram
    participant U as User
    participant A as API
    participant R as Rotator
    participant N as NM
    participant K as Kernel
    participant D as Dispatcher/Timer

    U->>A: POST /modems/0/rotate
    A->>R: rotate(0)
    R->>N: connection down gsm0
    N-->>R: OK (IP был 91.151.136.100)

    Note over R: Ждем disconnect (3-5 сек)

    R->>N: connection up gsm0
    N->>K: Установить маршрут wwan0

    Note over N,K: ⚠️ NM также восстанавливает WiFi route!
    N->>K: Восстановить default via wlan0 metric 600

    Note over D: Dispatcher обнаруживает изменение
    D->>K: Удалить WiFi route metric 600
    D->>K: Добавить multipath route
    D->>K: Добавить WiFi backup metric 1000

    Note over R: Ждем новый IP (5-10 сек)

    R->>N: Проверить новый IP
    N-->>R: Новый IP: 91.151.136.234

    R-->>A: Success
    A-->>U: 200 OK
```

### Сценарий 3: Восстановление после сбоя

```mermaid
sequenceDiagram
    participant NM as NetworkManager
    participant M as Modem wwan0
    participant K as Kernel
    participant D as Dispatcher/Timer
    participant S as Squid

    Note over M: Модем потерял связь
    M-->>NM: Disconnected event
    NM->>K: Удалить маршруты wwan0

    Note over K: Остается только WiFi route
    K->>K: default via wlan0

    Note over M: Модем восстановил связь
    M-->>NM: Connected event
    NM->>K: Добавить маршрут wwan0
    NM->>K: Добавить default via wlan0 metric 600

    Note over D: Dispatcher срабатывает на "up"
    D->>K: Пересоздать multipath route
    D->>S: Перезапустить Squid

    Note over K,S: Трафик снова идет через модемы
```

## Отладка и диагностика

### Проверка текущего состояния

```bash
# 1. Проверить все IP адреса
ip addr show

# 2. Проверить таблицу маршрутизации
ip route show

# 3. Проверить default route подробно
ip route show default

# 4. Проверить через какой интерфейс идет трафик
curl -v ifconfig.me

# 5. Проверить конкретный интерфейс
curl --interface wwan0 ifconfig.me
curl --interface wwan1 ifconfig.me

# 6. Проверить статус модемов
mmcli -L
mmcli -m 0
mmcli -m 1

# 7. Проверить bearer (IP, gateway)
mmcli -b 0
mmcli -b 1

# 8. Проверить NetworkManager connections
nmcli connection show
nmcli connection show gsm0
nmcli connection show gsm1
```

### Проверка Squid

```bash
# Статус сервиса
systemctl status squid

# Логи
tail -f /var/log/squid/access.log

# Тест прокси с Mac
curl -x http://138.2.138.243:3128 http://ifconfig.me

# Проверка исходящего IP
for i in {1..10}; do
  curl -x http://138.2.138.243:3128 http://ifconfig.me
  echo
  sleep 1
done
```

### Ожидаемый вывод (после исправления)

```bash
$ for i in {1..10}; do curl -x http://138.2.138.243:3128 http://ifconfig.me; echo; done
91.151.136.231   # wwan0
91.151.137.37    # wwan1
91.151.136.231   # wwan0
91.151.136.231   # wwan0
91.151.137.37    # wwan1
91.151.137.37    # wwan1
91.151.136.231   # wwan0
91.151.137.37    # wwan1
91.151.136.231   # wwan0
91.151.137.37    # wwan1
```

### Текущий вывод (проблема)

```bash
$ curl -x http://138.2.138.243:3128 http://ifconfig.me
188.169.117.42   # ❌ WiFi IP вместо модемного
```
