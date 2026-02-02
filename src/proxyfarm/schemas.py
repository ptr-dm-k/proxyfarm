"""Pydantic schemas for API requests and responses."""

from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field


class ModemState(str, Enum):
    UNKNOWN = "unknown"
    FAILED = "failed"
    DISABLED = "disabled"
    DISABLING = "disabling"
    ENABLING = "enabling"
    ENABLED = "enabled"
    SEARCHING = "searching"
    REGISTERED = "registered"
    DISCONNECTING = "disconnecting"
    CONNECTING = "connecting"
    CONNECTED = "connected"


class Bearer(BaseModel):
    id: int
    interface: Optional[str] = None
    ip_address: Optional[str] = None
    gateway: Optional[str] = None
    dns: list[str] = Field(default_factory=list)


class Modem(BaseModel):
    id: int
    manufacturer: Optional[str] = None
    model: Optional[str] = None
    device_id: Optional[str] = None
    primary_port: Optional[str] = None
    state: ModemState = ModemState.UNKNOWN
    signal_quality: Optional[int] = None
    operator_name: Optional[str] = None
    operator_id: Optional[str] = None
    bearer: Optional[Bearer] = None
    interface: Optional[str] = None
    ip_address: Optional[str] = None


class ModemListResponse(BaseModel):
    modems: list[Modem]
    count: int


class USSDRequest(BaseModel):
    command: str = Field(..., example="*100#")


class USSDResponse(BaseModel):
    modem_id: int
    command: str
    response: str
    success: bool
    error: Optional[str] = None


class RotationResult(BaseModel):
    modem_id: int
    success: bool
    old_ip: Optional[str] = None
    new_ip: Optional[str] = None
    error: Optional[str] = None
    duration_seconds: float


class SystemStatus(BaseModel):
    status: str = "ok"
    modems_connected: int
    modems_total: int
    uptime_seconds: float
    version: str
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class HealthResponse(BaseModel):
    status: str = "healthy"
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class ErrorResponse(BaseModel):
    error: str
    detail: Optional[str] = None


class ReinitializeResponse(BaseModel):
    success: bool
    message: str
    error: Optional[str] = None
