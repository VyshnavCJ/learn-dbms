-- PostgreSQL seed dataset: approximately 8 million rows; run once.
-- Run with: psql -U postgres -f create_database.sql
CREATE DATABASE learning_db;

\connect learning_db

CREATE SCHEMA school;

CREATE TABLE school.departments (
    department_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    department_name TEXT NOT NULL UNIQUE
);

CREATE TABLE school.instructors (
    instructor_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    department_id BIGINT NOT NULL REFERENCES school.departments (department_id),
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    hired_on DATE NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE school.students (
    student_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    phone_number TEXT,
    city TEXT NOT NULL,
    country_code CHAR(2) NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('active', 'inactive', 'suspended')),
    enrolled_at DATE NOT NULL DEFAULT CURRENT_DATE
);

CREATE TABLE school.courses (
    course_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    department_id BIGINT NOT NULL REFERENCES school.departments (department_id),
    instructor_id BIGINT NOT NULL REFERENCES school.instructors (instructor_id),
    course_name TEXT NOT NULL,
    course_code TEXT NOT NULL UNIQUE,
    credits SMALLINT NOT NULL CHECK (credits > 0),
    course_level TEXT NOT NULL CHECK (course_level IN ('beginner', 'intermediate', 'advanced')),
    published_on DATE NOT NULL,
    is_active BOOLEAN NOT NULL
);

CREATE TABLE school.course_prerequisites (
    course_id BIGINT NOT NULL REFERENCES school.courses (course_id) ON DELETE CASCADE,
    prerequisite_course_id BIGINT NOT NULL REFERENCES school.courses (course_id),
    PRIMARY KEY (course_id, prerequisite_course_id),
    CHECK (course_id <> prerequisite_course_id)
);

CREATE TABLE school.enrollments (
    student_id BIGINT NOT NULL REFERENCES school.students (student_id) ON DELETE CASCADE,
    course_id BIGINT NOT NULL REFERENCES school.courses (course_id) ON DELETE CASCADE,
    enrolled_at DATE NOT NULL DEFAULT CURRENT_DATE,
    grade NUMERIC(5, 2) CHECK (grade BETWEEN 0 AND 100),
    PRIMARY KEY (student_id, course_id)
);

-- Generate deterministic data for joins, filters, NULL handling, and aggregation.
INSERT INTO school.departments (department_name)
SELECT 'Department ' || n
FROM generate_series(1, 100) AS series(n);

INSERT INTO school.instructors
    (department_id, first_name, last_name, email, hired_on, is_active)
SELECT
    ((n - 1) % 100) + 1,
    'Instructor' || n,
    'Family' || (n % 500),
    'instructor' || n || '@example.test',
    DATE '2000-01-01' + (n % 9000)::integer,
    n % 10 <> 0
FROM generate_series(1, 10000) AS series(n);

-- One million students and one million courses; five million enrollments follow.
INSERT INTO school.students
    (first_name, last_name, email, phone_number, city, country_code, status, enrolled_at)
SELECT
    'Student' || n,
    'Family' || (n % 1000),
    'student' || n || '@example.test',
    CASE WHEN n % 5 = 0 THEN NULL ELSE '+1-555-' || lpad(n::text, 7, '0') END,
    'City ' || (n % 250),
    CASE n % 5
        WHEN 0 THEN 'US'
        WHEN 1 THEN 'CA'
        WHEN 2 THEN 'GB'
        WHEN 3 THEN 'IN'
        ELSE 'AU'
    END,
    CASE WHEN n % 20 = 0 THEN 'inactive'
         WHEN n % 17 = 0 THEN 'suspended'
         ELSE 'active'
    END,
    DATE '2020-01-01' + (n % 2000)::integer
FROM generate_series(1, 1000000) AS series(n);

INSERT INTO school.courses
    (department_id, instructor_id, course_name, course_code, credits,
     course_level, published_on, is_active)
SELECT
    ((n - 1) % 100) + 1,
    ((n - 1) % 10000) + 1,
    'Course ' || n,
    'C' || lpad(n::text, 7, '0'),
    (1 + n % 6)::smallint,
    CASE n % 3
        WHEN 0 THEN 'beginner'
        WHEN 1 THEN 'intermediate'
        ELSE 'advanced'
    END,
    DATE '2015-01-01' + (n % 4000)::integer,
    n % 8 <> 0
FROM generate_series(1, 1000000) AS series(n);

-- A prerequisite chain in groups of 1,000 supports recursive CTE practice.
INSERT INTO school.course_prerequisites (course_id, prerequisite_course_id)
SELECT n, n - 1000
FROM generate_series(1001, 1000000) AS series(n);

-- Give each student five distinct courses, for 5 million enrollment rows.
INSERT INTO school.enrollments (student_id, course_id, enrolled_at, grade)
SELECT
    ((n - 1) % 1000000) + 1,
    (((n - 1) * 7919 + ((n - 1) / 1000000) * 104729) % 1000000) + 1,
    DATE '2020-01-01' + (n % 2000)::integer,
    CASE WHEN n % 7 = 0 THEN NULL ELSE ((n * 37) % 101)::numeric(5, 2) END
FROM generate_series(1, 5000000) AS series(n);

CREATE INDEX instructors_department_id_idx ON school.instructors (department_id);
CREATE INDEX courses_department_id_idx ON school.courses (department_id);
CREATE INDEX courses_instructor_id_idx ON school.courses (instructor_id);
CREATE INDEX enrollments_course_id_idx ON school.enrollments (course_id);
