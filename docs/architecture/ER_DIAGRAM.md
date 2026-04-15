# UKonek ER Diagram

Last updated: 2026-04-05

```mermaid
erDiagram
    STAFF {
        bigint id PK
        varchar username UK
        varchar employee_id UK
        varchar email UK
        varchar role
        varchar status
        uuid auth_user_id UK
        boolean is_online
        timestamptz last_seen
        text doctor_specialization
    }

    CITIZENS {
        bigint id PK
        varchar email UK
        varchar username UK
        varchar role
        uuid auth_user_id UK
    }

    DOCTOR_SCHEDULES {
        bigint id PK
        bigint doctor_staff_id FK
        bigint created_by_staff_id FK
        date schedule_date
        time start_time
        time end_time
    }

    APPOINTMENTS {
        bigint id PK
        bigint citizen_id FK
        bigint doctor_staff_id FK
        date appointment_date
        time appointment_time
        varchar status
    }

    ANNOUNCEMENTS {
        bigint id PK
        bigint created_by_staff_id FK
        text title
        text visibility
    }

    FEEDBACKS {
        bigint id PK
        bigint citizen_id FK
        text from_email
        smallint rating
    }

    MEDICINES {
        bigint id PK
        bigint created_by_staff_id FK
        text name
        integer qty
        timestamptz archived_at
    }

    CONSULTATIONS {
        bigint id PK
        bigint patient_citizen_id FK
        bigint doctor_staff_id FK
        text diagnosis
        timestamptz consulted_at
    }

    PRESCRIPTION_HEADERS {
        bigint id PK
        bigint consultation_id FK
        bigint doctor_staff_id FK
        timestamptz issued_at
    }

    PRESCRIPTION_ITEMS {
        bigint id PK
        bigint prescription_id FK
        text medicine_name
        integer quantity
    }

    QUEUE_TICKETS {
        bigint id PK
        bigint citizen_id FK
        date queue_date
        text service_key
        integer queue_number
        text ticket_code UK
        text citizen_type
        text status
    }

    PENDING_CITIZEN_SIGNUPS {
        bigint id PK
        text email UK
        jsonb profile
        text otp_hash
        timestamptz otp_expires_at
        integer attempts_left
        timestamptz verified_at
        timestamptz consumed_at
    }

    STAFF ||--o{ DOCTOR_SCHEDULES : doctor_staff_id
    STAFF ||--o{ DOCTOR_SCHEDULES : created_by_staff_id
    STAFF ||--o{ APPOINTMENTS : doctor_staff_id
    CITIZENS ||--o{ APPOINTMENTS : citizen_id

    STAFF ||--o{ ANNOUNCEMENTS : created_by_staff_id
    CITIZENS ||--o{ FEEDBACKS : citizen_id
    STAFF ||--o{ MEDICINES : created_by_staff_id

    STAFF ||--o{ CONSULTATIONS : doctor_staff_id
    CITIZENS ||--o{ CONSULTATIONS : patient_citizen_id

    CONSULTATIONS ||--o{ PRESCRIPTION_HEADERS : consultation_id
    STAFF ||--o{ PRESCRIPTION_HEADERS : doctor_staff_id
    PRESCRIPTION_HEADERS ||--o{ PRESCRIPTION_ITEMS : prescription_id

    CITIZENS ||--o{ QUEUE_TICKETS : citizen_id
```

## Notes

- This ERD models current active tables only.
- Historical tables removed by migrations are intentionally omitted.
- Auth users live in Supabase auth schema and are linked by `auth_user_id` in `staff` and `citizens`.
