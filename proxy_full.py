#!/usr/bin/env python3
"""
ProxyFarm HTTP/HTTPS Proxy Server
Full implementation with asyncio
Supports user authentication and per-user modem assignment
"""
import asyncio
import base64
import logging
import signal
import socket
import subprocess
import sys
from pathlib import Path
from typing import Optional, Tuple
from urllib.parse import urlparse

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML not installed. Run: pip install pyyaml")
    sys.exit(1)

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration (global, will be reloaded on SIGHUP)
CONFIG = {}
CONFIG_PATH = Path(__file__).parent / 'config' / 'proxy.yaml'


def load_config(config_path: Path = CONFIG_PATH) -> dict:
    """Загрузить конфигурацию из YAML"""
    try:
        with open(config_path) as f:
            config = yaml.safe_load(f)
            logger.info(f"Config loaded from {config_path}")
            return config
    except FileNotFoundError:
        logger.warning(f"Config file not found: {config_path}, using defaults")
        return {
            'server': {'host': '0.0.0.0', 'port': 3128},
            'users': {
                'user1': {'modem': 'wwan0', 'password': 'pass1'},
                'user2': {'modem': 'wwan1', 'password': 'pass2'},
            },
            'modems': {
                'wwan0': {},
                'wwan1': {},
            }
        }
    except Exception as e:
        logger.error(f"Failed to load config: {e}")
        sys.exit(1)


def reload_config_handler(signum, frame):
    """Signal handler для перезагрузки конфига"""
    global CONFIG
    logger.info("Received SIGHUP, reloading config...")
    CONFIG = load_config()
    logger.info("Config reloaded successfully")


# Загружаем конфиг при старте
CONFIG = load_config()

# Регистрируем signal handler для SIGHUP
signal.signal(signal.SIGHUP, reload_config_handler)


def get_modem_ip(interface: str) -> Optional[str]:
    """Получить IP адрес модема"""
    try:
        result = subprocess.run(
            ['ip', '-4', 'addr', 'show', interface],
            capture_output=True, text=True, timeout=2
        )
        for line in result.stdout.split('\n'):
            if 'inet ' in line:
                ip = line.split()[1].split('/')[0]
                return ip
    except Exception as e:
        logger.error(f"Failed to get IP for {interface}: {e}")
    return None


def parse_proxy_auth(auth_line: str) -> Optional[Tuple[str, str]]:
    """Парсинг Proxy-Authorization header"""
    try:
        if not auth_line.startswith('Basic '):
            return None

        creds = base64.b64decode(auth_line[6:]).decode('utf-8')
        username, password = creds.split(':', 1)
        return username, password
    except Exception as e:
        logger.warning(f"Auth parse error: {e}")
        return None


def check_credentials(username: str, password: str) -> bool:
    """Проверка credentials"""
    if username not in CONFIG['users']:
        return False
    return CONFIG['users'][username]['password'] == password


async def create_bound_connection(host: str, port: int, source_ip: str) -> Tuple[asyncio.StreamReader, asyncio.StreamWriter]:
    """
    Создать TCP соединение с привязкой к source IP
    """
    # Создаем socket с привязкой к source IP
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

    # Bind к source IP модема
    sock.bind((source_ip, 0))

    # Делаем non-blocking
    sock.setblocking(False)

    # Подключаемся асинхронно
    loop = asyncio.get_event_loop()
    await loop.sock_connect(sock, (host, port))

    # Оборачиваем в StreamReader/Writer
    reader, writer = await asyncio.open_connection(sock=sock)

    return reader, writer


async def tunnel_data(reader_src: asyncio.StreamReader, writer_dst: asyncio.StreamWriter, direction: str):
    """Туннелирование данных в одном направлении"""
    try:
        while True:
            data = await reader_src.read(8192)
            if not data:
                break

            writer_dst.write(data)
            await writer_dst.drain()

    except Exception as e:
        logger.debug(f"Tunnel {direction} closed: {e}")
    finally:
        try:
            writer_dst.close()
            await writer_dst.wait_closed()
        except Exception:
            pass


async def handle_connect(
    client_reader: asyncio.StreamReader,
    client_writer: asyncio.StreamWriter,
    target_host: str,
    target_port: int,
    username: str,
    modem: str
):
    """Обработка HTTPS CONNECT туннеля"""

    source_ip = get_modem_ip(modem)
    if not source_ip:
        client_writer.write(b'HTTP/1.1 502 Bad Gateway\r\n\r\n')
        await client_writer.drain()
        client_writer.close()
        return

    logger.info(f"{username} ({modem}): CONNECT {target_host}:{target_port}")

    try:
        # Создаем соединение к target через нужный модем
        server_reader, server_writer = await create_bound_connection(
            target_host, target_port, source_ip
        )

        # Отправляем клиенту 200 Connection Established
        client_writer.write(b'HTTP/1.1 200 Connection Established\r\n\r\n')
        await client_writer.drain()

        # Туннелируем данные в обе стороны
        await asyncio.gather(
            tunnel_data(client_reader, server_writer, f"{username} client→server"),
            tunnel_data(server_reader, client_writer, f"{username} server→client")
        )

    except Exception as e:
        logger.error(f"CONNECT tunnel error: {e}")
        try:
            client_writer.write(b'HTTP/1.1 502 Bad Gateway\r\n\r\n')
            await client_writer.drain()
        except Exception:
            pass
    finally:
        client_writer.close()
        try:
            await client_writer.wait_closed()
        except Exception:
            pass


async def handle_http(
    client_reader: asyncio.StreamReader,
    client_writer: asyncio.StreamWriter,
    request_line: str,
    headers: dict,
    username: str,
    modem: str
):
    """Обработка обычного HTTP запроса"""

    source_ip = get_modem_ip(modem)
    if not source_ip:
        client_writer.write(b'HTTP/1.1 502 Bad Gateway\r\n\r\n')
        await client_writer.drain()
        client_writer.close()
        return

    # Parse request: GET http://example.com/path HTTP/1.1
    parts = request_line.split()
    if len(parts) != 3:
        client_writer.write(b'HTTP/1.1 400 Bad Request\r\n\r\n')
        await client_writer.drain()
        client_writer.close()
        return

    method, url, http_version = parts

    # Parse URL
    parsed = urlparse(url)
    target_host = parsed.hostname
    target_port = parsed.port or 80
    target_path = parsed.path or '/'
    if parsed.query:
        target_path += '?' + parsed.query

    logger.info(f"{username} ({modem}): {method} {target_host}{target_path}")

    try:
        # Создаем соединение к target через нужный модем
        server_reader, server_writer = await create_bound_connection(
            target_host, target_port, source_ip
        )

        # Формируем HTTP запрос к серверу
        request_headers = f"{method} {target_path} {http_version}\r\n"

        # Копируем headers, убираем proxy-специфичные
        for key, value in headers.items():
            if key.lower() not in ('proxy-authorization', 'proxy-connection'):
                request_headers += f"{key}: {value}\r\n"

        # Добавляем Host если нет
        if 'host' not in [k.lower() for k in headers.keys()]:
            request_headers += f"Host: {target_host}\r\n"

        request_headers += "\r\n"

        # Отправляем запрос
        server_writer.write(request_headers.encode('utf-8'))

        # Если есть тело запроса (POST, PUT)
        if 'content-length' in headers:
            content_length = int(headers['content-length'])
            body = await client_reader.readexactly(content_length)
            server_writer.write(body)

        await server_writer.drain()

        # Читаем ответ от сервера и пересылаем клиенту
        while True:
            data = await server_reader.read(8192)
            if not data:
                break

            client_writer.write(data)
            await client_writer.drain()

    except Exception as e:
        logger.error(f"HTTP request error: {e}")
        try:
            client_writer.write(b'HTTP/1.1 502 Bad Gateway\r\n\r\n')
            await client_writer.drain()
        except Exception:
            pass
    finally:
        client_writer.close()
        try:
            await client_writer.wait_closed()
        except Exception:
            pass


async def handle_client(client_reader: asyncio.StreamReader, client_writer: asyncio.StreamWriter):
    """Главный handler для клиента"""

    addr = client_writer.get_extra_info('peername')
    logger.info(f"New connection from {addr}")  # Changed to INFO

    try:
        # Читаем первую строку запроса
        request_line = await client_reader.readline()
        if not request_line:
            logger.warning(f"Empty request from {addr}")
            return

        request_line = request_line.decode('utf-8').strip()
        logger.info(f"Request: {request_line}")

        # Читаем headers
        headers = {}
        while True:
            line = await client_reader.readline()
            if not line or line == b'\r\n':
                break

            line = line.decode('utf-8').strip()
            if ':' in line:
                key, value = line.split(':', 1)
                headers[key.strip().lower()] = value.strip()

        # Проверяем авторизацию
        auth_header = headers.get('proxy-authorization', '')
        logger.info(f"Auth header: {auth_header[:50] if auth_header else 'None'}")
        auth = parse_proxy_auth(auth_header)

        if not auth:
            # 407 Proxy Authentication Required
            logger.warning(f"No auth from {addr}, sending 407")
            response = (
                b'HTTP/1.1 407 Proxy Authentication Required\r\n'
                b'Proxy-Authenticate: Basic realm="ProxyFarm"\r\n'
                b'Content-Length: 0\r\n'
                b'\r\n'
            )
            client_writer.write(response)
            await client_writer.drain()
            client_writer.close()
            return

        username, password = auth
        logger.info(f"Auth attempt: user={username}")

        if not check_credentials(username, password):
            # 403 Forbidden
            logger.warning(f"Invalid credentials for {username} from {addr}")
            client_writer.write(b'HTTP/1.1 403 Forbidden\r\n\r\n')
            await client_writer.drain()
            client_writer.close()
            return

        logger.info(f"Authenticated: {username}")

        # Определяем модем для пользователя
        modem = CONFIG['users'][username]['modem']

        # Определяем тип запроса
        if request_line.startswith('CONNECT '):
            # HTTPS туннель
            target = request_line.split()[1]
            target_host, target_port = target.split(':')
            target_port = int(target_port)

            await handle_connect(client_reader, client_writer, target_host, target_port, username, modem)
        else:
            # HTTP запрос
            await handle_http(client_reader, client_writer, request_line, headers, username, modem)

    except Exception as e:
        logger.error(f"Client handler error: {e}")
    finally:
        try:
            client_writer.close()
            await client_writer.wait_closed()
        except Exception:
            pass


async def main():
    """Главная функция"""

    # Проверяем доступность модемов
    logger.info("Checking modems...")
    for modem in CONFIG['modems'].keys():
        ip = get_modem_ip(modem)
        if ip:
            logger.info(f"  {modem}: {ip}")
        else:
            logger.warning(f"  {modem}: not available")

    # Получаем настройки сервера из конфига
    host = CONFIG.get('server', {}).get('host', '0.0.0.0')
    port = CONFIG.get('server', {}).get('port', 3128)

    # Запускаем сервер
    server = await asyncio.start_server(
        handle_client,
        host=host,
        port=port
    )

    addr = server.sockets[0].getsockname()
    logger.info(f"ProxyFarm proxy server listening on {addr[0]}:{addr[1]}")
    logger.info("Send SIGHUP to reload config: kill -HUP <pid>")

    async with server:
        await server.serve_forever()


if __name__ == '__main__':
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Shutting down...")
