# Relational Schema, Keys, Constraints and Normalisation

## 1. Relational schema (PK underlined in the notation by `PK`, foreign keys by `FK`)

```
department      (department_id PK, code UK, name UK, faculty)
lecturer        (lecturer_id PK, department_id FK, staff_no UK, first_name, last_name, email UK, rank_title)
programme       (programme_id PK, department_id FK, name, award, duration_years)         UK(department_id, name)
student         (student_id PK, matric_no UK, first_name, last_name, email UK, date_of_birth,
                 programme_id FK, entry_year, status)
term            (term_id PK, session_label, semester, start_date, end_date, registration_open)  UK(session_label, semester)
course          (course_id PK, code UK, title, credit_units, level, department_id FK)
course_offering (offering_id PK, course_id FK, term_id FK, lecturer_id FK, capacity)     UK(course_id, term_id)
registration    (registration_id PK, student_id FK, offering_id FK, registered_at, status) UK(student_id, offering_id)
grade_scale     (letter_grade PK, min_score UK, grade_point)
grade           (registration_id PK/FK, ca_score, exam_score, total_score*, letter_grade FK, grade_point, entered_by FK, entered_at)
grade_audit     (audit_id PK, registration_id, action, old_total, new_total, changed_by, changed_at)
```
`*` generated column = `ca_score + exam_score`.

## 2. Keys and constraints used

| Kind | Examples in `schema/01_schema.sql` |
|---|---|
| Surrogate primary keys | `GENERATED ALWAYS AS IDENTITY` on every main table; `BIGINT` for `registration` and `grade_audit` because they grow fastest. |
| Natural alternate keys | `matric_no`, `staff_no`, `email`, `course.code`, `(course_id, term_id)`, `(student_id, offering_id)` as `UNIQUE`. |
| Foreign keys | `ON DELETE RESTRICT` for academic history (a department with courses cannot be deleted); `ON DELETE CASCADE` only from `registration` to its `grade`. |
| CHECK constraints | score ranges (CA 0-30, exam 0-70), `credit_units 1-6`, course-code pattern `^[A-Z]{3}[0-9]{3}$`, semester in (1,2), session label pattern `YYYY/YYYY`, status lists. |
| NOT NULL / DEFAULT | Mandatory attributes are `NOT NULL`; `status` defaults to `ACTIVE` / `REGISTERED`. |
| Triggers | `grade_compute` (derive letter + point, enforce lecturer ownership); `grade_audit_trg` (audit trail). |

**Design decision - why `registration` is separate from `grade`.** A registration exists from the day a student enrols; a grade only exists after assessment. Keeping them apart avoids NULL score columns and lets "registered but not yet graded" be queried directly (`LEFT JOIN`).

**Design decision - why store `letter_grade` and `grade_point` when they can be derived.** They are derived from the grade scale at *entry time*. If the university later changes the scale, historic results must keep the grade that was awarded. The trigger guarantees they are always consistent with the scores when written. `total_score` is a generated column because it can never legitimately differ from `ca + exam`.

## 3. Normalisation walkthrough

Start from the paper-style **result sheet** a department might keep (unnormalised, UNF):

```
RESULT_SHEET(matric_no, student_name, programme, department, faculty,
             { session, semester, course_code, course_title, credit_units,
               lecturer_name, lecturer_email, ca, exam, total, letter, grade_point } )
```
`{ ... }` is a repeating group: one student has many course results.

### First Normal Form (1NF) - remove repeating groups, atomic values
One row per student-per-course result. Key becomes **(matric_no, session, semester, course_code)**.
Student, course and lecturer data are now repeated on every row (redundancy).

### Second Normal Form (2NF) - remove partial dependencies
Non-key attributes that depend on only *part* of the composite key are moved out:

| Depends on | Attributes | New table |
|---|---|---|
| `matric_no` only | student_name, programme, department, faculty | `student` |
| `course_code` only | course_title, credit_units | `course` |
| `(course_code, session, semester)` | lecturer_name, lecturer_email | `course_offering` |
| whole key | ca, exam, total, letter, grade_point | `registration` + `grade` |

### Third Normal Form (3NF) - remove transitive dependencies
- `student -> programme -> department -> faculty`: programme, department and faculty are stored once in `programme` / `department`, not per student.
- `lecturer_name, lecturer_email` depend on the lecturer, not on the offering: moved to `lecturer`, offering keeps only `lecturer_id`.
- `session` + `semester` + dates describe the term: moved to `term`.
- `letter_grade -> grade_point` (and total -> letter via ranges): the mapping lives in `grade_scale`.

### Boyce-Codd Normal Form (BCNF) check
Every determinant in the final tables is a candidate key: e.g. in `student`, `matric_no`, `email` and `student_id` each determine all other attributes and are all candidate keys; in `course_offering`, `offering_id` and `(course_id, term_id)` are both candidate keys. No table has a non-key determinant, so the design is in **BCNF**.

### Deliberate, documented denormalisation
`grade.letter_grade` and `grade.grade_point` are stored (see decision above). This is a controlled exception: the trigger keeps them correct, and it makes transcript queries faster because no range join to `grade_scale` is needed at read time.

## 4. How to demonstrate it (evidence for the LMS write-up)
1. Run the three schema scripts, then `\dt result_portal.*` and `\d result_portal.registration` - screenshot.
2. Run `tests/p1_tests.sql` - screenshot the PASS table.
3. Run `SELECT * FROM result_portal.fn_transcript(1);` - screenshot a transcript.
