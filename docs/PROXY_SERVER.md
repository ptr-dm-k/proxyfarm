# ProxyFarm Proxy Server

Python-based HTTP/HTTPS proxy server с поддержкой:
- ✅ HTTP и HTTPS (CONNECT туннели)
- ✅ Basic Authentication
- ✅ Привязка пользователя к модему
- ✅ Hot reload конфигурации
- ✅ Полный контроль routing

## Преимущества перед Squid

| Фича | Python Proxy | Squid |
|------|-------------|-------|
| HTTP/HTTPS | ✅ | ✅ |
| Привязка к интерфейсу | ✅ Явная через socket.bind() | ⚠️ Через fwmark или tcp_outgoing_address |
| Конфигурация | ✅ YAML, понятный | ⚠️ Специфичный синтаксис |
| Hot reload | ✅ SIGHUP, без downtime | ✅ squid -k reconfigure |
| Интеграция с API | ✅ Простая | ⚠️ Нужна генерация конфига |
| Метрики/логи | ✅ Легко добавить | ⚠️ Нужен парсинг логов |
| Debugging | ✅ Простой | ⚠️ Сложнее |
| Производительность | ⚠️ Хорошая (~5k req/s) | ✅ Отличная (~50k req/s) |

**Вывод**: Для 2 модемов Python proxy более чем достаточно и проще в управлении.

## Архитектура

```
Client (username:password)
    ↓
VPS:3128 (socat TCP forward)
    ↓ через OpenVPN
Orange Pi:3128 (Python Proxy)
    ↓
[check_credentials()] → username
    ↓
[modem = CONFIG['users'][username]['modem']]
    ↓
[source_ip = get_modem_ip(modem)]
    ↓
[socket.bind((source_ip, 0))]
    ↓
Запрос через wwan0 или wwan1
```

## Установка

### 1. Установить зависимости

```bash
cd /Users/petr/repo/proxyfarm
pip install -r requirements-proxy.txt
```

или на Orange Pi:
```bash
ssh root@192.168.50.111
cd /root/repo/proxyfarm
pip3 install pyyaml
```

### 2. Настроить конфигурацию

```bash
# Создать директорию для конфига
mkdir -p config

# Создать config/proxy.yaml
cp config/proxy.yaml config/proxy.yaml
# Отредактировать пользователей и пароли
nano config/proxy.yaml
```

### 3. Запустить proxy

```bash
# Напрямую (для теста)
python3 proxy_full.py

# Или через systemd
sudo cp systemd/proxyfarm-proxy.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable proxyfarm-proxy
sudo systemctl start proxyfarm-proxy
```

## Конфигурация

### config/proxy.yaml

```yaml
server:
  host: "0.0.0.0"
  port: 3128

users:
  alice:
    password: "secret123"
    modem: "wwan0"
    rate_limit: 60  # requests per minute (future)

  bob:
    password: "password456"
    modem: "wwan1"
    rate_limit: 120

modems:
  wwan0:
    id: 0
    name: "Modem 0"
    max_users: 10

  wwan1:
    id: 1
    name: "Modem 1"
    max_users: 10
```

## Управление

### Запуск

```bash
# Через systemd (рекомендуется)
sudo systemctl start proxyfarm-proxy

# Или напрямую
python3 /root/repo/proxyfarm/proxy_full.py
```

### Остановка

```bash
sudo systemctl stop proxyfarm-proxy
```

### Перезагрузка конфига (без downtime!)

```bash
# Способ 1: SIGHUP signal
sudo systemctl reload proxyfarm-proxy

# Способ 2: Напрямую
sudo kill -HUP $(pgrep -f proxy_full.py)
```

### Просмотр логов

```bash
# Через journalctl
sudo journalctl -u proxyfarm-proxy -f

# Или напрямую если запущено в терминале
```

### Проверка статуса

```bash
sudo systemctl status proxyfarm-proxy
```

## Тестирование

### Локальное тестирование (на Orange Pi)

```bash
# HTTP запрос
curl -x http://alice:secret123@localhost:3128 http://ifconfig.me

# HTTPS запрос
curl -x http://alice:secret123@localhost:3128 https://ifconfig.me

# Через разных пользователей
curl -x http://bob:password456@localhost:3128 https://api.ipify.org
```

### Удаленное тестирование (через VPS)

```bash
# Через VPS (если socat настроен)
curl -x http://alice:secret123@138.2.138.243:3128 https://ifconfig.me

# Должен вернуть IP модема alice (wwan0)
```

### Автоматическое тестирование

```bash
chmod +x test_proxy.sh
./test_proxy.sh
```

## Добавление нового пользователя

### Способ 1: Редактировать YAML

```bash
# 1. Редактируем config/proxy.yaml
nano config/proxy.yaml

# Добавляем:
users:
  newuser:
    password: "newpass"
    modem: "wwan0"

# 2. Перезагружаем конфиг
sudo systemctl reload proxyfarm-proxy

# 3. Проверяем
curl -x http://newuser:newpass@localhost:3128 https://ifconfig.me
```

### Способ 2: Через Management API (будущее)

```bash
# POST /api/v1/users
curl -X POST http://orangepi:8080/api/v1/users \
  -H "X-API-Key: secret" \
  -d '{
    "username": "newuser",
    "password": "newpass",
    "modem": "wwan0"
  }'

# API автоматически обновит config/proxy.yaml и отправит SIGHUP
```

## Интеграция с VPS

На VPS должен быть настроен socat для проброса трафика:

```bash
# VPS: /etc/systemd/system/socat-proxy.service
[Service]
ExecStart=/usr/bin/socat TCP4-LISTEN:3128,fork,reuseaddr TCP4:10.8.0.2:3128
```

Тогда:
```
Client → VPS:3128 → OpenVPN → Orange Pi:3128 (Python Proxy) → wwan0/wwan1
```

## Troubleshooting

### Proxy не запускается

```bash
# Проверяем логи
sudo journalctl -u proxyfarm-proxy -n 50

# Проверяем что порт 3128 свободен
sudo netstat -tlnp | grep 3128

# Проверяем конфиг
python3 -c "import yaml; print(yaml.safe_load(open('config/proxy.yaml')))"
```

### Ошибка "Modem unavailable"

```bash
# Проверяем что модемы подключены
ip addr show wwan0
ip addr show wwan1

# Проверяем IP модемов
ip -4 addr show wwan0 | grep inet
```

### Запросы не балансируются

```bash
# Проверяем конфиг - какому пользователю какой модем назначен
cat config/proxy.yaml | grep -A 2 "users:"

# Тестируем через разных пользователей
curl -x http://user1:pass@proxy:3128 ifconfig.me
curl -x http://user2:pass@proxy:3128 ifconfig.me
```

### Hot reload не работает

```bash
# Проверяем что процесс получает signal
sudo kill -HUP $(pgrep -f proxy_full.py)

# Проверяем логи
sudo journalctl -u proxyfarm-proxy -f
# Должно быть: "Received SIGHUP, reloading config..."
```

## Дальнейшее развитие

### Планируется добавить:

1. **Rate limiting** - ограничение запросов per user
2. **Метрики** - Prometheus metrics endpoint
3. **Connection pooling** - переиспользование TCP соединений
4. **Автоматическое назначение модемов** - балансировка нагрузки
5. **Management API** - FastAPI для управления пользователями
6. **IP rotation** - автоматическая ротация IP через интервал
7. **Access logs** - детальные логи запросов

### Код для rate limiting

```python
# В handle_client() перед обработкой запроса
user_config = CONFIG['users'][username]
rate_limit = user_config.get('rate_limit', 0)

if rate_limit > 0:
    # Проверяем количество запросов за последнюю минуту
    if not check_rate_limit(username, rate_limit):
        client_writer.write(b'HTTP/1.1 429 Too Many Requests\r\n\r\n')
        await client_writer.drain()
        client_writer.close()
        return
```

## См. также

- [ARCHITECTURE.md](ARCHITECTURE.md) - Архитектура ProxyFarm
- [LOAD_BALANCING.md](LOAD_BALANCING.md) - Как работает балансировка
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Решение проблем
