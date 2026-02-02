"""Background monitoring service."""

import asyncio
import logging

from ..config import get_config
from ..core.modem import modem_manager
from ..core.network import network_manager
from ..core.rotation import ip_rotator
from ..schemas import ModemState

logger = logging.getLogger(__name__)


class MonitorService:
    """Background service for monitoring modem health."""

    def __init__(self):
        self._running = False
        self._task = None

    async def start(self):
        """Start the monitor service."""
        config = get_config()
        if not config.monitor.enabled:
            logger.info("Monitor service disabled in config")
            return

        self._running = True
        self._task = asyncio.create_task(self._run())
        logger.info("Monitor service started")

    async def stop(self):
        """Stop the monitor service."""
        self._running = False
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
        logger.info("Monitor service stopped")

    async def _run(self):
        """Main monitoring loop."""
        config = get_config()
        interval = config.monitor.interval

        while self._running:
            try:
                await self._check_modems()
            except Exception as e:
                logger.exception(f"Error in monitor loop: {e}")

            await asyncio.sleep(interval)

    async def _check_modems(self):
        """Check health of all modems."""
        config = get_config()
        modems = await modem_manager.list_modems()

        for modem in modems:
            logger.debug(
                f"Modem {modem.id}: state={modem.state}, "
                f"ip={modem.ip_address}, signal={modem.signal_quality}%"
            )

            # Check if modem is not connected
            if modem.state != ModemState.CONNECTED:
                logger.warning(f"Modem {modem.id} is not connected (state: {modem.state})")

                if config.monitor.auto_reconnect:
                    logger.info(f"Attempting to reconnect modem {modem.id}")
                    await ip_rotator.rotate(modem.id)
                continue

            # Check if modem has IP
            if not modem.ip_address:
                logger.warning(f"Modem {modem.id} has no IP address")
                continue

            # Check internet connectivity
            if modem.interface:
                connected, external_ip = await network_manager.check_internet_connectivity(
                    modem.interface, config.monitor.health_check_url
                )
                if not connected:
                    logger.warning(
                        f"Modem {modem.id} ({modem.interface}) has no internet connectivity"
                    )
                else:
                    logger.debug(f"Modem {modem.id} external IP: {external_ip}")


# Global instance
monitor_service = MonitorService()
