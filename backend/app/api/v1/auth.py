import random

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.api.deps import get_current_patient
from app.core.database import get_db
from app.core.security import create_access_token, hash_password, verify_password
from app.models.entities import FamilyMember, OtpCode, Patient
from app.schemas.auth import LoginRequest, OtpRequest, OtpVerifyRequest, PatientLoginRequest, RegisterRequest, TokenResponse

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=TokenResponse)
def register(payload: RegisterRequest, db: Session = Depends(get_db)):
    existing = db.query(Patient).filter(Patient.phone == payload.phone).first()
    if existing:
        raise HTTPException(status_code=400, detail="Phone already registered")

    patient = Patient(phone=payload.phone, full_name=payload.full_name, password_hash=hash_password(payload.password))
    db.add(patient)
    db.commit()

    token = create_access_token(payload.phone)
    return TokenResponse(access_token=token)


@router.post("/login", response_model=TokenResponse)
def login(payload: LoginRequest, db: Session = Depends(get_db)):
    patient = db.query(Patient).filter(Patient.phone == payload.phone).first()
    if not patient or not verify_password(payload.password, patient.password_hash):
        raise HTTPException(status_code=401, detail="Invalid credentials")

    token = create_access_token(patient.phone)
    return TokenResponse(access_token=token)


@router.post("/patient-login", response_model=TokenResponse)
def patient_login(payload: PatientLoginRequest, db: Session = Depends(get_db)):
    identifier = payload.identifier.strip()
    patient = (
        db.query(Patient)
        .filter(
            (Patient.national_id == identifier)
            | (Patient.medical_record_no == identifier)
            | (Patient.phone == identifier)
        )
        .first()
    )
    if not patient or not verify_password(payload.password, patient.password_hash):
        raise HTTPException(status_code=401, detail="NIK / No Rekam Medis atau password tidak valid")

    token = create_access_token(patient.phone)
    return TokenResponse(access_token=token)


@router.post("/otp/request")
def request_otp(payload: OtpRequest, db: Session = Depends(get_db)):
    code = f"{random.randint(100000, 999999)}"
    otp = OtpCode(phone=payload.phone, code=code)
    db.add(otp)
    db.commit()
    return {"message": "OTP generated", "dev_otp": code}


@router.post("/otp/verify")
def verify_otp(payload: OtpVerifyRequest, db: Session = Depends(get_db)):
    otp = db.query(OtpCode).filter(OtpCode.phone == payload.phone, OtpCode.code == payload.code).order_by(OtpCode.id.desc()).first()
    if not otp:
        raise HTTPException(status_code=400, detail="Invalid OTP")
    otp.is_verified = True
    db.commit()
    return {"message": "OTP verified"}


@router.get("/profile")
def get_profile(patient: Patient = Depends(get_current_patient), db: Session = Depends(get_db)):
    family = db.query(FamilyMember).filter(FamilyMember.patient_id == patient.id).all()
    return {
        "id": patient.id,
        "phone": patient.phone,
        "full_name": patient.full_name,
        "national_id": patient.national_id,
        "medical_record_no": patient.medical_record_no,
        "family_members": [
            {
                "id": x.id,
                "full_name": x.full_name,
                "relationship_name": x.relationship_name,
                "birth_date": x.birth_date,
            }
            for x in family
        ],
    }


@router.post("/family")
def add_family_member(payload: dict, patient: Patient = Depends(get_current_patient), db: Session = Depends(get_db)):
    member = FamilyMember(
        patient_id=patient.id,
        full_name=payload.get("full_name", ""),
        relationship_name=payload.get("relationship_name", "Keluarga"),
        birth_date=payload.get("birth_date"),
    )
    db.add(member)
    db.commit()
    return {"message": "Family member added", "id": member.id}
