# SmartQueue RS - API Endpoints

Base URL: `/api/v1`

## Auth & Patient
- `POST /auth/register`
- `POST /auth/login`
- `POST /auth/otp/request`
- `POST /auth/otp/verify`
- `GET /auth/profile`
- `POST /auth/family`

## Queue
- `GET /queue/polis`
- `GET /queue/doctors?poli_id={id}`
- `GET /queue/schedules?doctor_id={id}`
- `POST /queue/take`
- `GET /queue/dashboard`

## History
- `GET /history/queues`
- `GET /history/visits`

## Admin Web
- `GET /admin/queue-monitor`
- `GET /admin/stats`
- `POST /admin/seed`

## WebSocket
- `GET ws://{host}/ws/admin/queue`

## SIMRS Integration Points (Design)
- `GET /simrs/doctors-sync`
- `GET /simrs/schedules-sync`
- `POST /simrs/visit-push`

Note: SIMRS endpoints are prepared conceptually and should be mapped to vendor-specific contract.
