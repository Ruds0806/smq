from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.deps import get_current_patient
from app.core.database import get_db
from app.models.entities import Doctor, Patient, Poli, QueueTicket, VisitHistory

router = APIRouter(prefix="/history", tags=["history"])


@router.get("/queues")
def queue_history(patient: Patient = Depends(get_current_patient), db: Session = Depends(get_db)):
    rows = (
        db.query(QueueTicket, Poli.name.label("poli_name"), Doctor.full_name.label("doctor_name"))
        .join(Poli, Poli.id == QueueTicket.poli_id)
        .join(Doctor, Doctor.id == QueueTicket.doctor_id)
        .filter(QueueTicket.patient_id == patient.id)
        .order_by(QueueTicket.id.desc())
        .all()
    )
    return [
        {
            "id": t.id,
            "ticket_no": t.ticket_no,
            "status": t.status,
            "poli_name": poli_name,
            "doctor_name": doctor_name,
            "queue_position": t.queue_position,
            "registration_channel": t.registration_channel,
            "created_at": t.created_at.isoformat(),
            "called_at": t.called_at.isoformat() if t.called_at else None,
            "done_at": t.done_at.isoformat() if t.done_at else None,
            "actual_serve_minutes": t.actual_serve_minutes,
        }
        for t, poli_name, doctor_name in rows
    ]


@router.get("/visits")
def visit_history(patient: Patient = Depends(get_current_patient), db: Session = Depends(get_db)):
    rows = db.query(VisitHistory).filter(VisitHistory.patient_id == patient.id).order_by(VisitHistory.id.desc()).all()
    return [
        {
            "id": x.id,
            "doctor_name": x.doctor_name,
            "poli_name": x.poli_name,
            "diagnosis_summary": x.diagnosis_summary,
            "visit_date": x.visit_date,
        }
        for x in rows
    ]
