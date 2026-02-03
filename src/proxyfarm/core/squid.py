"""
Squid proxy management module.
Handles dynamic reconfiguration of Squid based on active modem IPs.
"""

import asyncio
import logging
from pathlib import Path
from typing import Optional

from .network import NetworkManager

logger = logging.getLogger(__name__)


class SquidManager:
    """Manages Squid proxy configuration and lifecycle."""

    def __init__(self):
        self.network_manager = NetworkManager()
        self.setup_script = Path("/opt/proxyfarm/scripts/setup_squid.sh")
        self.squid_conf = Path("/etc/squid/squid.conf")

    async def reconfigure(self) -> bool:
        """
        Reconfigure Squid based on current wwan interfaces and IPs.
        Runs setup_squid.sh script which regenerates config and restarts Squid.

        Returns:
            True if reconfiguration was successful, False otherwise.
        """
        if not self.setup_script.exists():
            logger.error(f"Squid setup script not found: {self.setup_script}")
            return False

        logger.info("Reconfiguring Squid proxy based on current modem IPs...")

        try:
            process = await asyncio.create_subprocess_exec(
                str(self.setup_script),
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )

            stdout, stderr = await process.communicate()

            if process.returncode != 0:
                logger.error(
                    f"Squid reconfiguration failed with exit code {process.returncode}"
                )
                logger.error(f"stdout: {stdout.decode()}")
                logger.error(f"stderr: {stderr.decode()}")
                return False

            logger.info("Squid reconfiguration completed successfully")
            logger.debug(f"Output: {stdout.decode()}")
            return True

        except Exception as e:
            logger.error(f"Failed to reconfigure Squid: {e}")
            return False

    async def is_running(self) -> bool:
        """Check if Squid service is running."""
        try:
            process = await asyncio.create_subprocess_exec(
                "systemctl",
                "is-active",
                "squid",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )

            stdout, _ = await process.communicate()
            return stdout.decode().strip() == "active"

        except Exception as e:
            logger.error(f"Failed to check Squid status: {e}")
            return False

    async def get_status(self) -> dict:
        """
        Get current Squid status including configuration and service state.

        Returns:
            Dictionary with Squid status information.
        """
        status = {
            "running": await self.is_running(),
            "config_exists": self.squid_conf.exists(),
        }

        # Get active outgoing IPs from config if available
        if self.squid_conf.exists():
            try:
                with open(self.squid_conf, "r") as f:
                    content = f.read()
                    # Extract tcp_outgoing_address lines
                    outgoing_ips = []
                    for line in content.split("\n"):
                        if line.strip().startswith("tcp_outgoing_address"):
                            parts = line.split()
                            if len(parts) >= 2:
                                outgoing_ips.append(parts[1])
                    status["outgoing_ips"] = outgoing_ips
            except Exception as e:
                logger.warning(f"Failed to parse Squid config: {e}")
                status["outgoing_ips"] = []
        else:
            status["outgoing_ips"] = []

        return status


# Global instance
squid_manager = SquidManager()
