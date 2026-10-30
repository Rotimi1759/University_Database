# Case Study Statement

| Item | Description |
|---|---|
| **Organisation / scenario** | A simulated Nigerian university, **"Example University Student Result Portal"** (a realistic business scenario, not a real institution; all data is synthetic). |
| **Nature of the system** | A central academic records database behind a web portal where students register courses and view results, lecturers upload scores, and the registry produces transcripts. |
| **Users of the database** | Students, lecturers, heads of department, the registry/exams officer, and the portal application (service account). |
| **Major data stored** | Departments, programmes, lecturers, students, academic terms (session + semester), courses, course offerings, course registrations, grades (CA + exam), grade scale, and a grade audit trail. |
| **Key operations supported** | Register courses (with seat, credit-unit and registration-window rules), enter grades (letter grade and grade point computed automatically), compute semester GPA and CGPA, generate a transcript, and audit any grade change. |

## Business rules modelled

1. A student belongs to exactly one programme; a programme belongs to one department.
2. A course is owned by a department. A *course offering* is that course delivered in one term by one responsible lecturer; a course can only be offered once per term.
3. A student registers for course **offerings** (not bare courses); a student cannot register twice for the same offering.
4. Registration is only possible while the term's registration window is open, while seats remain, and within **24 credit units per term**.
5. Scores are CA (0-30) + exam (0-70) = total (0-100). Grade letters and points follow the 5-point scale: A 70+ (5), B 60 (4), C 50 (3), D 45 (2), E 40 (1), F below 40 (0).
6. Only the lecturer responsible for an offering may enter grades for it, and only for active registrations.
7. GPA = sum(grade point x credit units) / sum(credit units). CGPA applies the same formula across all terms.
8. Every insert, update or delete on a grade is written to an audit table.

## Why this case study suits all five portfolios

| Portfolio | How the case study supports it |
|---|---|
| 1 Design | Rich entities, 1:N and M:N relationships (students-offerings), clear constraints. |
| 2 Query optimisation | Result sheets, transcripts, rankings and pass-rate reports scale to hundreds of thousands of rows. |
| 3 Transactions | Seat limits create real races; grade changes need atomicity and auditing. |
| 4 NoSQL | A transcript is a natural read-heavy *document*; course prerequisites are a natural *graph*. |
| 5 Distributed / cloud | Results-release day creates read spikes; data is sensitive personal data needing availability and protection. |
