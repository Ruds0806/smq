from datetime import datetime

from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class Patient(Base):
    __tablename__ = "patients"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    phone: Mapped[str] = mapped_column(String(20), unique=True, index=True)
    full_name: Mapped[str] = mapped_column(String(120))
    password_hash: Mapped[str] = mapped_column(String(255))
    national_id: Mapped[str | None] = mapped_column(String(30), nullable=True)
    medical_record_no: Mapped[str | None] = mapped_column(String(40), nullable=True)
    birth_date: Mapped[str | None] = mapped_column(String(20), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class FamilyMember(Base):
    __tablename__ = "family_members"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    patient_id: Mapped[int] = mapped_column(ForeignKey("patients.id"), index=True)
    full_name: Mapped[str] = mapped_column(String(120))
    relationship_name: Mapped[str] = mapped_column(String(60))
    birth_date: Mapped[str | None] = mapped_column(String(20), nullable=True)


class Poli(Base):
    __tablename__ = "polis"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(120), unique=True)


class Doctor(Base):
    __tablename__ = "doctors"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    full_name: Mapped[str] = mapped_column(String(120))
    specialization: Mapped[str] = mapped_column(String(120))
    poli_id: Mapped[int] = mapped_column(ForeignKey("polis.id"))
    photo_filename: Mapped[str | None] = mapped_column(String(255), nullable=True)


class Schedule(Base):
    __tablename__ = "schedules"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    doctor_id: Mapped[int] = mapped_column(ForeignKey("doctors.id"))
    poli_id: Mapped[int] = mapped_column(ForeignKey("polis.id"))
    date: Mapped[str] = mapped_column(String(20))
    start_time: Mapped[str] = mapped_column(String(10))
    end_time: Mapped[str] = mapped_column(String(10))
    quota: Mapped[int] = mapped_column(Integer, default=30)


class QueueTicket(Base):
    __tablename__ = "queue_tickets"
    __table_args__ = (UniqueConstraint("schedule_id", "queue_position", name="uq_queue_schedule_position"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    ticket_no: Mapped[str] = mapped_column(String(20), index=True)
    patient_id: Mapped[int] = mapped_column(ForeignKey("patients.id"), index=True)
    family_member_id: Mapped[int | None] = mapped_column(ForeignKey("family_members.id"), nullable=True)
    poli_id: Mapped[int] = mapped_column(ForeignKey("polis.id"))
    doctor_id: Mapped[int] = mapped_column(ForeignKey("doctors.id"))
    schedule_id: Mapped[int] = mapped_column(ForeignKey("schedules.id"))
    status: Mapped[str] = mapped_column(String(30), default="waiting")
    estimated_minutes: Mapped[int] = mapped_column(Integer, default=30)
    queue_position: Mapped[int] = mapped_column(Integer)
    checkin_qr: Mapped[str] = mapped_column(String(120))
    registration_channel: Mapped[str] = mapped_column(String(20), default="online")
    called_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    serving_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    done_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    actual_serve_minutes: Mapped[float | None] = mapped_column(Float, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class AdminUser(Base):
    __tablename__ = "admin_users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    username: Mapped[str] = mapped_column(String(60), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    role: Mapped[str] = mapped_column(String(30), default="petugas")
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class AuditLog(Base):
    __tablename__ = "audit_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    actor: Mapped[str] = mapped_column(String(80))
    action: Mapped[str] = mapped_column(String(80))
    detail: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class VisitHistory(Base):
    __tablename__ = "visit_histories"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    patient_id: Mapped[int] = mapped_column(ForeignKey("patients.id"), index=True)
    doctor_name: Mapped[str] = mapped_column(String(120))
    poli_name: Mapped[str] = mapped_column(String(120))
    diagnosis_summary: Mapped[str] = mapped_column(Text, default="")
    visit_date: Mapped[str] = mapped_column(String(20))


class OtpCode(Base):
    __tablename__ = "otp_codes"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    phone: Mapped[str] = mapped_column(String(20), index=True)
    code: Mapped[str] = mapped_column(String(6))
    is_verified: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
