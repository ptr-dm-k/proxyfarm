# Руководство по устранению неисправностей

## Общие проблемы

### 1. Прокси возвращает WiFi IP вместо модемного

#### Симптомы
```bash
$ curl -x http://138.2.138.243:3128 http://ifconfig.me
188.169.117.42  # WiFi IP

# Ожидается один из:
91.151.136.x  # wwan0
91.151.137.x  # wwan1
```

#### Диагностика

```bash
# На Orange Pi проверить routing table
ssh root@192.168.50.111
ip route show default
```

**Проблема:** Если вывод показывает:
```
default via 192.168.50.1 dev wlan0 metric 600
```

**Должно быть:**
```
default
    nexthop via 10.231.254.1 dev wwan0 weight 1
    nexthop via 10.223.35.1 dev wwan1 weight 1
default via 192.168.50.1 dev wlan0 metric 1000
```

#### Причина
NetworkManager автоматически восстанавливает маршрут через WiFi с metric 600, который имеет приоритет над multipath маршрутом (metric 0).

#### Решение

**Вариант A: NetworkManager Dispatcher (рекомендуется)**
```bash
# На вашем Mac
cd /Users/petr/repo/proxyfarm
expect /tmp/ssh_install_dispatcher.exp
```

Это установит dispatcher script, который будет автоматически восстанавливать правильные маршруты при любых изменениях сети.

**Вариант B: Systemd Timer**
```bash
# На вашем Mac
cd /Users/petr/repo/proxyfarm
expect /tmp/ssh_install_service.exp
```

Это создаст systemd service, который будет проверять и восстанавливать маршруты каждые 5 минут.

**Вариант C: Ручное исправление**
```bash
# На Orange Pi
ssh root@192.168.50.111
cd /root/repo/proxyfarm
./scripts/setup_modem_routing.sh

# Проверить результат
ip route show default

# Тестировать
curl ifconfig.me
```

### 2. Multipath route исчезает после создания

#### Симптомы
```bash
# Создаем route
./scripts/setup_modem_routing.sh
# Успешно создан

# Через несколько секунд проверяем
ip route show default
# Route исчез или изменился обратно на WiFi
```

#### Причина
NetworkManager срабатывает на событие изменения сети и восстанавливает свою конфигурацию маршрутов.

#### Решение
Установить один из механизмов persistence (см. решение для проблемы #1).

### 3. Потеря SSH соединения после изменения WiFi route

#### Симптомы
```bash
# Пробуем подключиться
ssh root@192.168.50.111
# Operation timed out
```

#### Причина
Команда `nmcli connection modify <wifi> ipv4.never-default yes` полностью убирает default route через WiFi, что нарушает SSH доступ.

#### Решение
**НЕ используйте `ipv4.never-default yes` для WiFi!**

Вместо этого:
1. Оставьте WiFi default route но с высоким metric (1000)
2. Multipath route будет иметь приоритет (metric 0)
3. SSH доступ сохранится через WiFi

Если доступ уже потерян:
1. Физический доступ к Orange Pi
2. Подключить монитор и клавиатуру
3. Восстановить WiFi route:
```bash
nmcli connection modify <wifi-name> ipv4.never-default no
nmcli connection down <wifi-name>
nmcli connection up <wifi-name>
```

### 4. Медленные запросы через прокси (> 20 секунд)

#### Симптомы
```bash
$ time curl -x http://138.2.138.243:3128 http://ifconfig.me
# 29.5 seconds
```

#### Диагностика
```bash
# Проверить логи Squid
ssh root@192.168.50.111
tail -f /var/log/squid/access.log

# Искать признаки:
# - Много TCP_DENIED
# - Много TCP_MISS/TIMEOUT
# - Ошибки DNS
```

#### Причины
1. Устаревшие директивы Squid (dns_v4_first, persistent_connection_timeout)
2. Отсутствие DNS кеширования
3. Нет connection pooling
4. Проблемы с DNS резолвингом

#### Решение
```bash
# Обновить конфигурацию Squid
ssh root@192.168.50.111
cd /root/repo/proxyfarm
./scripts/setup_squid.sh
systemctl restart squid

# Проверить улучшение
curl -x http://138.2.138.243:3128 http://ifconfig.me
# Должно быть 1-3 секунды
```

**Правильная конфигурация:**
- ✅ DNS серверы: 8.8.8.8, 8.8.4.4
- ✅ Connection pooling включен
- ✅ pconn_timeout (не persistent_connection_timeout)
- ✅ Удалены obsolete директивы

### 5. Модем не подключается после ротации IP

#### Симптомы
```bash
curl -X POST localhost:8080/api/v1/modems/0/rotate
# Timeout или ошибка
```

#### Диагностика
```bash
# Проверить статус модема
mmcli -m 0

# State должен быть: connected
# Если: connecting, disconnecting, или failed

# Проверить bearer
mmcli -b 0
# Должен показывать IP address
```

#### Причины
1. Слабый сигнал
2. Проблемы с APN
3. SIM карта заблокирована
4. Превышен лимит данных

#### Решение
```bash
# 1. Проверить сигнал
mmcli -m 0 | grep signal
# Signal: 80% (хорошо), 20% (плохо)

# 2. Переподключить вручную
nmcli connection down gsm0
sleep 5
nmcli connection up gsm0

# 3. Проверить APN
nmcli connection show gsm0 | grep apn
# Должен быть: internet (или ваш APN)

# 4. Проверить баланс через USSD
curl -X POST localhost:8080/api/v1/modems/0/ussd \
  -H "Content-Type: application/json" \
  -d '{"command": "*100#"}'
```

### 6. VPN tunnel не работает

#### Симптомы
```bash
# С Mac
curl -x http://138.2.138.243:3128 http://ifconfig.me
# Connection refused или timeout
```

#### Диагностика
```bash
# На VPS проверить OpenVPN
ssh ubuntu@138.2.138.243
systemctl status openvpn@server

# Проверить tun0 интерфейс
ip addr show tun0
# Должен быть: 10.8.0.1

# На Orange Pi
ssh root@192.168.50.111
systemctl status openvpn@client
ip addr show tun0
# Должен быть: 10.8.0.2

# Ping через VPN
ping 10.8.0.1  # с Orange Pi
ping 10.8.0.2  # с VPS
```

#### Решение
```bash
# Перезапустить OpenVPN на обеих сторонах

# На VPS
systemctl restart openvpn@server

# На Orange Pi
systemctl restart openvpn@client

# Проверить connectivity
ping 10.8.0.1
```

### 7. Socat forwarder не работает на VPS

#### Симптомы
```bash
curl -x http://138.2.138.243:3128 http://ifconfig.me
# Connection refused
```

#### Диагностика
```bash
# На VPS
systemctl status socat-proxy
netstat -tlnp | grep 3128

# Должен быть:
# tcp  0  0 0.0.0.0:3128  0.0.0.0:*  LISTEN  12345/socat
```

#### Решение
```bash
# На VPS
systemctl restart socat-proxy

# Или установить заново
cd ~/proxyfarm
./scripts/setup_vps_proxy_forward.sh
```

## Диагностические команды

### Быстрая проверка системы

```bash
#!/bin/bash
echo "=== IP Addresses ==="
ip -4 addr show | grep inet

echo -e "\n=== Routing Table ==="
ip route show

echo -e "\n=== Default Routes ==="
ip route show default

echo -e "\n=== Modem Status ==="
mmcli -L
mmcli -m 0 --output-keyvalue | grep -E "modem.generic.state|modem.3gpp.registration|signal.quality"
mmcli -m 1 --output-keyvalue | grep -E "modem.generic.state|modem.3gpp.registration|signal.quality"

echo -e "\n=== Bearer Info ==="
mmcli -b 0 | grep -E "Status|IP address|Gateway"
mmcli -b 1 | grep -E "Status|IP address|Gateway"

echo -e "\n=== Network Connections ==="
nmcli connection show --active

echo -e "\n=== Squid Status ==="
systemctl status squid --no-pager | head -5

echo -e "\n=== Testing Outgoing IPs ==="
echo "Default route:"
curl -s --max-time 5 ifconfig.me || echo "Failed"

echo "wwan0:"
curl -s --max-time 5 --interface wwan0 ifconfig.me || echo "Failed"

echo "wwan1:"
curl -s --max-time 5 --interface wwan1 ifconfig.me || echo "Failed"
```

Сохраните как `check_system.sh` и запустите:
```bash
chmod +x check_system.sh
./check_system.sh
```

### Проверка балансировки нагрузки

```bash
#!/bin/bash
echo "Testing load balancing (10 requests)..."
for i in {1..10}; do
  IP=$(curl -s --max-time 10 ifconfig.me)
  echo "Request $i: $IP"
  sleep 1
done | sort | uniq -c
```

Ожидаемый результат:
```
5 91.151.136.231  # wwan0
5 91.151.137.37   # wwan1
```

Или хотя бы оба IP должны появиться в выводе.

### Мониторинг в реальном времени

```bash
# Terminal 1: Routing table
watch -n 1 'ip route show default'

# Terminal 2: Squid logs
tail -f /var/log/squid/access.log

# Terminal 3: System logs
journalctl -f | grep -E "NetworkManager|ModemManager|wwan"

# Terminal 4: Requests
while true; do
  curl -x http://138.2.138.243:3128 http://ifconfig.me
  sleep 2
done
```

## Логи

### Где найти логи

| Компонент | Путь к логам | Команда |
|-----------|--------------|---------|
| Squid | `/var/log/squid/access.log` | `tail -f /var/log/squid/access.log` |
| FastAPI | systemd journal | `journalctl -u proxyfarm.service -f` |
| Routing service | systemd journal | `journalctl -u modem-routing.service -f` |
| NetworkManager | systemd journal | `journalctl -u NetworkManager -f` |
| ModemManager | systemd journal | `journalctl -u ModemManager -f` |
| OpenVPN | systemd journal | `journalctl -u openvpn@client -f` |
| NM Dispatcher | syslog | `journalctl -f \| grep NM-Dispatcher` |

### Анализ логов Squid

```bash
# Последние 50 запросов
tail -50 /var/log/squid/access.log

# Статистика по кодам ответа
awk '{print $4}' /var/log/squid/access.log | sort | uniq -c

# Время ответов
awk '{print $2}' /var/log/squid/access.log | sort -n | tail -20

# Запросы от VPN клиентов
grep '10.8.0.1' /var/log/squid/access.log

# Ошибки
grep -E 'ERROR|DENIED|TIMEOUT' /var/log/squid/access.log
```

## Performance Tips

### 1. Оптимизация Squid

```squid
# /etc/squid/squid.conf

# Увеличить file descriptors
max_filedescriptors 4096

# DNS кеширование
dns_nameservers 8.8.8.8 8.8.4.4

# Connection pooling
client_persistent_connections on
server_persistent_connections on
pconn_timeout 1 minute

# Кеш в памяти для часто используемых объектов
cache_mem 256 MB
maximum_object_size_in_memory 512 KB
```

### 2. Системные оптимизации

```bash
# /etc/sysctl.conf

# Multipath hash policy (L4 hash)
net.ipv4.fib_multipath_hash_policy=1

# TCP optimizations
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_tw_reuse=1
net.core.somaxconn=4096
net.ipv4.tcp_max_syn_backlog=8192

# Apply changes
sysctl -p
```

### 3. ModemManager настройки

```bash
# Отключить автоматическое сканирование сетей (экономит батарею)
mmcli -m 0 --set-power-state-low  # когда не используется
mmcli -m 0 --set-power-state-on   # когда нужен
```

## Автоматизация отладки

### Создать скрипт диагностики

```bash
# /root/diagnostic.sh
#!/bin/bash
LOGFILE="/var/log/proxyfarm_diagnostic.log"

echo "=== Diagnostic started at $(date) ===" >> $LOGFILE

# Check routing
echo "--- Routing ---" >> $LOGFILE
ip route show >> $LOGFILE 2>&1

# Check modems
echo "--- Modems ---" >> $LOGFILE
mmcli -L >> $LOGFILE 2>&1

# Test connectivity
echo "--- Connectivity ---" >> $LOGFILE
for iface in wwan0 wwan1; do
  echo "Testing $iface:" >> $LOGFILE
  timeout 5 curl --interface $iface -s ifconfig.me >> $LOGFILE 2>&1 || echo "$iface failed" >> $LOGFILE
done

echo "--- Proxy test ---" >> $LOGFILE
timeout 5 curl -x http://localhost:3128 -s ifconfig.me >> $LOGFILE 2>&1 || echo "Proxy failed" >> $LOGFILE

echo "" >> $LOGFILE
```

Добавить в cron:
```bash
# Каждые 10 минут
*/10 * * * * /root/diagnostic.sh
```

## FAQ

### Q: Какой IP должен возвращать прокси?

**A:** Один из модемных IP:
- `91.151.136.x` (wwan0)
- `91.151.137.x` (wwan1)

**НЕ должен:** `188.169.117.42` (WiFi IP)

### Q: Как часто нужно ротировать IP?

**A:** Зависит от использования:
- Для веб-скрейпинга: каждые 100-1000 запросов
- Для обхода rate limits: при получении 429/403
- Профилактически: раз в час

### Q: Можно ли использовать больше 2 модемов?

**A:** Да, просто добавьте больше nexthop в multipath route:
```bash
ip route add default scope global \
  nexthop via GW0 dev wwan0 weight 1 \
  nexthop via GW1 dev wwan1 weight 1 \
  nexthop via GW2 dev wwan2 weight 1 \
  nexthop via GW3 dev wwan3 weight 1
```

### Q: Почему не использовать tcp_outgoing_address в Squid?

**A:** Потому что:
1. Squid не может балансировать между несколькими IP
2. Нужно было бы вручную чередовать адреса
3. Kernel multipath делает это автоматически и эффективнее
4. При ротации IP нужно перезапускать Squid

### Q: Как проверить работает ли балансировка?

**A:**
```bash
# Сделать много запросов и посчитать уникальные IP
for i in {1..100}; do
  curl -s -x http://138.2.138.243:3128 http://ifconfig.me
done | sort | uniq -c

# Должно быть примерно 50/50
```

### Q: Что делать если один модем медленнее?

**A:** Изменить веса в multipath route:
```bash
# Дать wwan0 в 2 раза больше трафика
ip route add default scope global \
  nexthop via GW0 dev wwan0 weight 2 \
  nexthop via GW1 dev wwan1 weight 1
```

### Q: Можно ли использовать это для Telegram/WhatsApp?

**A:** Да, но:
- Нужно настроить SOCKS5 прокси (в дополнение к HTTP)
- Или использовать приложения, поддерживающие HTTP CONNECT
- Telegram Desktop поддерживает HTTP прокси
