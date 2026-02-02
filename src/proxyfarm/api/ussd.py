"""USSD API endpoints."""

from fastapi import APIRouter, Depends, HTTPException, status

from ..auth import verify_api_key
from ..core.modem import modem_manager
from ..core.ussd import ussd_handler
from ..schemas import ErrorResponse, USSDRequest, USSDResponse

router = APIRouter(tags=["ussd"])


@router.post(
    "/modems/{modem_id}/ussd",
    response_model=USSDResponse,
    responses={404: {"model": ErrorResponse}},
)
async def send_ussd(
    modem_id: int,
    request: USSDRequest,
    _: str = Depends(verify_api_key),
) -> USSDResponse:
    """Send USSD command to a modem."""
    # Verify modem exists
    modem = await modem_manager.get_modem(modem_id)
    if not modem:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Modem {modem_id} not found",
        )

    return await ussd_handler.send(modem_id, request.command)
