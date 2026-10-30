-- =====================================================================
-- MIT 8103 | Portfolio 1 | University Student Result Portal
-- 03_seed_data.sql : SMALL synthetic data set (no real people)
-- Names, matric numbers and e-mails are invented for demonstration.
-- Run after 02_functions_triggers_views.sql
-- =====================================================================
SET search_path TO result_portal, public;

INSERT INTO grade_scale(letter_grade, min_score, grade_point) VALUES
 ('A',70,5.0),('B',60,4.0),('C',50,3.0),('D',45,2.0),('E',40,1.0),('F',0,0.0);

INSERT INTO department(code, name, faculty) VALUES
 ('CSC','Computer Science','Faculty of Computing'),
 ('MTH','Mathematics','Faculty of Science'),
 ('EEE','Electrical and Electronic Engineering','Faculty of Engineering'),
 ('BUS','Business Administration','Faculty of Management Sciences');

INSERT INTO lecturer(department_id, staff_no, first_name, last_name, email, rank_title)
SELECT d.department_id, v.staff_no, v.fn, v.ln, v.email, v.rk
FROM (VALUES
 ('CSC','STF-0001','Adaeze','Okonkwo','a.okonkwo@uni.example.org','Senior Lecturer'),
 ('CSC','STF-0002','Ibrahim','Musa','i.musa@uni.example.org','Lecturer I'),
 ('MTH','STF-0003','Funmilayo','Adebayo','f.adebayo@uni.example.org','Professor'),
 ('MTH','STF-0004','Chinedu','Eze','c.eze@uni.example.org','Lecturer II'),
 ('EEE','STF-0005','Halima','Bello','h.bello@uni.example.org','Associate Professor'),
 ('EEE','STF-0006','Tunde','Ogunleye','t.ogunleye@uni.example.org','Lecturer I'),
 ('BUS','STF-0007','Ngozi','Nwosu','n.nwosu@uni.example.org','Senior Lecturer'),
 ('BUS','STF-0008','Yusuf','Danjuma','y.danjuma@uni.example.org','Lecturer II')
) AS v(dcode, staff_no, fn, ln, email, rk)
JOIN department d ON d.code = v.dcode;

INSERT INTO programme(department_id, name, award, duration_years)
SELECT d.department_id, 'B.Sc. ' || d.name, 'BSc', 4 FROM department d;

INSERT INTO term(session_label, semester, start_date, end_date, registration_open) VALUES
 ('2025/2026',1,'2025-09-15','2026-01-30',FALSE),
 ('2025/2026',2,'2026-02-09','2026-06-30',FALSE),
 ('2026/2027',1,'2026-09-14','2027-01-29',TRUE);

INSERT INTO course(code, title, credit_units, level, department_id)
SELECT v.code, v.title, v.units, v.lvl, d.department_id
FROM (VALUES
 ('CSC','CSC201','Data Structures and Algorithms',3,200),
 ('CSC','CSC301','Database Management Systems',3,300),
 ('CSC','CSC302','Operating Systems',3,300),
 ('CSC','CSC401','Software Engineering',3,400),
 ('MTH','MTH201','Linear Algebra',3,200),
 ('MTH','MTH202','Real Analysis I',3,200),
 ('MTH','MTH301','Numerical Analysis',3,300),
 ('MTH','MTH302','Probability Theory',2,300),
 ('EEE','EEE201','Circuit Theory',3,200),
 ('EEE','EEE202','Digital Electronics',3,200),
 ('EEE','EEE301','Control Systems',3,300),
 ('EEE','EEE302','Power Systems',3,300),
 ('BUS','BUS201','Principles of Management',3,200),
 ('BUS','BUS202','Financial Accounting',3,200),
 ('BUS','BUS301','Marketing Strategy',2,300),
 ('BUS','BUS302','Operations Management',3,300)
) AS v(dcode, code, title, units, lvl)
JOIN department d ON d.code = v.dcode;

-- every course is offered in every term; lecturer = one of the department's lecturers
INSERT INTO course_offering(course_id, term_id, lecturer_id, capacity)
SELECT c.course_id, t.term_id, l.lecturer_id, 50
FROM course c
CROSS JOIN term t
JOIN LATERAL (
    SELECT lecturer_id FROM lecturer
     WHERE department_id = c.department_id
     ORDER BY lecturer_id
    OFFSET (c.course_id % 2) LIMIT 1
) l ON TRUE;

INSERT INTO student(matric_no, first_name, last_name, email, date_of_birth, programme_id, entry_year)
SELECT v.matric, v.fn, v.ln, v.email, v.dob::date, p.programme_id, v.entry
FROM (VALUES
 ('CSC','CSC/2024/001','Oluwaseun','Adeyemi','seun.adeyemi@student.example.org','2005-03-14',2024),
 ('CSC','CSC/2024/002','Amina','Suleiman','amina.suleiman@student.example.org','2004-11-02',2024),
 ('CSC','CSC/2025/003','Emeka','Obi','emeka.obi@student.example.org','2006-01-23',2025),
 ('MTH','MTH/2024/001','Zainab','Lawal','zainab.lawal@student.example.org','2005-07-30',2024),
 ('MTH','MTH/2025/002','Kelechi','Nnamdi','kelechi.nnamdi@student.example.org','2006-05-19',2025),
 ('EEE','EEE/2024/001','Bamidele','Fashola','bamidele.fashola@student.example.org','2005-09-08',2024),
 ('EEE','EEE/2025/002','Hauwa','Garba','hauwa.garba@student.example.org','2006-02-11',2025),
 ('BUS','BUS/2024/001','Chiamaka','Okafor','chiamaka.okafor@student.example.org','2005-12-27',2024),
 ('BUS','BUS/2024/002','Musa','Abdullahi','musa.abdullahi@student.example.org','2004-08-16',2024),
 ('BUS','BUS/2025/003','Temitope','Balogun','temitope.balogun@student.example.org','2006-04-05',2025)
) AS v(dcode, matric, fn, ln, email, dob, entry)
JOIN programme p ON p.department_id = (SELECT department_id FROM department WHERE code = v.dcode);

-- students take all courses of their own department in the two CLOSED terms
INSERT INTO registration(student_id, offering_id)
SELECT s.student_id, o.offering_id
FROM student s
JOIN programme p       ON p.programme_id = s.programme_id
JOIN course c          ON c.department_id = p.department_id
JOIN course_offering o ON o.course_id = c.course_id
JOIN term t            ON t.term_id = o.term_id
WHERE t.registration_open = FALSE;

-- deterministic synthetic scores (CA out of 30, exam out of 70); some fail on purpose
INSERT INTO grade(registration_id, ca_score, exam_score, entered_by)
SELECT r.registration_id,
       10 + ((r.student_id * 7  + r.offering_id * 3) % 21),
       15 + ((r.student_id * 13 + r.offering_id * 5) % 56),
       o.lecturer_id
FROM registration r
JOIN course_offering o ON o.offering_id = r.offering_id;

-- the open term (2026/2027 S1) is left empty so registration can be demonstrated
