"""System API endpoints."""

import asyncio
import time
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status

from .. import __version__
from ..auth import verify_api_key
from ..config import get_config
from ..core.modem import modem_manager, run_command
from ..schemas import (
    ErrorResponse,
    HealthResponse,
    ModemState,
    ReinitializeResponse,
    SystemStatus,
)

router = APIRouter(prefix="/system", tags=["system"])

# Track service start time
_start_time = time.time()


@router.get("/status", response_model=SystemStatus)
async def get_system_status(_: str = Depends(verify_api_key)) -> SystemStatus:
    """Get overall system status."""
    modems = await modem_manager.list_modems()
    connected = sum(1 for m in modems if m.state == ModemState.CONNECTED)

    return SystemStatus(
        status="ok" if connected > 0 else "degraded",
        modems_connected=connected,
        modems_total=len(modems),
        uptime_seconds=time.time() - _start_time,
        version=__version__,
        timestamp=datetime.utcnow(),
    )


@router.post(
    "/reinitialize",
    response_model=ReinitializeResponse,
    responses={500: {"model": ErrorResponse}},
)
async def reinitialize_modems(_: str = Depends(verify_api_key)) -> ReinitializeResponse:
    """Reinitialize all modems by running setup script."""
    config = get_config()
    script_path = config.scripts.setup_modems

    try:
        stdout, stderr, rc = await run_command(
            ["bash", script_path],
            timeout=300.0,  # 5 minutes
        )

        if rc != 0:
            return ReinitializeResponse(
                success=False,
                message="Setup script failed",
                error=stderr or stdout,
            )

        return ReinitializeResponse(
            success=True,
            message="Modems reinitialized successfully",
        )

    except asyncio.TimeoutError:
        return ReinitializeResponse(
            success=False,
            message="Setup script timed out",
            error="Script execution exceeded 5 minutes",
        )
    except Exception as e:
        return ReinitializeResponse(
            success=False,
            message="Failed to run setup script",
            error=str(e),
        )


# Health check endpoint (no auth required)
health_router = APIRouter(tags=["health"])


@health_router.get("/health", response_model=HealthResponse)
async def health_check() -> HealthResponse:
    """Health check endpoint for monitoring."""
    return HealthResponse(status="healthy", timestamp=datetime.utcnow())
