# Entity-Relationship Diagram

GitHub renders the Mermaid diagram below automatically. For the LMS write-up, take a screenshot of the rendered diagram (or paste the code into https://mermaid.live and export a PNG into `../screenshots/`).

```mermaid
erDiagram
    DEPARTMENT ||--o{ LECTURER        : employs
    DEPARTMENT ||--o{ PROGRAMME       : offers
    DEPARTMENT ||--o{ COURSE          : owns
    PROGRAMME  ||--o{ STUDENT         : enrols
    TERM       ||--o{ COURSE_OFFERING : schedules
    COURSE     ||--o{ COURSE_OFFERING : "is delivered as"
    LECTURER   ||--o{ COURSE_OFFERING : teaches
    STUDENT    ||--o{ REGISTRATION    : makes
    COURSE_OFFERING ||--o{ REGISTRATION : receives
    REGISTRATION ||--o| GRADE         : "is assessed by"
    GRADE_SCALE  ||--o{ GRADE         : classifies
    LECTURER   ||--o{ GRADE           : enters
    GRADE      ||--o{ GRADE_AUDIT     : "is logged in"

    DEPARTMENT {
        smallint department_id PK
        varchar code UK
        varchar name UK
        varchar faculty
    }
    LECTURER {
        int lecturer_id PK
        smallint department_id FK
        varchar staff_no UK
        varchar email UK
        varchar rank_title
    }
    PROGRAMME {
        smallint programme_id PK
        smallint department_id FK
        varchar name
        varchar award
        smallint duration_years
    }
    STUDENT {
        int student_id PK
        varchar matric_no UK
        varchar email UK
        date date_of_birth
        smallint programme_id FK
        smallint entry_year
        varchar status
    }
    TERM {
        smallint term_id PK
        varchar session_label
        smallint semester
        date start_date
        date end_date
        boolean registration_open
    }
    COURSE {
        int course_id PK
        varchar code UK
        varchar title
        smallint credit_units
        smallint level
        smallint department_id FK
    }
    COURSE_OFFERING {
        int offering_id PK
        int course_id FK
        smallint term_id FK
        int lecturer_id FK
        int capacity
    }
    REGISTRATION {
        bigint registration_id PK
        int student_id FK
        int offering_id FK
        timestamptz registered_at
        varchar status
    }
    GRADE_SCALE {
        char letter_grade PK
        numeric min_score UK
        numeric grade_point
    }
    GRADE {
        bigint registration_id PK, FK
        numeric ca_score
        numeric exam_score
        numeric total_score "generated"
        char letter_grade FK
        numeric grade_point
        int entered_by FK
        timestamptz entered_at
    }
    GRADE_AUDIT {
        bigint audit_id PK
        bigint registration_id
        varchar action
        numeric old_total
        numeric new_total
        text changed_by
        timestamptz changed_at
    }
```

**Reading the diagram.** `STUDENT` and `COURSE_OFFERING` have a many-to-many relationship, resolved by the associative entity `REGISTRATION`. `GRADE` shares its primary key with `REGISTRATION` (a one-to-zero-or-one relationship: a registration may not yet have a grade). `UK` = unique key, `FK` = foreign key.
