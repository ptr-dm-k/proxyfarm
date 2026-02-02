"""Modem API endpoints."""

from fastapi import APIRouter, Depends, HTTPException, status

from ..auth import verify_api_key
from ..core.modem import modem_manager
from ..core.rotation import ip_rotator
from ..schemas import ErrorResponse, Modem, ModemListResponse, RotationResult

router = APIRouter(prefix="/modems", tags=["modems"])


@router.get(
    "",
    response_model=ModemListResponse,
    responses={500: {"model": ErrorResponse}},
)
async def list_modems(_: str = Depends(verify_api_key)) -> ModemListResponse:
    """Get list of all modems."""
    modems = await modem_manager.list_modems()
    return ModemListResponse(modems=modems, count=len(modems))


@router.get(
    "/{modem_id}",
    response_model=Modem,
    responses={404: {"model": ErrorResponse}},
)
async def get_modem(
    modem_id: int, _: str = Depends(verify_api_key)
) -> Modem:
    """Get detailed information about a specific modem."""
    modem = await modem_manager.get_modem(modem_id)
    if not modem:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Modem {modem_id} not found",
        )
    return modem


@router.post(
    "/{modem_id}/rotate",
    response_model=RotationResult,
    responses={404: {"model": ErrorResponse}},
)
async def rotate_ip(
    modem_id: int, _: str = Depends(verify_api_key)
) -> RotationResult:
    """Rotate IP address for a modem by reconnecting."""
    # Verify modem exists
    modem = await modem_manager.get_modem(modem_id)
    if not modem:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Modem {modem_id} not found",
        )

    return await ip_rotator.rotate(modem_id)


@router.post(
    "/{modem_id}/enable",
    response_model=dict,
    responses={404: {"model": ErrorResponse}},
)
async def enable_modem(
    modem_id: int, _: str = Depends(verify_api_key)
) -> dict:
    """Enable a modem."""
    success = await modem_manager.enable(modem_id)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to enable modem {modem_id}",
        )
    return {"success": True, "modem_id": modem_id}


@router.post(
    "/{modem_id}/disable",
    response_model=dict,
    responses={404: {"model": ErrorResponse}},
)
async def disable_modem(
    modem_id: int, _: str = Depends(verify_api_key)
) -> dict:
    """Disable a modem."""
    success = await modem_manager.disable(modem_id)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to disable modem {modem_id}",
        )
    return {"success": True, "modem_id": modem_id}
