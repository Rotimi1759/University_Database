-- =====================================================================
-- MIT 8103 | Portfolio 1 | University Student Result Portal
-- 01_schema.sql : tables, keys, constraints
-- Target DBMS: PostgreSQL 16 (works on 14+)
-- Run:  psql -d portal -f 01_schema.sql
-- =====================================================================
DROP SCHEMA IF EXISTS result_portal CASCADE;
CREATE SCHEMA result_portal;
SET search_path TO result_portal, public;

-- ---------- Reference / organisational data --------------------------
CREATE TABLE department (
    department_id  SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code           VARCHAR(10)  NOT NULL UNIQUE,
    name           VARCHAR(100) NOT NULL UNIQUE,
    faculty        VARCHAR(100) NOT NULL
);

CREATE TABLE lecturer (
    lecturer_id    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    department_id  SMALLINT     NOT NULL
                   REFERENCES department(department_id)
                   ON UPDATE CASCADE ON DELETE RESTRICT,
    staff_no       VARCHAR(20)  NOT NULL UNIQUE,
    first_name     VARCHAR(50)  NOT NULL,
    last_name      VARCHAR(50)  NOT NULL,
    email          VARCHAR(120) NOT NULL UNIQUE CHECK (email LIKE '%_@_%'),
    rank_title     VARCHAR(30)  NOT NULL DEFAULT 'Lecturer I'
                   CHECK (rank_title IN ('Assistant Lecturer','Lecturer II','Lecturer I',
                                         'Senior Lecturer','Associate Professor','Professor'))
);

CREATE TABLE programme (
    programme_id    SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    department_id   SMALLINT     NOT NULL
                    REFERENCES department(department_id)
                    ON UPDATE CASCADE ON DELETE RESTRICT,
    name            VARCHAR(120) NOT NULL,
    award           VARCHAR(10)  NOT NULL CHECK (award IN ('BSc','MSc','MIT','PGD','PhD')),
    duration_years  SMALLINT     NOT NULL CHECK (duration_years BETWEEN 1 AND 6),
    UNIQUE (department_id, name)
);

CREATE TABLE student (
    student_id     INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    matric_no      VARCHAR(20)  NOT NULL UNIQUE,
    first_name     VARCHAR(50)  NOT NULL,
    last_name      VARCHAR(50)  NOT NULL,
    email          VARCHAR(120) NOT NULL UNIQUE CHECK (email LIKE '%_@_%'),
    date_of_birth  DATE         NOT NULL CHECK (date_of_birth > DATE '1950-01-01'),
    programme_id   SMALLINT     NOT NULL
                   REFERENCES programme(programme_id)
                   ON UPDATE CASCADE ON DELETE RESTRICT,
    entry_year     SMALLINT     NOT NULL CHECK (entry_year BETWEEN 2000 AND 2100),
    status         VARCHAR(10)  NOT NULL DEFAULT 'ACTIVE'
                   CHECK (status IN ('ACTIVE','SUSPENDED','GRADUATED','WITHDRAWN'))
);

CREATE TABLE term (                       -- one academic session + semester
    term_id            SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    session_label      VARCHAR(9) NOT NULL CHECK (session_label ~ '^[0-9]{4}/[0-9]{4}$'),
    semester           SMALLINT   NOT NULL CHECK (semester IN (1,2)),
    start_date         DATE       NOT NULL,
    end_date           DATE       NOT NULL,
    registration_open  BOOLEAN    NOT NULL DEFAULT FALSE,
    UNIQUE (session_label, semester),
    CHECK (end_date > start_date)
);

CREATE TABLE course (
    course_id      INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code           VARCHAR(10)  NOT NULL UNIQUE CHECK (code ~ '^[A-Z]{3}[0-9]{3}$'),
    title          VARCHAR(150) NOT NULL,
    credit_units   SMALLINT     NOT NULL CHECK (credit_units BETWEEN 1 AND 6),
    level          SMALLINT     NOT NULL CHECK (level BETWEEN 100 AND 900 AND level % 100 = 0),
    department_id  SMALLINT     NOT NULL
                   REFERENCES department(department_id)
                   ON UPDATE CASCADE ON DELETE RESTRICT
);

-- A course delivered in a given term by one responsible lecturer
CREATE TABLE course_offering (
    offering_id  INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    course_id    INT      NOT NULL REFERENCES course(course_id)     ON DELETE RESTRICT,
    term_id      SMALLINT NOT NULL REFERENCES term(term_id)         ON DELETE RESTRICT,
    lecturer_id  INT      NOT NULL REFERENCES lecturer(lecturer_id) ON DELETE RESTRICT,
    capacity     INT      NOT NULL DEFAULT 100 CHECK (capacity > 0),
    UNIQUE (course_id, term_id)
);

-- Registration = a student enrolling on a course offering
CREATE TABLE registration (
    registration_id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_id       INT         NOT NULL REFERENCES student(student_id)           ON DELETE RESTRICT,
    offering_id      INT         NOT NULL REFERENCES course_offering(offering_id)  ON DELETE RESTRICT,
    registered_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    status           VARCHAR(10) NOT NULL DEFAULT 'REGISTERED'
                     CHECK (status IN ('REGISTERED','DROPPED')),
    UNIQUE (student_id, offering_id)
);

-- Nigerian 5-point grading scale (lookup: highest min_score <= total)
CREATE TABLE grade_scale (
    letter_grade  CHAR(1)      PRIMARY KEY CHECK (letter_grade IN ('A','B','C','D','E','F')),
    min_score     NUMERIC(5,2) NOT NULL UNIQUE CHECK (min_score BETWEEN 0 AND 100),
    grade_point   NUMERIC(2,1) NOT NULL CHECK (grade_point BETWEEN 0 AND 5)
);

CREATE TABLE grade (
    registration_id  BIGINT PRIMARY KEY
                     REFERENCES registration(registration_id) ON DELETE CASCADE,
    ca_score         NUMERIC(5,2) NOT NULL CHECK (ca_score   BETWEEN 0 AND 30),
    exam_score       NUMERIC(5,2) NOT NULL CHECK (exam_score BETWEEN 0 AND 70),
    total_score      NUMERIC(5,2) GENERATED ALWAYS AS (ca_score + exam_score) STORED,
    letter_grade     CHAR(1)      NOT NULL REFERENCES grade_scale(letter_grade),
    grade_point      NUMERIC(2,1) NOT NULL,
    entered_by       INT          NOT NULL REFERENCES lecturer(lecturer_id),
    entered_at       TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE grade_audit (
    audit_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    registration_id  BIGINT      NOT NULL,
    action           VARCHAR(6)  NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
    old_total        NUMERIC(5,2),
    new_total        NUMERIC(5,2),
    changed_by       TEXT        NOT NULL DEFAULT current_user,
    changed_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
