"""Main API router combining all endpoints."""

from fastapi import APIRouter

from .modems import router as modems_router
from .proxy import router as proxy_router
from .system import health_router, router as system_router
from .ussd import router as ussd_router

# Main API router with version prefix
api_router = APIRouter(prefix="/api/v1")
api_router.include_router(modems_router)
api_router.include_router(ussd_router)
api_router.include_router(system_router)
api_router.include_router(proxy_router)

# Health check at root level (no version prefix, no auth)
root_router = APIRouter()
root_router.include_router(health_router)
