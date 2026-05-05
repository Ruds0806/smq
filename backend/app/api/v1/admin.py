from datetime import datetime
from io import BytesIO
from pathlib import Path
from uuid import uuid4
from zipfile import ZIP_DEFLATED, ZipFile
from xml.sax.saxutils import escape

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from fastapi.responses import StreamingResponse
from sqlalchemy.exc import IntegrityError
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import hash_password
from app.core.ws_manager import manager
from app.models.entities import AdminUser, AuditLog, Doctor, Patient, Poli, QueueTicket, Schedule, VisitHistory
from app.services.queue_service import apply_status_transition, build_ticket_no, can_transition, get_next_queue_position

router = APIRouter(prefix="/admin", tags=["admin"])
UPLOAD_DIR = Path(__file__).resolve().parents[3] / "uploads" / "doctors"
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)


def _write_audit(db: Session, actor: str, action: str, detail: str = "") -> None:
    db.add(AuditLog(actor=actor, action=action, detail=detail))
    db.commit()


def _photo_url(filename: str | None) -> str | None:
    if not filename:
        return None
    return f"/uploads/doctors/{filename}"


def _safe_suffix(filename: str) -> str:
    suffix = Path(filename).suffix.lower()
    if suffix in {".jpg", ".jpeg", ".png", ".webp"}:
        return suffix
    return ".jpg"


def _store_photo(photo: UploadFile | None) -> str | None:
    if not photo or not photo.filename:
        return None
    suffix = _safe_suffix(photo.filename)
    photo_filename = f"doctor-{uuid4().hex}{suffix}"
    photo_path = UPLOAD_DIR / photo_filename
    photo_path.write_bytes(photo.file.read())
    return photo_filename


def _service_from_poli_name(poli_name: str | None) -> str:
    text = (poli_name or "").lower()
    if "farmasi" in text:
        return "farmasi"
    if "admin" in text:
        return "admin"
    return "poli"


def _service_matches(service: str, poli_name: str | None) -> bool:
    return _service_from_poli_name(poli_name) == service


def _build_xlsx(rows: list[list[str | int | float | None]], sheet_name: str = "Laporan") -> bytes:
    def cell_xml(value: str | int | float | None) -> str:
        if value is None:
            value = ""
        text = escape(str(value))
        return f'<c t="inlineStr"><is><t>{text}</t></is></c>'

    def row_xml(values: list[str | int | float | None]) -> str:
        cells = ''.join(cell_xml(value) for value in values)
        return f'<row>{cells}</row>'

    sheet_rows = ''.join(row_xml(row) for row in rows)
    sheet_xml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        f'<sheetData>{sheet_rows}</sheetData>'
        '</worksheet>'
    )
    workbook_xml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        f'<sheets><sheet name="{escape(sheet_name)}" sheetId="1" r:id="rId1"/></sheets>'
        '</workbook>'
    )
    rels_xml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '</Relationships>'
    )
    root_rels = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
        '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
        '</Relationships>'
    )
    content_types = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
        '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
        '</Types>'
    )
    core_xml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:dcterms="http://purl.org/dc/terms/" '
        'xmlns:dcmitype="http://purl.org/dc/dcmitype/" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        '<dc:title>SmartQueue RS Report</dc:title>'
        '<dc:creator>SmartQueue RS</dc:creator>'
        '<cp:lastModifiedBy>SmartQueue RS</cp:lastModifiedBy>'
        '</cp:coreProperties>'
    )
    app_xml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" '
        'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">'
        '<Application>SmartQueue RS</Application>'
        '</Properties>'
    )

    buffer = BytesIO()
    with ZipFile(buffer, 'w', ZIP_DEFLATED) as archive:
        archive.writestr('[Content_Types].xml', content_types)
        archive.writestr('_rels/.rels', root_rels)
        archive.writestr('docProps/core.xml', core_xml)
        archive.writestr('docProps/app.xml', app_xml)
        archive.writestr('xl/workbook.xml', workbook_xml)
        archive.writestr('xl/_rels/workbook.xml.rels', rels_xml)
        archive.writestr('xl/worksheets/sheet1.xml', sheet_xml)
    buffer.seek(0)
    return buffer.getvalue()


@router.get("/queue-monitor")
def queue_monitor(db: Session = Depends(get_db)):
    rows = (
        db.query(QueueTicket, Patient.full_name.label("patient_name"), Poli.name.label("poli_name"), Doctor.full_name.label("doctor_name"))
        .join(Patient, Patient.id == QueueTicket.patient_id)
        .join(Poli, Poli.id == QueueTicket.poli_id)
        .join(Doctor, Doctor.id == QueueTicket.doctor_id)
        .order_by(QueueTicket.id.desc())
        .limit(100)
        .all()
    )
    return [
        {
            "ticket_no": ticket.ticket_no,
            "patient_name": patient_name,
            "poli_name": poli_name,
            "doctor_name": doctor_name,
            "status": ticket.status,
            "registration_channel": ticket.registration_channel,
            "queue_position": ticket.queue_position,
            "estimated_minutes": ticket.estimated_minutes,
            "created_at": ticket.created_at.isoformat(),
        }
        for ticket, patient_name, poli_name, doctor_name in rows
    ]


@router.get("/reports/visits")
def visit_report(db: Session = Depends(get_db)):
    rows = (
        db.query(QueueTicket, Patient.full_name.label("patient_name"), Poli.name.label("poli_name"), Doctor.full_name.label("doctor_name"))
        .join(Patient, Patient.id == QueueTicket.patient_id)
        .join(Poli, Poli.id == QueueTicket.poli_id)
        .join(Doctor, Doctor.id == QueueTicket.doctor_id)
        .order_by(QueueTicket.created_at.desc())
        .all()
    )
    return [
        {
            "ticket_no": ticket.ticket_no,
            "patient_name": patient_name,
            "poli_name": poli_name,
            "doctor_name": doctor_name,
            "status": ticket.status,
            "registration_channel": ticket.registration_channel,
            "queue_position": ticket.queue_position,
            "estimated_minutes": ticket.estimated_minutes,
            "created_at": ticket.created_at.isoformat(),
        }
        for ticket, patient_name, poli_name, doctor_name in rows
    ]


@router.get("/reports/visits.xlsx")
def visit_report_xlsx(db: Session = Depends(get_db)):
    rows = visit_report(db)
    workbook_rows: list[list[str | int | float | None]] = [
        ["SmartQueue RS", "Laporan Kunjungan"],
        ["Dicetak", datetime.utcnow().isoformat()],
        [],
        ["No Tiket", "Nama Pasien", "Poli", "Dokter", "Channel", "Status", "Posisi", "Estimasi Menit", "Waktu"],
    ]
    for row in rows:
        workbook_rows.append([
            row["ticket_no"],
            row["patient_name"],
            row["poli_name"],
            row["doctor_name"],
            row["registration_channel"],
            row["status"],
            row["queue_position"],
            row["estimated_minutes"],
            row["created_at"],
        ])

    payload = _build_xlsx(workbook_rows, "Laporan Kunjungan")
    filename = f"smartqueue-rs-laporan-kunjungan-{datetime.utcnow().strftime('%Y%m%d-%H%M%S')}.xlsx"
    headers = {"Content-Disposition": f'attachment; filename="{filename}"'}
    return StreamingResponse(
        BytesIO(payload),
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers=headers,
    )


@router.get("/queue-options")
def queue_options(db: Session = Depends(get_db)):
    polis = db.query(Poli).order_by(Poli.name.asc()).all()
    doctors = db.query(Doctor).order_by(Doctor.full_name.asc()).all()
    schedules = db.query(Schedule).order_by(Schedule.date.asc(), Schedule.start_time.asc()).all()

    # Count active bookings per schedule
    booked_map: dict[int, int] = {}
    for s in schedules:
        booked_map[s.id] = (
            db.query(func.count(QueueTicket.id))
            .filter(
                QueueTicket.schedule_id == s.id,
                QueueTicket.status.notin_(["cancelled", "no_show"]),
            )
            .scalar() or 0
        )

    return {
        "polis": [{"id": x.id, "name": x.name} for x in polis],
        "doctors": [
            {
                "id": x.id,
                "full_name": x.full_name,
                "specialization": x.specialization,
                "poli_id": x.poli_id,
            }
            for x in doctors
        ],
        "schedules": [
            {
                "id": x.id,
                "doctor_id": x.doctor_id,
                "poli_id": x.poli_id,
                "date": x.date,
                "start_time": x.start_time,
                "end_time": x.end_time,
                "quota": x.quota,
                "booked": booked_map.get(x.id, 0),
            }
            for x in schedules
        ],
    }


@router.post("/queue-call-next")
def queue_call_next(payload: dict, db: Session = Depends(get_db)):
    service = (payload.get("service") or "").strip().lower()
    if service not in {"admin", "poli", "farmasi"}:
        raise HTTPException(status_code=400, detail="service harus admin, poli, atau farmasi")

    rows = (
        db.query(QueueTicket, Patient.full_name.label("patient_name"), Poli.name.label("poli_name"), Doctor.full_name.label("doctor_name"))
        .join(Patient, Patient.id == QueueTicket.patient_id)
        .join(Poli, Poli.id == QueueTicket.poli_id)
        .join(Doctor, Doctor.id == QueueTicket.doctor_id)
        .filter(QueueTicket.status == "waiting")
        .order_by(QueueTicket.queue_position.asc(), QueueTicket.id.asc())
        .all()
    )

    selected = None
    for row in rows:
        ticket, patient_name, poli_name, doctor_name = row
        if _service_matches(service, poli_name):
            selected = (ticket, patient_name, poli_name, doctor_name)
            break

    if selected is None:
        raise HTTPException(status_code=404, detail=f"Belum ada antrian waiting untuk {service}")

    ticket, patient_name, poli_name, doctor_name = selected
    apply_status_transition(ticket, "called")
    db.commit()
    db.refresh(ticket)

    _write_audit(db, "petugas", "call_next", f"{ticket.ticket_no} ({patient_name}) -> called")

    import asyncio
    asyncio.create_task(manager.broadcast({
        "event": "ticket_called",
        "ticket_no": ticket.ticket_no,
        "patient_name": patient_name,
        "service": service,
        "poli_name": poli_name,
        "doctor_name": doctor_name,
    }))

    return {
        "message": "Panggilan berhasil",
        "ticket_no": ticket.ticket_no,
        "queue_position": ticket.queue_position,
        "status": ticket.status,
        "service": service,
        "patient_name": patient_name,
        "poli_name": poli_name,
        "doctor_name": doctor_name,
    }


@router.post("/queue-status")
def update_queue_status(payload: dict, db: Session = Depends(get_db)):
    """Advance a ticket through the lifecycle: called→serving, serving→done, called→no_show."""
    ticket_no = (payload.get("ticket_no") or "").strip()
    new_status = (payload.get("status") or "").strip().lower()

    if not ticket_no or not new_status:
        raise HTTPException(status_code=400, detail="ticket_no dan status wajib diisi")

    ticket = db.query(QueueTicket).filter(QueueTicket.ticket_no == ticket_no).first()
    if not ticket:
        raise HTTPException(status_code=404, detail="Tiket tidak ditemukan")

    if not can_transition(ticket.status, new_status):
        raise HTTPException(
            status_code=400,
            detail=f"Tidak bisa mengubah status dari '{ticket.status}' ke '{new_status}'",
        )

    apply_status_transition(ticket, new_status)
    db.commit()
    db.refresh(ticket)

    _write_audit(db, "petugas", "status_update", f"{ticket_no}: {new_status}")

    import asyncio
    asyncio.create_task(manager.broadcast({
        "event": "ticket_status_changed",
        "ticket_no": ticket.ticket_no,
        "status": new_status,
    }))

    return {"message": f"Status tiket {ticket_no} diubah ke {new_status}", "ticket_no": ticket_no, "status": new_status}


@router.post("/queue-reset")
def queue_reset(db: Session = Depends(get_db)):
    db.query(QueueTicket).delete()
    db.commit()
    return {"message": "Semua antrian berhasil direset"}


@router.post("/queue-onsite")
def register_queue_onsite(payload: dict, db: Session = Depends(get_db)):
    from app.services.queue_service import compute_rolling_avg_serve_minutes

    full_name = (payload.get("full_name") or "").strip()
    phone = (payload.get("phone") or "").strip()
    national_id = (payload.get("national_id") or "").strip() or None
    medical_record_no = (payload.get("medical_record_no") or "").strip() or None
    birth_date = (payload.get("birth_date") or "").strip() or None
    poli_id = payload.get("poli_id")
    doctor_id = payload.get("doctor_id")
    schedule_id = payload.get("schedule_id")

    if not full_name or not phone or not poli_id or not doctor_id or not schedule_id:
        raise HTTPException(status_code=400, detail="full_name, phone, poli_id, doctor_id, schedule_id wajib diisi")

    schedule = db.query(Schedule).filter(Schedule.id == schedule_id).first()
    if not schedule:
        raise HTTPException(status_code=404, detail="Schedule tidak ditemukan")

    # Upsert patient — match by phone, NIK, or medical record number
    patient = None
    if national_id:
        patient = db.query(Patient).filter(Patient.national_id == national_id).first()
    if not patient and medical_record_no:
        patient = db.query(Patient).filter(Patient.medical_record_no == medical_record_no).first()
    if not patient:
        patient = db.query(Patient).filter(Patient.phone == phone).first()

    if not patient:
        patient = Patient(
            phone=phone,
            full_name=full_name,
            password_hash=hash_password("onsite-" + phone[-4:]),  # temporary password
            national_id=national_id,
            medical_record_no=medical_record_no,
            birth_date=birth_date,
        )
        db.add(patient)
        db.flush()
    else:
        # Update any missing fields
        patient.full_name = full_name
        if national_id and not patient.national_id:
            patient.national_id = national_id
        if medical_record_no and not patient.medical_record_no:
            patient.medical_record_no = medical_record_no
        if birth_date and not patient.birth_date:
            patient.birth_date = birth_date

    avg_serve = compute_rolling_avg_serve_minutes(db, doctor_id)

    ticket = None
    for _ in range(4):
        queue_position = get_next_queue_position(db, schedule_id)
        ticket_no = build_ticket_no(queue_position)
        ticket = QueueTicket(
            ticket_no=ticket_no,
            patient_id=patient.id,
            family_member_id=None,
            poli_id=poli_id,
            doctor_id=doctor_id,
            schedule_id=schedule_id,
            status="waiting",
            estimated_minutes=max(5, round(queue_position * avg_serve)),
            queue_position=queue_position,
            checkin_qr=f"ONSITE-{patient.id}-{datetime.utcnow().timestamp()}",
            registration_channel="on_site",
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
        raise HTTPException(status_code=409, detail="Gagal membuat nomor antrian on-site. Silakan coba lagi.")

    _write_audit(db, "console", "onsite_register", f"{full_name} ({phone}) → {ticket.ticket_no}")

    import asyncio
    asyncio.create_task(manager.broadcast({
        "event": "ticket_created",
        "ticket_no": ticket.ticket_no,
        "schedule_id": schedule_id,
        "registration_channel": "on_site",
    }))

    # Resolve names for the slip
    poli = db.query(Poli).filter(Poli.id == poli_id).first()
    doctor = db.query(Doctor).filter(Doctor.id == doctor_id).first()

    return {
        "message": "Pendaftaran on-the-spot berhasil",
        "ticket_no": ticket.ticket_no,
        "queue_position": ticket.queue_position,
        "estimated_minutes": ticket.estimated_minutes,
        "registration_channel": ticket.registration_channel,
        "checkin_qr": ticket.checkin_qr,
        "patient": {
            "id": patient.id,
            "full_name": patient.full_name,
            "phone": patient.phone,
            "national_id": patient.national_id,
            "medical_record_no": patient.medical_record_no,
        },
        "poli_name": poli.name if poli else "",
        "doctor_name": doctor.full_name if doctor else "",
        "schedule": {
            "date": schedule.date,
            "start_time": schedule.start_time,
            "end_time": schedule.end_time,
        },
    }


@router.get("/stats")
def stats(db: Session = Depends(get_db)):
    total_tickets = db.query(func.count(QueueTicket.id)).scalar() or 0
    waiting = db.query(func.count(QueueTicket.id)).filter(QueueTicket.status == "waiting").scalar() or 0
    done = db.query(func.count(QueueTicket.id)).filter(QueueTicket.status == "done").scalar() or 0
    total_doctors = db.query(func.count(Doctor.id)).scalar() or 0
    total_patients = db.query(func.count(Patient.id)).scalar() or 0
    online_count = db.query(func.count(QueueTicket.id)).filter(QueueTicket.registration_channel == "online").scalar() or 0
    offline_count = db.query(func.count(QueueTicket.id)).filter(QueueTicket.registration_channel == "on_site").scalar() or 0
    service_rows = (
        db.query(Poli.name.label("poli_name"), QueueTicket.registration_channel.label("registration_channel"))
        .join(Poli, Poli.id == QueueTicket.poli_id)
        .all()
    )
    poli_count = sum(1 for poli_name, _ in service_rows if _service_from_poli_name(poli_name) == "poli")
    farmasi_count = sum(1 for poli_name, _ in service_rows if _service_from_poli_name(poli_name) == "farmasi")
    return {
        "total_tickets": total_tickets,
        "waiting": waiting,
        "done": done,
        "total_doctors": total_doctors,
        "total_patients": total_patients,
        "registration_channels": {
            "online": online_count,
            "on_site": offline_count,
        },
        "service_counts": {
            "poli": poli_count,
            "farmasi": farmasi_count,
        },
    }


@router.get("/doctors")
def list_doctors(db: Session = Depends(get_db)):
    rows = (
        db.query(Doctor, Poli.name.label("poli_name"))
        .join(Poli, Poli.id == Doctor.poli_id)
        .order_by(Doctor.id.desc())
        .all()
    )
    return [
        {
            "id": doctor.id,
            "full_name": doctor.full_name,
            "specialization": doctor.specialization,
            "poli_id": doctor.poli_id,
            "poli_name": poli_name,
            "photo_filename": doctor.photo_filename,
            "photo_url": _photo_url(doctor.photo_filename),
        }
        for doctor, poli_name in rows
    ]


@router.post("/doctors")
async def add_doctor(
    full_name: str = Form(...),
    specialization: str = Form(...),
    poli_id: int = Form(...),
    photo: UploadFile | None = File(None),
    db: Session = Depends(get_db),
):
    full_name = full_name.strip()
    specialization = specialization.strip()
    if not full_name or not specialization or not poli_id:
        raise HTTPException(status_code=400, detail="full_name, specialization, dan poli_id wajib diisi")

    poli = db.query(Poli).filter(Poli.id == poli_id).first()
    if not poli:
        raise HTTPException(status_code=404, detail="Poli tidak ditemukan")

    photo_filename = _store_photo(photo)

    doctor = Doctor(full_name=full_name, specialization=specialization, poli_id=poli_id, photo_filename=photo_filename)
    db.add(doctor)
    db.commit()
    db.refresh(doctor)
    return {"message": "Doctor added", "id": doctor.id, "photo_url": _photo_url(doctor.photo_filename)}


@router.put("/doctors/{doctor_id}")
def update_doctor(
    doctor_id: int,
    full_name: str = Form(...),
    specialization: str = Form(...),
    poli_id: int = Form(...),
    photo: UploadFile | None = File(None),
    db: Session = Depends(get_db),
):
    doctor = db.query(Doctor).filter(Doctor.id == doctor_id).first()
    if not doctor:
        raise HTTPException(status_code=404, detail="Doctor tidak ditemukan")

    poli = db.query(Poli).filter(Poli.id == poli_id).first()
    if not poli:
        raise HTTPException(status_code=404, detail="Poli tidak ditemukan")

    doctor.full_name = full_name.strip()
    doctor.specialization = specialization.strip()
    doctor.poli_id = poli_id

    new_photo = _store_photo(photo)
    if new_photo:
        if doctor.photo_filename:
            old_path = UPLOAD_DIR / doctor.photo_filename
            if old_path.exists():
                old_path.unlink(missing_ok=True)
        doctor.photo_filename = new_photo

    db.commit()
    db.refresh(doctor)
    return {"message": "Doctor updated", "id": doctor.id, "photo_url": _photo_url(doctor.photo_filename)}


@router.delete("/doctors/{doctor_id}")
def delete_doctor(doctor_id: int, db: Session = Depends(get_db)):
    doctor = db.query(Doctor).filter(Doctor.id == doctor_id).first()
    if not doctor:
        raise HTTPException(status_code=404, detail="Doctor tidak ditemukan")

    schedule_count = db.query(func.count(Schedule.id)).filter(Schedule.doctor_id == doctor_id).scalar() or 0
    queue_count = db.query(func.count(QueueTicket.id)).filter(QueueTicket.doctor_id == doctor_id).scalar() or 0
    if schedule_count > 0 or queue_count > 0:
        raise HTTPException(status_code=400, detail="Doctor sudah dipakai di jadwal/antrian dan tidak bisa dihapus")

    if doctor.photo_filename:
        photo_path = UPLOAD_DIR / doctor.photo_filename
        if photo_path.exists():
            photo_path.unlink(missing_ok=True)

    db.delete(doctor)
    db.commit()
    return {"message": "Doctor deleted"}


@router.get("/patients")
def list_patients(db: Session = Depends(get_db)):
    rows = db.query(Patient).order_by(Patient.id.desc()).limit(100).all()
    return [
        {
            "id": x.id,
            "full_name": x.full_name,
            "phone": x.phone,
            "national_id": x.national_id,
            "created_at": x.created_at.isoformat(),
        }
        for x in rows
    ]


@router.get("/visits")
def recent_visits(db: Session = Depends(get_db)):
    rows = (
        db.query(VisitHistory, Patient.full_name.label("patient_name"))
        .join(Patient, Patient.id == VisitHistory.patient_id)
        .order_by(VisitHistory.id.desc())
        .limit(100)
        .all()
    )
    return [
        {
            "patient_id": visit.patient_id,
            "patient_name": patient_name,
            "doctor_name": visit.doctor_name,
            "poli_name": visit.poli_name,
            "diagnosis_summary": visit.diagnosis_summary,
            "visit_date": visit.visit_date,
        }
        for visit, patient_name in rows
    ]


@router.post("/seed")
def seed_master_data(db: Session = Depends(get_db)):
    if db.query(func.count(Poli.id)).scalar() == 0:
        poli_names = ["Poli Umum", "Poli Anak", "Poli Jantung", "Poli Mata"]
        for name in poli_names:
            db.add(Poli(name=name))
        db.commit()

    if db.query(func.count(Doctor.id)).scalar() == 0:
        poli_rows = db.query(Poli).all()
        for p in poli_rows:
            db.add(Doctor(full_name=f"dr. {p.name.split()[-1]} 1", specialization=p.name, poli_id=p.id, photo_filename=None))
            db.add(Doctor(full_name=f"dr. {p.name.split()[-1]} 2", specialization=p.name, poli_id=p.id, photo_filename=None))
        db.commit()

    if db.query(func.count(Schedule.id)).scalar() == 0:
        docs = db.query(Doctor).all()
        for d in docs:
            db.add(Schedule(doctor_id=d.id, poli_id=d.poli_id, date="2026-04-23", start_time="08:00", end_time="12:00", quota=40))
            db.add(Schedule(doctor_id=d.id, poli_id=d.poli_id, date="2026-04-24", start_time="13:00", end_time="16:00", quota=30))
        db.commit()

    if db.query(func.count(Patient.id)).scalar() == 0:
        patients = [
            Patient(phone="0811111111", full_name="Siti Aisyah", password_hash=hash_password("123456"), national_id="3201010101010001", medical_record_no="RM-0001"),
            Patient(phone="0822222222", full_name="Budi Santoso", password_hash=hash_password("123456"), national_id="3201010101010002", medical_record_no="RM-0002"),
            Patient(phone="0833333333", full_name="Rina Marlina", password_hash=hash_password("123456"), national_id="3201010101010003", medical_record_no="RM-0003"),
        ]
        db.add_all(patients)
        db.commit()

    seeded_updates = {
        "0811111111": {"medical_record_no": "RM-0001", "national_id": "3201010101010001"},
        "0822222222": {"medical_record_no": "RM-0002", "national_id": "3201010101010002"},
        "0833333333": {"medical_record_no": "RM-0003", "national_id": "3201010101010003"},
    }
    changed = False
    for phone, payload in seeded_updates.items():
        patient = db.query(Patient).filter(Patient.phone == phone).first()
        if not patient:
            continue
        if not patient.medical_record_no:
            patient.medical_record_no = payload["medical_record_no"]
            changed = True
        if not patient.national_id:
            patient.national_id = payload["national_id"]
            changed = True
        if patient.password_hash == "seed":
            patient.password_hash = hash_password("123456")
            changed = True
    if changed:
        db.commit()

    if db.query(func.count(QueueTicket.id)).scalar() == 0:
        patients = db.query(Patient).all()
        doctors = db.query(Doctor).all()
        schedules = db.query(Schedule).all()
        if patients and doctors and schedules:
            queue_rows = [
                QueueTicket(ticket_no="A-001", patient_id=patients[0].id, poli_id=doctors[0].poli_id, doctor_id=doctors[0].id, schedule_id=schedules[0].id, status="waiting", estimated_minutes=18, queue_position=1, checkin_qr="seed-1"),
                QueueTicket(ticket_no="A-002", patient_id=patients[1].id, poli_id=doctors[1].poli_id, doctor_id=doctors[1].id, schedule_id=schedules[1].id, status="called", estimated_minutes=8, queue_position=2, checkin_qr="seed-2", registration_channel="on_site"),
                QueueTicket(ticket_no="A-003", patient_id=patients[2].id, poli_id=doctors[2].poli_id, doctor_id=doctors[2].id, schedule_id=schedules[2].id, status="serving", estimated_minutes=0, queue_position=3, checkin_qr="seed-3", registration_channel="online"),
            ]
            db.add_all(queue_rows)
            db.commit()

    if db.query(func.count(VisitHistory.id)).scalar() == 0:
        patients = db.query(Patient).all()
        if patients:
            db.add_all([
                VisitHistory(patient_id=patients[0].id, doctor_name="dr. Andi", poli_name="Poli Umum", diagnosis_summary="Kontrol rutin dan resep obat", visit_date="2026-04-20"),
                VisitHistory(patient_id=patients[1].id, doctor_name="dr. Sari", poli_name="Poli Anak", diagnosis_summary="Demam ringan, observasi lanjutan", visit_date="2026-04-21"),
            ])
            db.commit()

    # Seed default admin users
    if db.query(func.count(AdminUser.id)).scalar() == 0:
        default_admins = [
            AdminUser(username="administrator", password_hash=hash_password("admin123"), role="administrator"),
            AdminUser(username="petugas", password_hash=hash_password("panggil123"), role="petugas"),
            AdminUser(username="console", password_hash=hash_password("console123"), role="console"),
            AdminUser(username="display", password_hash=hash_password("display123"), role="display"),
        ]
        db.add_all(default_admins)
        db.commit()

    return {"message": "Seed completed"}


# ── Admin Auth ──────────────────────────────────────────────────────────────

@router.post("/auth/login")
def admin_login(payload: dict, db: Session = Depends(get_db)):
    from app.core.security import create_access_token, verify_password
    username = (payload.get("username") or "").strip()
    password = payload.get("password") or ""
    user = db.query(AdminUser).filter(AdminUser.username == username, AdminUser.is_active == True).first()
    if not user or not verify_password(password, user.password_hash):
        raise HTTPException(status_code=401, detail="Username atau password salah")
    token = create_access_token(f"admin:{user.username}:{user.role}")
    _write_audit(db, username, "admin_login", f"role={user.role}")
    return {"access_token": token, "token_type": "bearer", "role": user.role, "username": user.username}


@router.get("/auth/users")
def list_admin_users(db: Session = Depends(get_db)):
    rows = db.query(AdminUser).order_by(AdminUser.id.asc()).all()
    return [{"id": u.id, "username": u.username, "role": u.role, "is_active": u.is_active} for u in rows]


@router.post("/auth/users")
def create_admin_user(payload: dict, db: Session = Depends(get_db)):
    from app.core.security import hash_password
    username = (payload.get("username") or "").strip()
    password = payload.get("password") or ""
    role = (payload.get("role") or "petugas").strip()
    if not username or not password:
        raise HTTPException(status_code=400, detail="username dan password wajib diisi")
    if role not in {"administrator", "petugas", "console", "display"}:
        raise HTTPException(status_code=400, detail="role tidak valid")
    if db.query(AdminUser).filter(AdminUser.username == username).first():
        raise HTTPException(status_code=409, detail="Username sudah digunakan")
    user = AdminUser(username=username, password_hash=hash_password(password), role=role)
    db.add(user)
    db.commit()
    _write_audit(db, "administrator", "create_user", f"{username} ({role})")
    return {"message": "User berhasil dibuat", "id": user.id}


# ── Schedule Management ─────────────────────────────────────────────────────

@router.post("/schedules")
def create_schedule(payload: dict, db: Session = Depends(get_db)):
    doctor_id = payload.get("doctor_id")
    poli_id = payload.get("poli_id")
    date = (payload.get("date") or "").strip()
    start_time = (payload.get("start_time") or "").strip()
    end_time = (payload.get("end_time") or "").strip()
    quota = int(payload.get("quota") or 30)

    if not all([doctor_id, poli_id, date, start_time, end_time]):
        raise HTTPException(status_code=400, detail="doctor_id, poli_id, date, start_time, end_time wajib diisi")

    schedule = Schedule(doctor_id=doctor_id, poli_id=poli_id, date=date, start_time=start_time, end_time=end_time, quota=quota)
    db.add(schedule)
    db.commit()
    db.refresh(schedule)
    _write_audit(db, "administrator", "create_schedule", f"doctor_id={doctor_id} date={date}")
    return {"message": "Jadwal berhasil dibuat", "id": schedule.id}


@router.put("/schedules/{schedule_id}")
def update_schedule(schedule_id: int, payload: dict, db: Session = Depends(get_db)):
    schedule = db.query(Schedule).filter(Schedule.id == schedule_id).first()
    if not schedule:
        raise HTTPException(status_code=404, detail="Jadwal tidak ditemukan")
    if "date" in payload:
        schedule.date = payload["date"]
    if "start_time" in payload:
        schedule.start_time = payload["start_time"]
    if "end_time" in payload:
        schedule.end_time = payload["end_time"]
    if "quota" in payload:
        schedule.quota = int(payload["quota"])
    db.commit()
    _write_audit(db, "administrator", "update_schedule", f"id={schedule_id}")
    return {"message": "Jadwal diperbarui"}


@router.delete("/schedules/{schedule_id}")
def delete_schedule(schedule_id: int, db: Session = Depends(get_db)):
    schedule = db.query(Schedule).filter(Schedule.id == schedule_id).first()
    if not schedule:
        raise HTTPException(status_code=404, detail="Jadwal tidak ditemukan")
    active = db.query(QueueTicket).filter(
        QueueTicket.schedule_id == schedule_id,
        QueueTicket.status.in_(["waiting", "called", "serving"]),
    ).count()
    if active > 0:
        raise HTTPException(status_code=400, detail="Jadwal masih memiliki antrian aktif")
    db.delete(schedule)
    db.commit()
    _write_audit(db, "administrator", "delete_schedule", f"id={schedule_id}")
    return {"message": "Jadwal dihapus"}


# ── Poli Management ─────────────────────────────────────────────────────────

@router.post("/polis")
def create_poli(payload: dict, db: Session = Depends(get_db)):
    name = (payload.get("name") or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="name wajib diisi")
    if db.query(Poli).filter(Poli.name == name).first():
        raise HTTPException(status_code=409, detail="Nama poli sudah ada")
    poli = Poli(name=name)
    db.add(poli)
    db.commit()
    db.refresh(poli)
    return {"message": "Poli berhasil dibuat", "id": poli.id}


@router.delete("/polis/{poli_id}")
def delete_poli(poli_id: int, db: Session = Depends(get_db)):
    poli = db.query(Poli).filter(Poli.id == poli_id).first()
    if not poli:
        raise HTTPException(status_code=404, detail="Poli tidak ditemukan")
    if db.query(Doctor).filter(Doctor.poli_id == poli_id).count() > 0:
        raise HTTPException(status_code=400, detail="Poli masih memiliki dokter terdaftar")
    db.delete(poli)
    db.commit()
    return {"message": "Poli dihapus"}


# ── Audit Log ───────────────────────────────────────────────────────────────

@router.get("/audit-logs")
def get_audit_logs(limit: int = 100, db: Session = Depends(get_db)):
    rows = db.query(AuditLog).order_by(AuditLog.id.desc()).limit(limit).all()
    return [
        {"id": r.id, "actor": r.actor, "action": r.action, "detail": r.detail, "created_at": r.created_at.isoformat()}
        for r in rows
    ]


# ── Analytics ───────────────────────────────────────────────────────────────

@router.get("/analytics/wait-times")
def analytics_wait_times(db: Session = Depends(get_db)):
    """Average actual serve time per doctor."""
    rows = (
        db.query(Doctor.full_name, Poli.name.label("poli_name"), func.avg(QueueTicket.actual_serve_minutes).label("avg_minutes"), func.count(QueueTicket.id).label("total"))
        .join(QueueTicket, QueueTicket.doctor_id == Doctor.id)
        .join(Poli, Poli.id == Doctor.poli_id)
        .filter(QueueTicket.actual_serve_minutes.isnot(None))
        .group_by(Doctor.id)
        .all()
    )
    return [
        {"doctor": r.full_name, "poli": r.poli_name, "avg_serve_minutes": round(r.avg_minutes or 0, 1), "total_served": r.total}
        for r in rows
    ]


@router.get("/analytics/daily")
def analytics_daily(db: Session = Depends(get_db)):
    """Ticket counts grouped by date."""
    rows = (
        db.query(func.substr(QueueTicket.created_at, 1, 10).label("date"), func.count(QueueTicket.id).label("total"))
        .group_by(func.substr(QueueTicket.created_at, 1, 10))
        .order_by(func.substr(QueueTicket.created_at, 1, 10).desc())
        .limit(30)
        .all()
    )
    return [{"date": r.date, "total": r.total} for r in rows]
