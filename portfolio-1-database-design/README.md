# Portfolio 1 - Database Design and Modelling

**Case study:** University Student Result Portal (full statement in `docs/01-case-study.md`).

| Deliverable (assignment section 4) | Where |
|---|---|
| Chosen case study description | `docs/01-case-study.md` |
| ER diagram | `docs/02-er-diagram.md` (Mermaid; export a PNG into `screenshots/`) |
| Relational schema, keys, constraints | `docs/03-relational-schema-and-normalisation.md`, `schema/01_schema.sql` |
| Normalisation explanation | `docs/03-relational-schema-and-normalisation.md` (UNF to BCNF) |
| Implementation + business rules | `schema/02_functions_triggers_views.sql` (triggers, GPA and transcript functions, registration procedure) |
| Test evidence | `tests/p1_tests.sql` |

## How to run (PostgreSQL 14+)
```bash
createdb portal
psql -d portal -f schema/01_schema.sql
psql -d portal -f schema/02_functions_triggers_views.sql
psql -d portal -f schema/03_seed_data.sql          # small synthetic data set
psql -d portal -f tests/p1_tests.sql               # expect 10 x PASS (rolled back afterwards)
psql -d portal -c "SELECT * FROM result_portal.fn_transcript(1);"
psql -d portal -c "SELECT result_portal.fn_cgpa(1), result_portal.fn_gpa(1, 1::smallint);"
```

## Try the key operations
```sql
SET search_path TO result_portal;
CALL sp_register_course(1, 33);            -- register student 1 on an offering in the open term
SELECT * FROM v_result_detail WHERE student_id = 1;
SELECT * FROM grade_audit ORDER BY audit_id DESC LIMIT 5;
```
(Offering ids 33-48 belong to the open term in the seed data; check with `SELECT * FROM course_offering o JOIN term t USING (term_id) WHERE t.registration_open;`.)

## Screenshots to take for the LMS write-up
1. ER diagram rendered on GitHub.
2. `\dt result_portal.*` and `\d result_portal.registration`.
3. The PASS table from `tests/p1_tests.sql`.
4. A transcript from `fn_transcript(1)`.
