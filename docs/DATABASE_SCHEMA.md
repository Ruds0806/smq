# SmartQueue RS - Database Schema

## Core Tables

### patients
- id (PK)
- phone (unique)
- full_name
- password_hash
- national_id
- birth_date
- created_at

### family_members
- id (PK)
- patient_id (FK -> patients.id)
- full_name
- relationship_name
- birth_date

### polis
- id (PK)
- name (unique)

### doctors
- id (PK)
- full_name
- specialization
- poli_id (FK -> polis.id)

### schedules
- id (PK)
- doctor_id (FK -> doctors.id)
- poli_id (FK -> polis.id)
- date
- start_time
- end_time
- quota

### queue_tickets
- id (PK)
- ticket_no
- patient_id (FK -> patients.id)
- family_member_id (FK -> family_members.id, nullable)
- poli_id (FK -> polis.id)
- doctor_id (FK -> doctors.id)
- schedule_id (FK -> schedules.id)
- status (waiting/called/done/cancelled)
- estimated_minutes
- queue_position
- checkin_qr
- created_at

### visit_histories
- id (PK)
- patient_id (FK -> patients.id)
- doctor_name
- poli_name
- diagnosis_summary
- visit_date

### otp_codes
- id (PK)
- phone
- code
- is_verified
- created_at

## Cloud Database Recommendation
- Production: PostgreSQL (managed cloud)
- Realtime queue updates: Redis pub/sub + WebSocket gateway
- Audit trail: separate event log table (recommended)
