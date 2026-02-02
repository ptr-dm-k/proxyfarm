"""Network management using nmcli and ip commands."""

import asyncio
import logging
import re
from typing import Optional

from .modem import run_command

logger = logging.getLogger(__name__)


class NetworkManager:
    """Wrapper for NetworkManager CLI (nmcli) and ip commands."""

    async def get_connection_state(self, connection_name: str) -> Optional[str]:
        """Get state of a NetworkManager connection."""
        stdout, stderr, rc = await run_command([
            "nmcli", "-g", "GENERAL.STATE", "connection", "show", connection_name
        ])
        if rc != 0:
            return None
        return stdout.strip() if stdout else None

    async def get_connection_device(self, connection_name: str) -> Optional[str]:
        """Get device associated with a connection."""
        stdout, stderr, rc = await run_command([
            "nmcli", "-g", "GENERAL.DEVICES", "connection", "show", connection_name
        ])
        if rc != 0:
            return None
        return stdout.strip() if stdout else None

    async def connection_up(self, connection_name: str) -> bool:
        """Activate a NetworkManager connection."""
        stdout, stderr, rc = await run_command([
            "nmcli", "connection", "up", connection_name
        ], timeout=60.0)
        if rc != 0:
            logger.error(f"Failed to activate connection {connection_name}: {stderr}")
            return False
        return True

    async def connection_down(self, connection_name: str) -> bool:
        """Deactivate a NetworkManager connection."""
        stdout, stderr, rc = await run_command([
            "nmcli", "connection", "down", connection_name
        ], timeout=30.0)
        if rc != 0:
            logger.error(f"Failed to deactivate connection {connection_name}: {stderr}")
            return False
        return True

    async def get_interface_ip(self, interface: str) -> Optional[str]:
        """Get IPv4 address of a network interface."""
        stdout, stderr, rc = await run_command([
            "ip", "-4", "addr", "show", interface
        ])
        if rc != 0:
            return None

        # Parse: inet 10.0.0.1/24 ...
        match = re.search(r"inet\s+([\d.]+)", stdout)
        return match.group(1) if match else None

    async def get_interface_gateway(self, interface: str) -> Optional[str]:
        """Get default gateway for an interface."""
        stdout, stderr, rc = await run_command([
            "ip", "route", "show", "dev", interface
        ])
        if rc != 0:
            return None

        # Parse: default via 10.0.0.1 ...
        match = re.search(r"default\s+via\s+([\d.]+)", stdout)
        return match.group(1) if match else None

    async def list_wwan_interfaces(self) -> list[str]:
        """Get list of wwan interfaces."""
        stdout, stderr, rc = await run_command(["ip", "link", "show"])
        if rc != 0:
            return []

        interfaces = re.findall(r"(wwan\d+)", stdout)
        return list(set(interfaces))

    async def check_internet_connectivity(
        self, interface: str, url: str = "http://ifconfig.me"
    ) -> tuple[bool, Optional[str]]:
        """Check internet connectivity through an interface."""
        try:
            stdout, stderr, rc = await run_command([
                "curl", "--interface", interface, "-s", "-m", "10", url
            ], timeout=15.0)
            if rc == 0 and stdout:
                # Should return external IP
                ip_match = re.match(r"^[\d.]+$", stdout.strip())
                if ip_match:
                    return True, stdout.strip()
            return False, None
        except Exception as e:
            logger.error(f"Connectivity check failed for {interface}: {e}")
            return False, None

    async def flush_routes(self) -> bool:
        """Flush route cache."""
        stdout, stderr, rc = await run_command(["ip", "route", "flush", "cache"])
        return rc == 0


# Global instance
network_manager = NetworkManager()
