"""IP rotation logic."""

import asyncio
import logging
import time
from typing import Optional

from ..config import get_config
from ..schemas import RotationResult
from .modem import modem_manager
from .network import network_manager

logger = logging.getLogger(__name__)


class IPRotator:
    """Handles IP rotation for modems."""

    async def rotate(self, modem_id: int) -> RotationResult:
        """Rotate IP address for a modem by reconnecting."""
        start_time = time.time()
        config = get_config()
        connection_name = f"{config.modems.connection_prefix}{modem_id + 1}"

        # Get current modem info
        modem = await modem_manager.get_modem(modem_id)
        if not modem:
            return RotationResult(
                modem_id=modem_id,
                success=False,
                error="Modem not found",
                duration_seconds=time.time() - start_time,
            )

        old_ip = modem.ip_address

        try:
            # Step 1: Disconnect
            logger.info(f"Rotating IP for modem {modem_id}, disconnecting {connection_name}")
            await network_manager.connection_down(connection_name)

            # Wait for disconnect
            await asyncio.sleep(2)

            # Step 2: Reconnect
            logger.info(f"Reconnecting {connection_name}")
            success = await network_manager.connection_up(connection_name)
            if not success:
                return RotationResult(
                    modem_id=modem_id,
                    success=False,
                    old_ip=old_ip,
                    error="Failed to reconnect",
                    duration_seconds=time.time() - start_time,
                )

            # Step 3: Wait for new IP
            new_ip = await self._wait_for_ip(modem_id, old_ip, timeout=60)

            if not new_ip:
                return RotationResult(
                    modem_id=modem_id,
                    success=False,
                    old_ip=old_ip,
                    error="Timeout waiting for new IP",
                    duration_seconds=time.time() - start_time,
                )

            # Step 4: Flush route cache
            await network_manager.flush_routes()

            logger.info(f"IP rotated for modem {modem_id}: {old_ip} -> {new_ip}")

            return RotationResult(
                modem_id=modem_id,
                success=True,
                old_ip=old_ip,
                new_ip=new_ip,
                duration_seconds=time.time() - start_time,
            )

        except Exception as e:
            logger.exception(f"Error rotating IP for modem {modem_id}")
            return RotationResult(
                modem_id=modem_id,
                success=False,
                old_ip=old_ip,
                error=str(e),
                duration_seconds=time.time() - start_time,
            )

    async def _wait_for_ip(
        self, modem_id: int, old_ip: Optional[str], timeout: int = 60
    ) -> Optional[str]:
        """Wait for a new IP address to be assigned."""
        start = time.time()

        while time.time() - start < timeout:
            modem = await modem_manager.get_modem(modem_id)
            if modem and modem.ip_address:
                # If we got a different IP (or any IP if old was None)
                if old_ip is None or modem.ip_address != old_ip:
                    return modem.ip_address
            await asyncio.sleep(2)

        return None


# Global instance
ip_rotator = IPRotator()
