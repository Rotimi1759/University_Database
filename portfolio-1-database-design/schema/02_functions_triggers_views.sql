-- =====================================================================
-- MIT 8103 | Portfolio 1 | University Student Result Portal
-- 02_functions_triggers_views.sql : business rules in the database
--   * grade trigger  : computes letter grade + grade point, checks ownership
--   * audit trigger  : every grade change is logged
--   * v_result_detail: one row per graded course result
--   * fn_gpa / fn_cgpa / fn_transcript : GPA and transcript generation
--   * sp_register_course : safe course registration (used again in P3)
-- Run after 01_schema.sql
-- Every function pins its own search_path so it works no matter which schema the
-- calling session uses (triggers fire inside other sessions' contexts).
-- =====================================================================
SET search_path TO result_portal, public;

-- ---------------------------------------------------------------------
-- 1. Grade computation + integrity trigger
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_grade_compute() RETURNS trigger
LANGUAGE plpgsql SET search_path = result_portal, public AS $$
DECLARE
    v_total   NUMERIC(5,2);
    v_letter  CHAR(1);
    v_gp      NUMERIC(2,1);
    v_lect    INT;
    v_status  TEXT;
BEGIN
    v_total := NEW.ca_score + NEW.exam_score;

    SELECT gs.letter_grade, gs.grade_point
      INTO v_letter, v_gp
      FROM grade_scale gs
     WHERE gs.min_score <= v_total
     ORDER BY gs.min_score DESC
     LIMIT 1;

    NEW.letter_grade := v_letter;
    NEW.grade_point  := v_gp;

    -- Only the lecturer responsible for the offering may enter its grades,
    -- and only for registrations that are still active.
    SELECT o.lecturer_id, r.status
      INTO v_lect, v_status
      FROM registration r
      JOIN course_offering o ON o.offering_id = r.offering_id
     WHERE r.registration_id = NEW.registration_id;

    IF v_status IS DISTINCT FROM 'REGISTERED' THEN
        RAISE EXCEPTION 'Cannot grade registration % (status = %)',
                        NEW.registration_id, COALESCE(v_status, 'missing');
    END IF;
    IF NEW.entered_by <> v_lect THEN
        RAISE EXCEPTION 'Lecturer % is not the lecturer of the offering for registration %',
                        NEW.entered_by, NEW.registration_id;
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS grade_compute ON grade;
CREATE TRIGGER grade_compute
    BEFORE INSERT OR UPDATE OF ca_score, exam_score ON grade
    FOR EACH ROW EXECUTE FUNCTION trg_grade_compute();

-- ---------------------------------------------------------------------
-- 2. Audit trigger
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_grade_audit() RETURNS trigger
LANGUAGE plpgsql SET search_path = result_portal, public AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO grade_audit(registration_id, action, new_total)
        VALUES (NEW.registration_id, 'INSERT', NEW.total_score);
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO grade_audit(registration_id, action, old_total, new_total)
        VALUES (NEW.registration_id, 'UPDATE', OLD.total_score, NEW.total_score);
    ELSE
        INSERT INTO grade_audit(registration_id, action, old_total)
        VALUES (OLD.registration_id, 'DELETE', OLD.total_score);
    END IF;
    RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS grade_audit_trg ON grade;
CREATE TRIGGER grade_audit_trg
    AFTER INSERT OR UPDATE OR DELETE ON grade
    FOR EACH ROW EXECUTE FUNCTION trg_grade_audit();

-- ---------------------------------------------------------------------
-- 3. Reporting view: one row per graded result
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_result_detail AS
SELECT s.student_id,
       s.matric_no,
       s.first_name || ' ' || s.last_name AS student_name,
       t.term_id,
       t.session_label,
       t.semester,
       t.start_date,
       c.code            AS course_code,
       c.title           AS course_title,
       c.credit_units,
       g.ca_score,
       g.exam_score,
       g.total_score,
       g.letter_grade,
       g.grade_point
  FROM grade g
  JOIN registration    r ON r.registration_id = g.registration_id
  JOIN student         s ON s.student_id      = r.student_id
  JOIN course_offering o ON o.offering_id     = r.offering_id
  JOIN course          c ON c.course_id       = o.course_id
  JOIN term            t ON t.term_id         = o.term_id
 WHERE r.status = 'REGISTERED';

-- ---------------------------------------------------------------------
-- 4. GPA functions  (GPA = sum(grade_point * units) / sum(units))
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_gpa(p_student INT, p_term SMALLINT DEFAULT NULL)
RETURNS NUMERIC LANGUAGE sql STABLE SET search_path = result_portal, public AS $$
    SELECT ROUND(SUM(v.grade_point * v.credit_units) / NULLIF(SUM(v.credit_units), 0), 2)
      FROM v_result_detail v
     WHERE v.student_id = p_student
       AND (p_term IS NULL OR v.term_id = p_term);
$$;

CREATE OR REPLACE FUNCTION fn_cgpa(p_student INT)
RETURNS NUMERIC LANGUAGE sql STABLE SET search_path = result_portal, public AS $$
    SELECT fn_gpa(p_student, NULL);
$$;

-- ---------------------------------------------------------------------
-- 5. Transcript: per-course rows with semester GPA and running CGPA
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_transcript(p_student INT)
RETURNS TABLE (
    session_label TEXT, semester SMALLINT, course_code TEXT, course_title TEXT,
    credit_units SMALLINT, total_score NUMERIC, letter_grade CHAR(1),
    grade_point NUMERIC, semester_gpa NUMERIC, cgpa NUMERIC
) LANGUAGE sql STABLE SET search_path = result_portal, public AS $$
    SELECT d.session_label::TEXT, d.semester, d.course_code::TEXT, d.course_title::TEXT,
           d.credit_units, d.total_score, d.letter_grade, d.grade_point,
           ROUND(SUM(d.grade_point * d.credit_units) OVER w_term
                 / SUM(d.credit_units) OVER w_term, 2),
           ROUND(SUM(d.grade_point * d.credit_units) OVER w_cum
                 / SUM(d.credit_units) OVER w_cum, 2)
      FROM v_result_detail d
     WHERE d.student_id = p_student
    WINDOW w_term AS (PARTITION BY d.term_id),
           w_cum  AS (ORDER BY d.start_date
                      RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
     ORDER BY d.start_date, d.course_code;
$$;

-- ---------------------------------------------------------------------
-- 6. Course registration procedure
--    Rules: active student, registration window open, no duplicate,
--           seat available, max 24 credit units per term.
--    The offering row is locked (FOR UPDATE) so two students cannot take
--    the last seat at the same time (demonstrated in Portfolio 3).
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_register_course(p_student INT, p_offering INT)
LANGUAGE plpgsql SET search_path = result_portal, public AS $$
DECLARE
    v_status     TEXT;
    v_capacity   INT;
    v_term       SMALLINT;
    v_open       BOOLEAN;
    v_new_units  INT;
    v_taken      INT;
    v_units_now  INT;
    v_reg_id     BIGINT;
    v_reg_status TEXT;
BEGIN
    SELECT s.status INTO v_status FROM student s WHERE s.student_id = p_student;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Student % does not exist', p_student;
    END IF;
    IF v_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'Student % is not ACTIVE (status = %)', p_student, v_status;
    END IF;

    SELECT o.capacity, o.term_id, t.registration_open, c.credit_units
      INTO v_capacity, v_term, v_open, v_new_units
      FROM course_offering o
      JOIN term   t ON t.term_id   = o.term_id
      JOIN course c ON c.course_id = o.course_id
     WHERE o.offering_id = p_offering
       FOR UPDATE OF o;                       -- serialise registrations per offering
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Offering % does not exist', p_offering;
    END IF;
    IF NOT v_open THEN
        RAISE EXCEPTION 'Registration is closed for this term';
    END IF;

    SELECT r.registration_id, r.status INTO v_reg_id, v_reg_status
      FROM registration r
     WHERE r.student_id = p_student AND r.offering_id = p_offering;
    IF v_reg_status = 'REGISTERED' THEN
        RAISE EXCEPTION 'Student % is already registered for offering %', p_student, p_offering;
    END IF;

    SELECT COUNT(*) INTO v_taken
      FROM registration r
     WHERE r.offering_id = p_offering AND r.status = 'REGISTERED';
    IF v_taken >= v_capacity THEN
        RAISE EXCEPTION 'Offering % is full (% of % seats)', p_offering, v_taken, v_capacity;
    END IF;

    SELECT COALESCE(SUM(c.credit_units), 0) INTO v_units_now
      FROM registration r
      JOIN course_offering o ON o.offering_id = r.offering_id
      JOIN course c          ON c.course_id   = o.course_id
     WHERE r.student_id = p_student AND o.term_id = v_term AND r.status = 'REGISTERED';
    IF v_units_now + v_new_units > 24 THEN
        RAISE EXCEPTION 'Credit-unit limit exceeded: % already + % new > 24', v_units_now, v_new_units;
    END IF;

    IF v_reg_id IS NULL THEN
        INSERT INTO registration(student_id, offering_id) VALUES (p_student, p_offering);
    ELSE                                       -- re-register after a drop
        UPDATE registration SET status = 'REGISTERED', registered_at = now()
         WHERE registration_id = v_reg_id;
    END IF;
END $$;
