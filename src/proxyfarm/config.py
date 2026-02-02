"""Configuration management."""

from pathlib import Path
from typing import Optional

import yaml
from pydantic import BaseModel, Field


class APIConfig(BaseModel):
    host: str = "0.0.0.0"
    port: int = 8080
    api_key: str = "change-me"


class ModemsConfig(BaseModel):
    apn: str = "internet"
    expected_count: int = 2
    connection_prefix: str = "lte-modem"


class MonitorConfig(BaseModel):
    enabled: bool = True
    interval: int = 30
    auto_reconnect: bool = True
    health_check_url: str = "http://ifconfig.me"


class ScriptsConfig(BaseModel):
    setup_modems: str = "/opt/proxyfarm/scripts/setup_modems.sh"


class Config(BaseModel):
    api: APIConfig = Field(default_factory=APIConfig)
    modems: ModemsConfig = Field(default_factory=ModemsConfig)
    monitor: MonitorConfig = Field(default_factory=MonitorConfig)
    scripts: ScriptsConfig = Field(default_factory=ScriptsConfig)


_config: Optional[Config] = None


def load_config(path: Optional[Path] = None) -> Config:
    """Load configuration from YAML file."""
    global _config

    if path is None:
        # Try default locations
        candidates = [
            Path("/etc/proxyfarm/config.yaml"),
            Path.home() / ".config" / "proxyfarm" / "config.yaml",
            Path("config.yaml"),
        ]
        for candidate in candidates:
            if candidate.exists():
                path = candidate
                break

    if path and path.exists():
        with open(path) as f:
            data = yaml.safe_load(f) or {}
        _config = Config(**data)
    else:
        _config = Config()

    return _config


def get_config() -> Config:
    """Get current configuration."""
    global _config
    if _config is None:
        _config = load_config()
    return _config
