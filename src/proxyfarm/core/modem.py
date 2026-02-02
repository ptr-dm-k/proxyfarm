"""ModemManager wrapper using mmcli."""

import asyncio
import logging
import re
from typing import Optional

from ..schemas import Bearer, Modem, ModemState

logger = logging.getLogger(__name__)


async def run_command(cmd: list[str], timeout: float = 30.0) -> tuple[str, str, int]:
    """Run a shell command asynchronously."""
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(
            proc.communicate(), timeout=timeout
        )
        return (
            stdout.decode().strip(),
            stderr.decode().strip(),
            proc.returncode or 0,
        )
    except asyncio.TimeoutError:
        logger.error(f"Command timed out: {' '.join(cmd)}")
        raise
    except Exception as e:
        logger.error(f"Command failed: {' '.join(cmd)}, error: {e}")
        raise


def parse_mmcli_output(output: str) -> dict[str, str]:
    """Parse mmcli key-value output into a dictionary."""
    result = {}
    for line in output.split("\n"):
        line = line.strip()
        if "|" in line:
            line = line.split("|", 1)[1].strip()
        if ":" in line:
            key, _, value = line.partition(":")
            result[key.strip()] = value.strip()
    return result


def state_from_string(state_str: str) -> ModemState:
    """Convert state string to ModemState enum."""
    state_map = {
        "failed": ModemState.FAILED,
        "unknown": ModemState.UNKNOWN,
        "disabled": ModemState.DISABLED,
        "disabling": ModemState.DISABLING,
        "enabling": ModemState.ENABLING,
        "enabled": ModemState.ENABLED,
        "searching": ModemState.SEARCHING,
        "registered": ModemState.REGISTERED,
        "disconnecting": ModemState.DISCONNECTING,
        "connecting": ModemState.CONNECTING,
        "connected": ModemState.CONNECTED,
    }
    return state_map.get(state_str.lower(), ModemState.UNKNOWN)


class ModemManager:
    """Wrapper for ModemManager CLI (mmcli)."""

    async def list_modem_ids(self) -> list[int]:
        """Get list of modem IDs."""
        stdout, stderr, rc = await run_command(["mmcli", "-L"])
        if rc != 0:
            logger.error(f"Failed to list modems: {stderr}")
            return []

        # Parse output like: /org/freedesktop/ModemManager1/Modem/0
        modem_ids = []
        for match in re.finditer(r"/Modem/(\d+)", stdout):
            modem_ids.append(int(match.group(1)))
        return modem_ids

    async def get_modem(self, modem_id: int) -> Optional[Modem]:
        """Get detailed information about a modem."""
        stdout, stderr, rc = await run_command(["mmcli", "-m", str(modem_id)])
        if rc != 0:
            logger.error(f"Failed to get modem {modem_id}: {stderr}")
            return None

        data = parse_mmcli_output(stdout)

        # Extract signal quality (e.g., "51% (recent)")
        signal_str = data.get("signal quality", "")
        signal_match = re.search(r"(\d+)%", signal_str)
        signal_quality = int(signal_match.group(1)) if signal_match else None

        # Get bearer info
        bearer = await self.get_bearer(modem_id)

        # Determine interface from bearer or primary port
        interface = None
        if bearer and bearer.interface:
            interface = bearer.interface
        else:
            primary_port = data.get("primary port", "")
            if primary_port.startswith("cdc-wdm"):
                # cdc-wdm0 -> wwan0
                num = re.search(r"\d+$", primary_port)
                if num:
                    interface = f"wwan{num.group()}"

        return Modem(
            id=modem_id,
            manufacturer=data.get("manufacturer"),
            model=data.get("model"),
            device_id=data.get("device-id"),
            primary_port=data.get("primary port"),
            state=state_from_string(data.get("state", "unknown")),
            signal_quality=signal_quality,
            operator_name=data.get("operator name"),
            operator_id=data.get("operator id"),
            bearer=bearer,
            interface=interface,
            ip_address=bearer.ip_address if bearer else None,
        )

    async def get_bearer(self, modem_id: int) -> Optional[Bearer]:
        """Get bearer information for a modem."""
        # First get modem info to find bearer ID
        stdout, stderr, rc = await run_command(["mmcli", "-m", str(modem_id)])
        if rc != 0:
            return None

        bearer_match = re.search(r"Bearer/(\d+)", stdout)
        if not bearer_match:
            return None

        bearer_id = int(bearer_match.group(1))

        # Get bearer details
        stdout, stderr, rc = await run_command(["mmcli", "-b", str(bearer_id)])
        if rc != 0:
            return None

        data = parse_mmcli_output(stdout)

        # Parse DNS servers
        dns_str = data.get("dns", "")
        dns_servers = [d.strip() for d in dns_str.split(",") if d.strip()]

        return Bearer(
            id=bearer_id,
            interface=data.get("interface"),
            ip_address=data.get("address"),
            gateway=data.get("gateway"),
            dns=dns_servers,
        )

    async def list_modems(self) -> list[Modem]:
        """Get list of all modems with details."""
        modem_ids = await self.list_modem_ids()
        modems = []
        for mid in modem_ids:
            modem = await self.get_modem(mid)
            if modem:
                modems.append(modem)
        return modems

    async def enable(self, modem_id: int) -> bool:
        """Enable a modem."""
        stdout, stderr, rc = await run_command(["mmcli", "-m", str(modem_id), "-e"])
        if rc != 0:
            logger.error(f"Failed to enable modem {modem_id}: {stderr}")
            return False
        return True

    async def disable(self, modem_id: int) -> bool:
        """Disable a modem."""
        stdout, stderr, rc = await run_command(["mmcli", "-m", str(modem_id), "-d"])
        if rc != 0:
            logger.error(f"Failed to disable modem {modem_id}: {stderr}")
            return False
        return True

    async def send_ussd(self, modem_id: int, command: str) -> tuple[bool, str]:
        """Send USSD command to a modem."""
        # First initiate USSD session
        stdout, stderr, rc = await run_command(
            ["mmcli", "-m", str(modem_id), "--3gpp-ussd-initiate", command],
            timeout=60.0,
        )

        if rc != 0:
            return False, stderr or "USSD command failed"

        # Parse response
        # Output format: "response: 'Your balance is...'"
        response_match = re.search(r"response:\s*['\"]?(.+?)['\"]?\s*$", stdout, re.DOTALL)
        if response_match:
            return True, response_match.group(1).strip()

        return True, stdout


# Global instance
modem_manager = ModemManager()
