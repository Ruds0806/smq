from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.api.deps import get_current_patient
from app.core.database import get_db
from app.core.ws_manager import manager
from app.models.entities import Doctor, Patient, Poli, QueueTicket, Schedule
from app.schemas.queue import QueueCreateRequest, QueueTicketResponse
from app.services.queue_service import (
    apply_status_transition,
    build_ticket_no,
    can_transition,
    compute_rolling_avg_serve_minutes,
    get_next_queue_position,
)
from app.services.notification_service import send_push_notification

router = APIRouter(prefix="/queue", tags=["queue"])


@router.get("/polis")
def list_polis(db: Session = Depends(get_db)):
    rows = db.query(Poli).all()
    return [{"id": x.id, "name": x.name} for x in rows]


@router.get("/doctors")
def list_doctors(poli_id: int, db: Session = Depends(get_db)):
    rows = (
        db.query(Doctor, Poli.name.label("poli_name"))
        .join(Poli, Poli.id == Doctor.poli_id)
        .filter(Doctor.poli_id == poli_id)
        .all()
    )
    return [
        {
            "id": d.id,
            "full_name": d.full_name,
            "specialization": d.specialization,
            "photo_url": f"/uploads/doctors/{d.photo_filename}" if d.photo_filename else None,
            "avg_serve_minutes": compute_rolling_avg_serve_minutes(db, d.id),
        }
        for d, _ in rows
    ]


@router.get("/schedules")
def list_schedules(doctor_id: int, db: Session = Depends(get_db)):
    rows = db.query(Schedule).filter(Schedule.doctor_id == doctor_id).all()
    return [
        {
            "id": x.id,
            "date": x.date,
            "start_time": x.start_time,
            "end_time": x.end_time,
            "quota": x.quota,
            "booked": db.query(QueueTicket)
            .filter(
                QueueTicket.schedule_id == x.id,
                QueueTicket.status.notin_(["cancelled", "no_show"]),
            )
            .count(),
        }
        for x in rows
    ]


@router.get("/check-conflict")
def check_schedule_conflict(
    schedule_id: int,
    patient: Patient = Depends(get_current_patient),
    db: Session = Depends(get_db),
):
    """
    Returns any active tickets whose schedule overlaps with the requested schedule.
    Frontend uses this to show a confirmation dialog before proceeding.
    """
    new_schedule = db.query(Schedule).filter(Schedule.id == schedule_id).first()
    if not new_schedule:
        raise HTTPException(status_code=404, detail="Schedule not found")

    # Get all active tickets for this patient
    active_tickets = (
        db.query(QueueTicket, Schedule, Poli, Doctor)
        .join(Schedule, Schedule.id == QueueTicket.schedule_id)
        .join(Poli, Poli.id == QueueTicket.poli_id)
        .join(Doctor, Doctor.id == QueueTicket.doctor_id)
        .filter(
            QueueTicket.patient_id == patient.id,
            QueueTicket.status.in_(["waiting", "called", "serving"]),
        )
        .all()
    )

    conflicts = []
    for ticket, sched, poli, doctor in active_tickets:
        # Same date check
        if sched.date != new_schedule.date:
            continue
        # Time overlap check: (start1 < end2) AND (end1 > start2)
        if sched.start_time < new_schedule.end_time and sched.end_time > new_schedule.start_time:
            conflicts.append({
                "ticket_no": ticket.ticket_no,
                "poli_name": poli.name,
                "doctor_name": doctor.full_name,
                "date": sched.date,
                "start_time": sched.start_time,
                "end_time": sched.end_time,
            })

    return {"has_conflict": len(conflicts) > 0, "conflicts": conflicts}


@router.post("/take", response_model=QueueTicketResponse)
def take_queue(
    payload: QueueCreateRequest,
    patient: Patient = Depends(get_current_patient),
    db: Session = Depends(get_db),
):
    schedule = db.query(Schedule).filter(Schedule.id == payload.schedule_id).first()
    if not schedule:
        raise HTTPException(status_code=404, detail="Schedule not found")

    # Prevent duplicate active ticket for same doctor
    existing = (
        db.query(QueueTicket)
        .filter(
            QueueTicket.patient_id == patient.id,
            QueueTicket.doctor_id == payload.doctor_id,
            QueueTicket.status.in_(["waiting", "called", "serving"]),
        )
        .first()
    )
    if existing:
        raise HTTPException(status_code=409, detail="Anda sudah memiliki antrian aktif untuk dokter ini.")

    avg_serve = compute_rolling_avg_serve_minutes(db, payload.doctor_id)

    ticket = None
    for _ in range(4):
        queue_position = get_next_queue_position(db, payload.schedule_id)
        ticket_no = build_ticket_no(queue_position)
        ticket = QueueTicket(
            ticket_no=ticket_no,
            patient_id=patient.id,
            family_member_id=payload.family_member_id,
            poli_id=payload.poli_id,
            doctor_id=payload.doctor_id,
            schedule_id=payload.schedule_id,
            status="waiting",
            estimated_minutes=max(5, round(queue_position * avg_serve)),
            queue_position=queue_position,
            checkin_qr=f"SQRS-{patient.id}-{datetime.utcnow().timestamp()}",
            registration_channel="online",
        )
        db.add(ticket)
        try:
            db.commit()
            db.refresh(ticket)
            break
        except IntegrityError:
            db.rollback()
            ticket = None

    if ticket is None:
        raise HTTPException(status_code=409, detail="Gagal membuat nomor antrian. Silakan coba lagi.")

    send_push_notification(patient.phone, "Antrian berhasil", f"Nomor antrian Anda {ticket.ticket_no}")

    import asyncio
    asyncio.create_task(
        manager.broadcast({"event": "ticket_created", "ticket_no": ticket.ticket_no, "schedule_id": payload.schedule_id})
    )

    return QueueTicketResponse(
        id=ticket.id,
        ticket_no=ticket.ticket_no,
        status=ticket.status,
        queue_position=ticket.queue_position,
        estimated_minutes=ticket.estimated_minutes,
        checkin_qr=ticket.checkin_qr,
    )


@router.post("/cancel/{ticket_id}")
def cancel_ticket(
    ticket_id: int,
    patient: Patient = Depends(get_current_patient),
    db: Session = Depends(get_db),
):
    ticket = (
        db.query(QueueTicket)
        .filter(QueueTicket.id == ticket_id, QueueTicket.patient_id == patient.id)
        .first()
    )
    if not ticket:
        raise HTTPException(status_code=404, detail="Tiket tidak ditemukan")
    if not can_transition(ticket.status, "cancelled"):
        raise HTTPException(status_code=400, detail=f"Tiket dengan status '{ticket.status}' tidak bisa dibatalkan")

    apply_status_transition(ticket, "cancelled")
    db.commit()

    import asyncio
    asyncio.create_task(
        manager.broadcast({"event": "ticket_cancelled", "ticket_no": ticket.ticket_no})
    )

    return {"message": "Antrian berhasil dibatalkan", "ticket_no": ticket.ticket_no}


@router.get("/dashboard")
def queue_dashboard(patient: Patient = Depends(get_current_patient), db: Session = Depends(get_db)):
    ticket = (
        db.query(QueueTicket)
        .filter(
            QueueTicket.patient_id == patient.id,
            QueueTicket.status.in_(["waiting", "called", "serving"]),
        )
        .order_by(QueueTicket.id.desc())
        .first()
    )
    if not ticket:
        return {"has_ticket": False}

    # Count how many tickets ahead are still waiting/called
    ahead = (
        db.query(QueueTicket)
        .filter(
            QueueTicket.schedule_id == ticket.schedule_id,
            QueueTicket.queue_position < ticket.queue_position,
            QueueTicket.status.in_(["waiting", "called"]),
        )
        .count()
    )

    avg_serve = compute_rolling_avg_serve_minutes(db, ticket.doctor_id)
    estimated = max(0, round(ahead * avg_serve))
    total_in_schedule = (
        db.query(QueueTicket)
        .filter(
            QueueTicket.schedule_id == ticket.schedule_id,
            QueueTicket.status.notin_(["cancelled", "no_show"]),
        )
        .count()
    )
    progress_percent = min(100, int(((ticket.queue_position - ahead) / max(ticket.queue_position, 1)) * 100))

    notification = "Anda sedang dilayani!" if ticket.status == "serving" else (
        "Segera menuju loket!" if ticket.status == "called" else (
            "Antrian hampir dipanggil" if ahead <= 2 else "Menunggu giliran"
        )
    )

    return {
        "has_ticket": True,
        "ticket_id": ticket.id,
        "ticket_no": ticket.ticket_no,
        "status": ticket.status,
        "queue_position": ticket.queue_position,
        "ahead": ahead,
        "estimated_minutes": estimated,
        "avg_serve_minutes": avg_serve,
        "progress_percent": progress_percent,
        "notification": notification,
        "checkin_qr": ticket.checkin_qr,
    }
