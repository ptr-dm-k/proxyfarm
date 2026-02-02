"""Main FastAPI application."""

import logging
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Optional

import uvicorn
from fastapi import FastAPI

from . import __version__
from .api.router import api_router, root_router
from .config import get_config, load_config
from .services.monitor import monitor_service

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan handler."""
    # Startup
    logger.info(f"Starting ProxyFarm v{__version__}")
    await monitor_service.start()

    yield

    # Shutdown
    logger.info("Shutting down ProxyFarm")
    await monitor_service.stop()


def create_app(config_path: Optional[Path] = None) -> FastAPI:
    """Create and configure the FastAPI application."""
    # Load configuration
    load_config(config_path)
    config = get_config()

    app = FastAPI(
        title="ProxyFarm",
        description="LTE modem management service",
        version=__version__,
        lifespan=lifespan,
        docs_url="/docs",
        redoc_url="/redoc",
    )

    # Include routers
    app.include_router(root_router)
    app.include_router(api_router)

    return app


# Default app instance
app = create_app()


def main():
    """Entry point for running the server."""
    config = get_config()
    uvicorn.run(
        "proxyfarm.main:app",
        host=config.api.host,
        port=config.api.port,
        reload=False,
    )


if __name__ == "__main__":
    main()
