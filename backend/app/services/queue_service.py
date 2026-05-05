from datetime import datetime, timezone

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.entities import QueueTicket

VALID_TRANSITIONS = {
    "waiting": {"called", "cancelled"},
    "called": {"serving", "no_show", "waiting"},
    "serving": {"done"},
    "done": set(),
    "cancelled": set(),
    "no_show": set(),
}


def get_next_queue_position(db: Session, schedule_id: int) -> int:
    current_max = (
        db.query(func.max(QueueTicket.queue_position))
        .filter(QueueTicket.schedule_id == schedule_id)
        .scalar()
    )
    return (current_max or 0) + 1


def build_ticket_no(position: int) -> str:
    return f"A-{position:03d}"


def can_transition(current: str, target: str) -> bool:
    return target in VALID_TRANSITIONS.get(current, set())


def apply_status_transition(ticket: QueueTicket, new_status: str) -> None:
    """Apply status change and record timestamps."""
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    ticket.status = new_status

    if new_status == "called":
        ticket.called_at = now
    elif new_status == "serving":
        ticket.serving_at = now
    elif new_status == "done":
        ticket.done_at = now
        if ticket.serving_at:
            delta = (now - ticket.serving_at).total_seconds() / 60
            ticket.actual_serve_minutes = round(delta, 2)


def compute_rolling_avg_serve_minutes(db: Session, doctor_id: int) -> float:
    """Rolling average of actual serve time for a doctor (last 20 done tickets)."""
    rows = (
        db.query(QueueTicket.actual_serve_minutes)
        .filter(
            QueueTicket.doctor_id == doctor_id,
            QueueTicket.actual_serve_minutes.isnot(None),
        )
        .order_by(QueueTicket.id.desc())
        .limit(20)
        .all()
    )
    values = [r[0] for r in rows if r[0] is not None]
    if not values:
        return 8.0  # default fallback
    return round(sum(values) / len(values), 1)
