from pydantic import BaseModel


class QueueCreateRequest(BaseModel):
    poli_id: int
    doctor_id: int
    schedule_id: int
    family_member_id: int | None = None


class QueueTicketResponse(BaseModel):
    id: int
    ticket_no: str
    status: str
    queue_position: int
    estimated_minutes: int
    checkin_qr: str
