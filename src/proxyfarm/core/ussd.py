"""USSD command handling."""

import logging

from ..schemas import USSDResponse
from .modem import modem_manager

logger = logging.getLogger(__name__)


class USSDHandler:
    """Handles USSD commands."""

    async def send(self, modem_id: int, command: str) -> USSDResponse:
        """Send USSD command to a modem."""
        logger.info(f"Sending USSD '{command}' to modem {modem_id}")

        success, response = await modem_manager.send_ussd(modem_id, command)

        if success:
            logger.info(f"USSD response from modem {modem_id}: {response}")
        else:
            logger.error(f"USSD failed for modem {modem_id}: {response}")

        return USSDResponse(
            modem_id=modem_id,
            command=command,
            response=response,
            success=success,
            error=None if success else response,
        )


# Global instance
ussd_handler = USSDHandler()
