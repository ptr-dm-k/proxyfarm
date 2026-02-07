# ProxyFarm Scripts

Организованная структура скриптов для установки и управления ProxyFarm.

## Структура

```
scripts/
├── install.sh              # 🚀 Главная точка входа (интерактивное меню)
├── uninstall.sh            # 🗑️  Удаление всех настроек (кроме OpenVPN)
├── check.sh                # 🔍 Диагностика системы
├── install_app.sh          # 📦 Установка Python приложения
│
├── setup/                  # Скрипты настройки компонентов
│   ├── squid.sh           # Настройка Squid proxy
│   ├── routing.sh         # Настройка multipath routing
│   ├── nm-dispatcher.sh   # Установка NetworkManager dispatcher
│   ├── systemd-service.sh # Установка Systemd service
│   └── vps.sh             # Настройка VPS forwarding
│
├── lib/                    # Общие библиотеки и функции
│   └── common.sh          # Общие функции (логирование, проверки)
│
└── backup/                 # Автоматические резервные копии
```

## Использование

### 🚀 Быстрая установка

**На Orange Pi:**
```bash
cd /root/repo/proxyfarm/scripts
sudo ./install.sh
```

Выберите опцию 1 (Install ALL) для полной установки.

### 📋 Интерактивное меню

```bash
sudo ./install.sh
```

Меню позволяет:
- Установить все компоненты сразу
- Установить отдельные компоненты
- Проверить статус системы
- Переустановить/починить маршрутизацию
- Удалить ProxyFarm

### 🔍 Проверка системы

```bash
./check.sh
```

Показывает:
- IP адреса всех интерфейсов
- Таблицу маршрутизации
- Статус модемов и bearers
- Статус Squid и других сервисов
- Результаты тестов исходящих IP

### 🗑️ Удаление

```bash
sudo ./uninstall.sh
```

**Удаляет:**
- Squid конфигурацию (с бэкапом)
- Multipath routing
- NetworkManager dispatcher
- Systemd routing service
- ProxyFarm приложение

**Сохраняет:**
- OpenVPN конфигурацию
- Модемные соединения (gsm0, gsm1)
- NetworkManager и ModemManager

## Компоненты установки

### 1. Squid Proxy (`setup/squid.sh`)

Устанавливает и настраивает Squid:
- HTTP/HTTPS прокси на порту 3128
- Доступ только с VPN сети (10.8.0.0/24)
- DNS кеширование
- Connection pooling
- Оптимизация производительности

**Использование:**
```bash
./setup/squid.sh
```

### 2. Multipath Routing (`setup/routing.sh`)

Настраивает маршрутизацию через модемы:
- Создает multipath route через wwan0 и wwan1
- Балансировка по L4 hash (source IP + dest IP + ports)
- WiFi как backup с metric 1000
- Автоматическое вычисление gateway

**Использование:**
```bash
./setup/routing.sh
```

### 3. NetworkManager Dispatcher (`setup/nm-dispatcher.sh`)

Устанавливает dispatcher для автоматического восстановления маршрутов:
- Срабатывает при любых изменениях сети
- Автоматически запускает `routing.sh`
- Логирует события в syslog

**Использование:**
```bash
./setup/nm-dispatcher.sh

# Просмотр логов:
journalctl -f | grep "ProxyFarm NM-Dispatcher"
tail -f /var/log/proxyfarm_routing.log
```

### 4. Systemd Service (`setup/systemd-service.sh`)

Альтернативный подход - периодическая проверка:
- Запускается при загрузке
- Проверяет маршруты каждые 5 минут
- Автоматически восстанавливает при сбоях

**Использование:**
```bash
./setup/systemd-service.sh

# Управление:
systemctl status modem-routing.timer
systemctl restart modem-routing.service
journalctl -u modem-routing -f
```

### 5. VPS Forwarding (`setup/vps.sh`)

Настраивает проброс прокси на VPS:
- Socat для TCP forwarding
- VPS:3128 → Orange Pi:3128 через VPN
- Systemd service для автозапуска

**⚠️ Запускать на VPS, не на Orange Pi!**

```bash
# На VPS:
./setup/vps.sh
```

## Общие функции (lib/common.sh)

Библиотека предоставляет:

### Логирование
```bash
log_info "Информационное сообщение"
log_success "Успешное выполнение"
log_warning "Предупреждение"
log_error "Ошибка"
```

### Проверки
```bash
check_root                    # Проверка прав root
command_exists "mmcli"        # Проверка наличия команды
check_dependencies mmcli nmcli  # Проверка зависимостей
```

### Утилиты
```bash
backup_file "/etc/squid/squid.conf" "squid.conf"
safe_remove "/path/to/file" "backup_name"
service_exists "squid"
service_is_active "squid"
stop_service "squid"
```

### Сетевые функции
```bash
get_modem_interfaces         # Список wwan интерфейсов
count_modems                 # Количество модемов
has_multipath_route         # Проверка multipath
get_wifi_connection         # Имя WiFi соединения
```

### Проверки конфигурации
```bash
has_nm_dispatcher           # Dispatcher установлен?
has_routing_service         # Systemd service установлен?
has_squid_config           # Squid настроен?
```

### UI
```bash
print_header "Заголовок"
print_step "Шаг установки"
confirm "Продолжить?" "y"    # y/n по умолчанию
press_enter
```

## Примеры использования

### Полная установка с нуля

```bash
# 1. Установить зависимости
apt update
apt install -y squid modemmanager network-manager openvpn

# 2. Запустить установщик
cd /root/repo/proxyfarm/scripts
sudo ./install.sh

# 3. Выбрать "1) Install ALL"

# 4. Проверить результат
./check.sh
curl ifconfig.me  # Должен вернуть 91.151.x.x
```

### Переустановка только маршрутизации

```bash
sudo ./install.sh
# Выбрать "8) Reinstall/Repair Routing"
```

### Ручная настройка компонентов

```bash
# Настроить Squid
sudo ./setup/squid.sh

# Настроить маршрутизацию
sudo ./setup/routing.sh

# Установить dispatcher для persistence
sudo ./setup/nm-dispatcher.sh

# Проверить
./check.sh
```

### Смена подхода persistence

```bash
# Если установлен dispatcher, но хотите использовать timer:

# 1. Удалить dispatcher
sudo rm /etc/NetworkManager/dispatcher.d/99-modem-routing

# 2. Установить systemd service
sudo ./setup/systemd-service.sh
```

### Полное удаление

```bash
sudo ./uninstall.sh
# Подтвердить удаление

# Проверить
ip route show
# Должен остаться только WiFi route
```

## Логи и отладка

### Где искать логи

```bash
# Squid
tail -f /var/log/squid/access.log
journalctl -u squid -f

# NetworkManager Dispatcher
journalctl -f | grep "ProxyFarm NM-Dispatcher"
tail -f /var/log/proxyfarm_routing.log

# Systemd Routing Service
journalctl -u modem-routing.service -f

# Все события ProxyFarm
journalctl -f | grep ProxyFarm
```

### Отладка проблем

```bash
# 1. Полная диагностика
./check.sh

# 2. Проверить маршруты
ip route show default

# 3. Проверить модемы
mmcli -L
mmcli -m 0
mmcli -m 1

# 4. Тестировать каждый интерфейс
curl --interface wwan0 ifconfig.me
curl --interface wwan1 ifconfig.me

# 5. Переустановить маршрутизацию
sudo ./setup/routing.sh

# 6. Проверить Squid
systemctl status squid
curl -x http://localhost:3128 http://ifconfig.me
```

## Резервные копии

Все изменения автоматически бэкапятся в `backup/` с timestamp:

```bash
ls -la backup/
# squid.conf.20260207_123045
# nm-dispatcher-routing.20260207_123046
# uninstall_20260207_123500/
```

Восстановление из бэкапа:
```bash
# Найти нужный бэкап
ls -la backup/ | grep squid

# Восстановить
sudo cp backup/squid.conf.20260207_123045 /etc/squid/squid.conf
sudo systemctl restart squid
```

## Переменные окружения

### Пути (в lib/common.sh)

- `SCRIPT_DIR` - папка scripts/
- `PROJECT_ROOT` - корень проекта
- `SETUP_DIR` - scripts/setup/
- `BACKUP_DIR` - scripts/backup/

### Цвета

- `RED` - ошибки
- `GREEN` - успех
- `YELLOW` - предупреждения
- `BLUE` - информация
- `NC` - сброс цвета

## Требования

### Обязательные пакеты

```bash
apt install -y \
  modemmanager \
  network-manager \
  squid \
  curl \
  iproute2
```

### Опциональные

```bash
# Для VPN
apt install -y openvpn

# Для expect скриптов (удаленное управление)
apt install -y expect

# Для Python приложения
apt install -y python3 python3-pip python3-venv
```

### Аппаратные требования

- 2+ USB LTE модемов
- WiFi или Ethernet для управления
- Orange Pi или аналог с Ubuntu/Armbian

## FAQ

**Q: Какой подход выбрать - dispatcher или systemd timer?**

A: NetworkManager Dispatcher (рекомендуется):
- Реагирует мгновенно на изменения сети
- Более "нативный" для Linux
- Меньше overhead

Systemd Timer:
- Проще для отладки (явное расписание)
- Независим от NetworkManager
- Подходит если dispatcher не работает

**Q: Можно ли установить оба подхода?**

A: Технически да, но не рекомендуется. Они будут конфликтовать. Выберите один.

**Q: Как проверить что routing persistence работает?**

A:
```bash
# 1. Проверить текущие маршруты
ip route show default

# 2. Изменить что-то в сети (например, отключить/включить WiFi)
nmcli radio wifi off
sleep 2
nmcli radio wifi on

# 3. Подождать 5-10 секунд

# 4. Проверить что multipath route восстановился
ip route show default
# Должен быть nexthop via ... dev wwan0 ... nexthop via ... dev wwan1
```

**Q: Скрипты требуют root?**

A: Да, все скрипты кроме `check.sh` требуют sudo/root для изменения системных настроек.

**Q: Где хранятся старые скрипты?**

A: Старые несовместимые скрипты перемещены:
- `install.sh` → `install_app.sh` (установка Python приложения)
- `check_system.sh` → `check.sh` (короткое имя)
- Устаревшие: `install_nm_dispatcher.sh`, `install_routing_service.sh`

## Поддержка

Проблемы или вопросы:
- 📖 [Architecture Documentation](../ARCHITECTURE.md)
- 🔧 [Troubleshooting Guide](../docs/TROUBLESHOOTING.md)
- 📚 [Quick Reference](../docs/QUICK_REFERENCE.md)
