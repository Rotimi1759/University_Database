-- =====================================================================
-- MIT 8103 | Portfolio 1 | tests/p1_tests.sql
-- Proves that keys, constraints, triggers and procedures reject bad data.
-- Each test expects an error; PASS = the database refused the bad action.
-- Run:  psql -d portal -f tests/p1_tests.sql   (after the three schema scripts)
-- Everything is rolled back, so the data is left untouched.
-- =====================================================================
SET search_path TO result_portal, public;
\set ON_ERROR_STOP off
BEGIN;

CREATE TEMP TABLE test_log(test TEXT, result TEXT) ON COMMIT DROP;

DO $$
DECLARE
    v_student INT := (SELECT student_id FROM student ORDER BY student_id LIMIT 1);
    v_prog    SMALLINT := (SELECT programme_id FROM programme ORDER BY 1 LIMIT 1);
    v_reg     BIGINT   := (SELECT registration_id FROM registration ORDER BY 1 LIMIT 1);
    v_other   INT      := (SELECT lecturer_id FROM lecturer ORDER BY lecturer_id DESC LIMIT 1);
    v_open_o  INT      := (SELECT o.offering_id FROM course_offering o JOIN term t USING (term_id)
                           WHERE t.registration_open ORDER BY 1 LIMIT 1);
    v_closed_o INT     := (SELECT o.offering_id FROM course_offering o JOIN term t USING (term_id)
                           WHERE NOT t.registration_open ORDER BY 1 LIMIT 1);
BEGIN
    -- T1 duplicate matric number (UNIQUE)
    BEGIN
        INSERT INTO student(matric_no, first_name, last_name, email, date_of_birth, programme_id, entry_year)
        SELECT matric_no, 'X','Y','x@y.org','2000-01-01', v_prog, 2024 FROM student WHERE student_id = v_student;
        INSERT INTO test_log VALUES ('T1 duplicate matric_no rejected', 'FAIL');
    EXCEPTION WHEN unique_violation THEN
        INSERT INTO test_log VALUES ('T1 duplicate matric_no rejected', 'PASS');
    END;

    -- T3 foreign key: registration for a non-existent student
    BEGIN
        INSERT INTO registration(student_id, offering_id) VALUES (999999, v_open_o);
        INSERT INTO test_log VALUES ('T3 orphan registration rejected', 'FAIL');
    EXCEPTION WHEN foreign_key_violation THEN
        INSERT INTO test_log VALUES ('T3 orphan registration rejected', 'PASS');
    END;

    -- T4 invalid course code format (CHECK regex)
    BEGIN
        INSERT INTO course(code, title, credit_units, level, department_id) VALUES ('C1','Bad',3,200,1);
        INSERT INTO test_log VALUES ('T4 bad course code rejected', 'FAIL');
    EXCEPTION WHEN check_violation THEN
        INSERT INTO test_log VALUES ('T4 bad course code rejected', 'PASS');
    END;

    -- T5 deleting a department that still has courses (ON DELETE RESTRICT)
    BEGIN
        DELETE FROM department WHERE code = 'CSC';
        INSERT INTO test_log VALUES ('T5 department delete restricted', 'FAIL');
    EXCEPTION WHEN foreign_key_violation THEN
        INSERT INTO test_log VALUES ('T5 department delete restricted', 'PASS');
    END;

    -- T7 registering in a closed term
    BEGIN
        CALL sp_register_course(v_student, v_closed_o);
        INSERT INTO test_log VALUES ('T7 closed-term registration rejected', 'FAIL');
    EXCEPTION WHEN raise_exception THEN
        INSERT INTO test_log VALUES ('T7 closed-term registration rejected', 'PASS');
    END;

    -- T8 happy path registration works, duplicate is refused
    BEGIN
        CALL sp_register_course(v_student, v_open_o);
        INSERT INTO test_log VALUES ('T8a valid registration accepted', 'PASS');
        BEGIN
            CALL sp_register_course(v_student, v_open_o);
            INSERT INTO test_log VALUES ('T8b duplicate registration rejected', 'FAIL');
        EXCEPTION WHEN raise_exception THEN
            INSERT INTO test_log VALUES ('T8b duplicate registration rejected', 'PASS');
        END;
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO test_log VALUES ('T8a valid registration accepted', 'FAIL: ' || SQLERRM);
    END;

    -- T2 CA score above 30 (CHECK constraint; correct lecturer so the trigger passes)
    DECLARE v_new BIGINT; v_lect INT;
    BEGIN
        SELECT r.registration_id, o.lecturer_id INTO v_new, v_lect
          FROM registration r JOIN course_offering o USING (offering_id)
         WHERE r.student_id = v_student AND r.offering_id = v_open_o;
        INSERT INTO grade(registration_id, ca_score, exam_score, entered_by) VALUES (v_new, 31, 50, v_lect);
        INSERT INTO test_log VALUES ('T2 ca_score > 30 rejected', 'FAIL');
    EXCEPTION WHEN check_violation THEN
        INSERT INTO test_log VALUES ('T2 ca_score > 30 rejected', 'PASS');
    END;

    -- T6 grading by a lecturer who does not own the offering (trigger rule)
    DECLARE v_new BIGINT; v_wrong INT;
    BEGIN
        SELECT r.registration_id,
               (SELECT l.lecturer_id FROM lecturer l WHERE l.lecturer_id <> o.lecturer_id LIMIT 1)
          INTO v_new, v_wrong
          FROM registration r JOIN course_offering o USING (offering_id)
         WHERE r.student_id = v_student AND r.offering_id = v_open_o;
        INSERT INTO grade(registration_id, ca_score, exam_score, entered_by) VALUES (v_new, 20, 48, v_wrong);
        INSERT INTO test_log VALUES ('T6 grading by wrong lecturer rejected', 'FAIL');
    EXCEPTION WHEN raise_exception THEN
        INSERT INTO test_log VALUES ('T6 grading by wrong lecturer rejected', 'PASS');
    END;

    -- T9 trigger computes grade letter and point correctly (68 -> B / 4.0)
    DECLARE v_new BIGINT; v_lect INT; v_letter CHAR(1); v_gp NUMERIC;
    BEGIN
        SELECT r.registration_id, o.lecturer_id INTO v_new, v_lect
          FROM registration r JOIN course_offering o USING (offering_id)
         WHERE r.student_id = v_student AND r.offering_id = v_open_o;
        INSERT INTO grade(registration_id, ca_score, exam_score, entered_by) VALUES (v_new, 20, 48, v_lect);
        SELECT letter_grade, grade_point INTO v_letter, v_gp FROM grade WHERE registration_id = v_new;
        INSERT INTO test_log VALUES ('T9 68 marks -> B / 4.0 computed by trigger',
                                     CASE WHEN v_letter = 'B' AND v_gp = 4.0 THEN 'PASS' ELSE 'FAIL' END);
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO test_log VALUES ('T9 68 marks -> B / 4.0 computed by trigger', 'FAIL: ' || SQLERRM);
    END;
END $$;

SELECT * FROM test_log ORDER BY test;
ROLLBACK;
