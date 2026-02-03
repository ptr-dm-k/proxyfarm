"""Proxy (Squid) management endpoints."""

import logging
from typing import Dict

from fastapi import APIRouter, Depends

from ..auth import verify_api_key
from ..core.squid import squid_manager

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/proxy", tags=["proxy"])


@router.get("/status", response_model=Dict)
async def get_proxy_status(_: str = Depends(verify_api_key)):
    """
    Get Squid proxy status including service state and configured outgoing IPs.
    """
    status = await squid_manager.get_status()
    return status


@router.post("/reconfigure", response_model=Dict)
async def reconfigure_proxy(_: str = Depends(verify_api_key)):
    """
    Manually trigger Squid reconfiguration based on current modem IPs.
    This is called automatically after IP rotation, but can be triggered manually.
    """
    logger.info("Manual Squid reconfiguration requested")
    success = await squid_manager.reconfigure()

    if success:
        status = await squid_manager.get_status()
        return {
            "success": True,
            "message": "Squid reconfigured successfully",
            "status": status,
        }
    else:
        return {
            "success": False,
            "message": "Squid reconfiguration failed",
            "error": "Check logs for details",
        }
