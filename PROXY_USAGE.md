# ProxyFarm - Использование прокси

## Публичный доступ через VPS

### Настройка (уже выполнена)
На VPS настроен port forwarding на Orange Pi через VPN:
```bash
# На VPS выполнено:
sudo bash scripts/setup_vps_proxy_forward.sh
```

Systemd сервис `proxy-forward` автоматически запускается при старте системы и пересылает запросы с VPS:3128 на Orange Pi:3128 через VPN туннель.

### Использование прокси

#### Базовое использование
```bash
# HTTP запросы
curl -x http://138.2.138.243:3128 http://ifconfig.me
curl -x http://138.2.138.243:3128 http://ipinfo.io/ip

# HTTPS запросы (Squid поддерживает CONNECT)
curl -x http://138.2.138.243:3128 https://api.ipify.org
```

#### С аутентификацией API (для браузеров/приложений)
Прокси не требует аутентификации для внешних подключений, но доступ ограничен на уровне VPN ACL.

#### Настройка в браузере
- **Прокси сервер**: 138.2.138.243
- **Порт**: 3128
- **Тип**: HTTP/HTTPS

#### Использование в коде

**Python (requests):**
```python
import requests

proxies = {
    'http': 'http://138.2.138.243:3128',
    'https': 'http://138.2.138.243:3128'
}

response = requests.get('http://ifconfig.me', proxies=proxies)
print(response.text)  # IP вашего LTE модема
```

**Node.js:**
```javascript
const axios = require('axios');

axios.get('http://ifconfig.me', {
  proxy: {
    host: '138.2.138.243',
    port: 3128
  }
}).then(response => {
  console.log(response.data);
});
```

**cURL:**
```bash
# Простой запрос
curl -x http://138.2.138.243:3128 http://ifconfig.me

# С verbose для отладки
curl -v -x http://138.2.138.243:3128 http://ifconfig.me

# Сохранить результат
curl -x http://138.2.138.243:3128 http://ipinfo.io/json -o result.json
```

## Локальное использование (через VPN)

Если вы подключены к VPN, можете использовать прямой адрес Orange Pi:

```bash
curl -x http://10.8.0.2:3128 http://ifconfig.me
```

## Управление через ProxyFarm API

### Проверка статуса прокси
```bash
curl -H 'X-API-Key: proxyfarm-secret-key-2026' \
     http://192.168.50.111:8080/api/v1/proxy/status
```

### Ротация IP модема
```bash
# Переподключить модем для получения нового IP
curl -X POST \
     -H 'X-API-Key: proxyfarm-secret-key-2026' \
     http://192.168.50.111:8080/api/v1/modems/0/rotate
```

После ротации Squid автоматически обновит конфигурацию.

### Перегенерация конфига Squid
```bash
curl -X POST \
     -H 'X-API-Key: proxyfarm-secret-key-2026' \
     http://192.168.50.111:8080/api/v1/proxy/reconfigure
```

## Производительность

### Типичные времена ответа

**Локально (на Orange Pi):**
- Без прокси: ~0.27 сек
- Через Squid: ~0.32 сек

**С Mac/PC через VPS:**
- Первый запрос: ~3 сек (DNS resolution)
- Последующие: ~1.4-2.6 сек (DNS в кэше)

### Оптимизация

Squid настроен с:
- DNS кэширование (6 часов для положительных ответов)
- Connection pooling (persistent connections)
- Оптимизированные таймауты
- Кэш на 2048 FQDN записей

## Мониторинг

### Проверка статуса сервисов

**На VPS:**
```bash
# Статус forwarding сервиса
sudo systemctl status proxy-forward

# Логи
sudo journalctl -u proxy-forward -f
```

**На Orange Pi:**
```bash
# Статус Squid
sudo systemctl status squid

# Access log
sudo tail -f /var/log/squid/access.log

# Cache log
sudo tail -f /var/log/squid/cache.log
```

### Проверка соединения
```bash
# С VPS проверить доступность Orange Pi
ping 10.8.0.2
nc -zv 10.8.0.2 3128

# Тест прокси
curl -v -x http://127.0.0.1:3128 http://ifconfig.me
```

## Балансировка нагрузки

Когда активны несколько модемов, Squid использует kernel multipath routing для автоматической балансировки запросов между всеми доступными модемами.

Проверить активные модемы:
```bash
curl -H 'X-API-Key: proxyfarm-secret-key-2026' \
     http://192.168.50.111:8080/api/v1/modems
```

## Безопасность

⚠️ **Важно**: Прокси доступен публично через VPS. Рекомендации:

1. Используйте сильный пароль для VPS
2. Настройте firewall (UFW) для ограничения доступа к порту 3128
3. Рассмотрите добавление аутентификации в Squid
4. Мониторьте логи на предмет злоупотреблений

### Ограничение доступа по IP (опционально)

На VPS можно настроить UFW:
```bash
# Разрешить только с определенных IP
sudo ufw allow from YOUR_IP to any port 3128

# Заблокировать остальных
sudo ufw deny 3128
```

## Troubleshooting

### Прокси не отвечает
1. Проверьте VPN: `ping 10.8.0.2` (с VPS)
2. Проверьте forwarding: `sudo systemctl status proxy-forward`
3. Проверьте Squid: `sudo systemctl status squid` (на Orange Pi)

### Медленные запросы
1. Проверьте пинг: `ping -c 5 10.8.0.2`
2. Проверьте логи Squid: `tail -100 /var/log/squid/cache.log`
3. Перезапустите Squid: `sudo systemctl restart squid`

### Ошибка 400/502
- Проверьте конфигурацию Squid: `sudo squid -k parse`
- Проверьте логи: `sudo tail -50 /var/log/squid/cache.log`
