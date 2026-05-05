from pathlib import Path

from fastapi import FastAPI, WebSocket
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy import inspect, text

from app.api.v1 import admin, auth, history, queue
from app.core.config import settings
from app.core.database import Base, engine
from app.core.ws_manager import manager

UPLOADS_DIR = Path(__file__).resolve().parents[1] / "uploads"
UPLOADS_DIR.mkdir(parents=True, exist_ok=True)

app = FastAPI(title=settings.app_name)

# In development allow all origins; in production restrict to ALLOWED_ORIGINS.
_origins: list[str] = (
    ["*"]
    if settings.environment == "development"
    else [o.strip() for o in settings.allowed_origins.split(",") if o.strip()]
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router, prefix="/api/v1")
app.include_router(queue.router, prefix="/api/v1")
app.include_router(history.router, prefix="/api/v1")
app.include_router(admin.router, prefix="/api/v1")
app.mount("/uploads", StaticFiles(directory=str(UPLOADS_DIR)), name="uploads")


@app.on_event("startup")
def on_startup():
    Base.metadata.create_all(bind=engine)
    inspector = inspect(engine)

    doctor_columns = {c["name"] for c in inspector.get_columns("doctors")}
    if "photo_filename" not in doctor_columns:
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE doctors ADD COLUMN photo_filename VARCHAR(255)"))

    queue_columns = {c["name"] for c in inspector.get_columns("queue_tickets")}
    if "registration_channel" not in queue_columns:
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE queue_tickets ADD COLUMN registration_channel VARCHAR(20) DEFAULT 'online'"))
    if "called_at" not in queue_columns:
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE queue_tickets ADD COLUMN called_at DATETIME"))
    if "serving_at" not in queue_columns:
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE queue_tickets ADD COLUMN serving_at DATETIME"))
    if "done_at" not in queue_columns:
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE queue_tickets ADD COLUMN done_at DATETIME"))
    if "actual_serve_minutes" not in queue_columns:
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE queue_tickets ADD COLUMN actual_serve_minutes FLOAT"))

    patient_columns = {c["name"] for c in inspector.get_columns("patients")}
    if "medical_record_no" not in patient_columns:
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE patients ADD COLUMN medical_record_no VARCHAR(40)"))

    with engine.begin() as conn:
        conn.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS uq_queue_schedule_position ON queue_tickets(schedule_id, queue_position)"))


@app.get("/")
def root():
    return {"app": settings.app_name, "status": "ok"}


@app.websocket("/ws/queue")
async def queue_ws(websocket: WebSocket):
    """Real-time queue updates for mobile and display clients."""
    await manager.connect(websocket)
    try:
        while True:
            await websocket.receive_text()  # keep-alive ping from client
    except Exception:
        manager.disconnect(websocket)
