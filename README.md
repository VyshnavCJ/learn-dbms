# learn-dbms

Understanding DBMS in depth with PostgreSQL examples.

## Introduction to SQL

SQL (Structured Query Language) is used to define database objects and query
or modify data. PostgreSQL, MySQL, SQLite, SQL Server, and Oracle all support
SQL, but each has dialect-specific features and syntax. This repository uses
PostgreSQL.

A typical query follows this clause order:

```sql
SELECT student_id, first_name
FROM school.students
WHERE status = 'active'
ORDER BY first_name
LIMIT 10;
```

End statements with a semicolon. Use single quotes for text values, and use
`--` for a one-line comment. In a `SELECT`, the usual order is `SELECT`,
`FROM`, `WHERE`, `GROUP BY`, `HAVING`, `ORDER BY`, then a row limit.

## Set up the sample database

The [`create_database.sql`](create_database.sql) script creates the `learning_db`
database, the `school` schema, six related tables, sample data, and indexes.
It generates about 8 million rows, so the initial load can take a while. Run it
once from a PostgreSQL client:

```sh
psql -U postgres -f create_database.sql
```

Connect to the database for the examples below:

```sh
psql -U postgres -d learning_db
```

## Database, schema, and table

A **database** is the overall container for data and database objects. In
PostgreSQL, a **schema** is a named grouping of objects—such as tables, views,
and functions—inside a database. A **table** stores rows and columns. In this
project, `learning_db` is the database, `school` is the schema, and
`school.students` is a table. Schemas help organize objects and allow the same
table name to exist in different schemas.

## Database design: normalization

**Normalization** organizes related data into tables and connects them with
keys. Its goal is to reduce repeated data and avoid anomalies—for example,
having to update the same department name in many course rows. The sample
schema separates `departments`, `instructors`, `courses`, `students`, and
`enrollments`, then uses primary and foreign keys to connect them.

Common normal forms build on one another:

- **First normal form (1NF):** each column holds a single value per row, and
  rows can be uniquely identified.
- **Second normal form (2NF):** non-key columns depend on the whole key, not
  just part of a composite key.
- **Third normal form (3NF):** non-key columns depend on the key, not on other
  non-key columns.

Normalization is especially useful for transactional systems. Analytics
systems may intentionally store some repeated descriptive data to make
reporting simpler or faster.

## OLTP, OLAP, fact tables, and dimension tables

Yes—**OLTP** and **OLAP** are the correct terms:

- **OLTP (Online Transaction Processing)** handles everyday operations such
  as enrolling a student, changing a course, or recording a grade. It usually
  uses normalized tables, many small reads and writes, and constraints to keep
  data consistent. The `school` schema is an OLTP-style design.
- **OLAP (Online Analytical Processing)** supports analysis over many rows,
  such as comparing enrollment counts by course, department, or year. It
  commonly uses a dimensional model with fact and dimension tables.

A **fact table** records business events at a defined level of detail (the
table's *grain*) and stores measurable values. A **dimension table** describes
the entities or categories used to filter and group those facts.

For a school analytics model, one possible design is:

| Table | Role | Example contents |
| --- | --- | --- |
| `fact_enrollments` | Fact | One row per student-course enrollment; keys to dimensions and a measure such as grade (counts can be calculated from rows) |
| `dim_student` | Dimension | Student name, city, and country |
| `dim_course` | Dimension | Course name, level, department, and instructor |
| `dim_date` | Dimension | Calendar date, month, term, and year |

The fact table's grain matters: if it is one row per enrollment, the student,
course, and date keys identify what each grade or enrollment measure refers
to. Dimensions provide the descriptive context for questions such as
"How many enrollments were there per department and year?" The existing
`school.enrollments` table is a normalized transactional table; it can provide
source data for an analytical fact table, but it is not itself a full star
schema.

## What are SQL data types?

A data type defines what kind of value a column can store, such as text, a
number, or a date. It helps PostgreSQL validate values and choose how to store
and process them. The sample schema uses types such as:

| Type | Stores | Example from this database |
| --- | --- | --- |
| `BIGINT`, `SMALLINT` | Whole numbers | Student IDs, course credits |
| `NUMERIC(5, 2)` | Exact decimal numbers | Enrollment grades |
| `TEXT`, `CHAR(2)` | Text of any length, or fixed-length text | Names, two-letter country codes |
| `DATE`, `TIMESTAMPTZ` | Date, or date and time with time zone | Enrollment dates, update timestamps |
| `BOOLEAN` | `TRUE` or `FALSE` | Whether a course is active |

For example, `grade NUMERIC(5, 2)` allows up to five digits in total, two
after the decimal point. PostgreSQL also has complex types such as arrays,
JSONB, composite, and range types; see [complex data types](#postgresql-complex-data-types).

## DDL: define database objects

DDL (Data Definition Language) creates or changes database structure. The
setup script contains `CREATE DATABASE`, `CREATE SCHEMA`, and `CREATE TABLE`
statements. For example, the student table defines columns, defaults,
constraints, and an identity primary key:

```sql
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
```

### Changing a table with ALTER TABLE

`ALTER TABLE` changes a table's structure. The following column changes are
shown in order: add a column, rename it, change its type and default, and
eventually drop it. The backfill example below fills the column before making
it `NOT NULL`.

```sql
ALTER TABLE school.students
ADD COLUMN preferred_name TEXT;

ALTER TABLE school.students
RENAME COLUMN preferred_name TO display_name;

ALTER TABLE school.students
ALTER COLUMN display_name TYPE VARCHAR(80)
USING display_name::VARCHAR(80);

ALTER TABLE school.students
ALTER COLUMN display_name SET DEFAULT 'Unknown';

ALTER TABLE school.students
ALTER COLUMN display_name DROP DEFAULT;
```

Changing a default affects future inserts, not existing rows. To make a
column `NOT NULL`, first make sure no existing row contains `NULL`; otherwise
PostgreSQL rejects the change:

```sql
UPDATE school.students
SET display_name = first_name
WHERE display_name IS NULL;

ALTER TABLE school.students
ALTER COLUMN display_name SET NOT NULL;

-- Allow NULL values again
ALTER TABLE school.students
ALTER COLUMN display_name DROP NOT NULL;
```

`UPDATE` changes values in existing rows; `ALTER TABLE` changes the table's
structure. The backfill above changes every row where `display_name` is
missing, so large-table updates may take time.

Constraints can also be added and removed. This check prevents blank city
names; PostgreSQL checks existing rows when the constraint is added:

```sql
ALTER TABLE school.students
ADD CONSTRAINT students_city_not_blank
CHECK (btrim(city) <> '');

ALTER TABLE school.students
DROP CONSTRAINT students_city_not_blank;
```

To remove a column or table, use `DROP`; this also removes its data, so use it
carefully:

```sql
ALTER TABLE school.students DROP COLUMN display_name;
CREATE TABLE school.example_table (id BIGINT PRIMARY KEY, label TEXT);
DROP TABLE school.example_table;
```

## Foreign keys and cascading behavior

A foreign key links a child table to a referenced (parent) table. In this
database, `school.enrollments.student_id` references `school.students`.
`ON DELETE` and `ON UPDATE` specify what happens to matching child rows when
the referenced parent row or key is deleted or changed:

| Action | Behavior |
| --- | --- |
| `CASCADE` | Delete child rows when the parent is deleted; propagate a changed key on update. |
| `RESTRICT` | Reject the delete or key update when child rows refer to the parent. |
| `NO ACTION` | The default; reject the operation if references remain when the constraint is checked. |
| `SET NULL` | Set the child foreign-key value to `NULL`; that column must allow `NULL`. |
| `SET DEFAULT` | Set the child foreign-key value to its default, which must still satisfy the foreign key. |

The setup script uses `ON DELETE CASCADE` for student/course enrollments, so
deleting a student or course also deletes its enrollment rows. It also
cascades when a course is deleted from the `course_id` side of
`course_prerequisites`. Other foreign keys use PostgreSQL's default `NO
ACTION`, so for example a course cannot be deleted while another course still
references it as a prerequisite.

You can inspect the cascade in a transaction and roll it back to keep the
seed data unchanged:

```sql
BEGIN;

SELECT COUNT(*)
FROM school.enrollments
WHERE student_id = 1;

DELETE FROM school.students
WHERE student_id = 1;

-- The matching enrollment rows were deleted by the foreign key action.
SELECT COUNT(*)
FROM school.enrollments
WHERE student_id = 1;

ROLLBACK;
```

Cascade actions are useful when child rows have no meaning without their
parent, but can remove many rows at once. Choose them deliberately; a
transaction can roll back a test before it is committed.

## DML: insert, update, delete, and read rows

DML (Data Manipulation Language) works with table data. The seed script uses
`INSERT ... SELECT` with PostgreSQL's `generate_series` to create sample rows.
A basic insert looks like this:

```sql
INSERT INTO school.departments (department_name)
VALUES ('Computer Science');
```

Update a row and inspect the changed value with a `SELECT` immediately after.
The sample data has a student with `student_id = 1`:

```sql
UPDATE school.students
SET city = 'Vancouver'
WHERE student_id = 1;

SELECT student_id, first_name, last_name, city
FROM school.students
WHERE student_id = 1;
```

`UPDATE` without a `WHERE` clause changes every row in the table. To delete a
specific row:

```sql
DELETE FROM school.students
WHERE student_id = 1;
```

Deleting a student also deletes their enrollments because the foreign key is
defined with `ON DELETE CASCADE`.

`TRUNCATE` removes every row from a table without scanning each row, and
cannot filter with `WHERE`. Use it carefully; this empties the enrollments
table:

```sql
TRUNCATE TABLE school.enrollments;
```

Some PostgreSQL statements can return changed rows directly:

```sql
UPDATE school.students
SET status = 'inactive'
WHERE student_id = 1
RETURNING student_id, status;
```

## SELECT: filter, join, and aggregate

```sql
-- Filter and sort
SELECT student_id, first_name, last_name, city
FROM school.students
WHERE status = 'active' AND country_code = 'US'
ORDER BY last_name, first_name
LIMIT 20;

-- Join students to the courses they are taking
SELECT s.student_id, s.first_name, s.last_name, c.course_name, e.grade
FROM school.enrollments AS e
JOIN school.students AS s ON s.student_id = e.student_id
JOIN school.courses AS c ON c.course_id = e.course_id
WHERE s.student_id = 1;

-- Aggregate: number of enrollments per course
SELECT c.course_id, c.course_name, COUNT(*) AS enrollment_count
FROM school.courses AS c
JOIN school.enrollments AS e ON e.course_id = c.course_id
GROUP BY c.course_id, c.course_name
ORDER BY enrollment_count DESC
LIMIT 10;
```

### DISTINCT, LIMIT, and FETCH

`DISTINCT` removes duplicate result rows. `LIMIT` caps how many rows are
returned. PostgreSQL also supports the SQL-standard `OFFSET` and `FETCH`
syntax: `OFFSET` skips rows, while `FETCH` specifies how many rows to return.
Use `ORDER BY` so pagination has a predictable order.

```sql
SELECT DISTINCT country_code
FROM school.students
ORDER BY country_code;

-- Return rows 11 through 20 in a stable order
SELECT student_id, first_name
FROM school.students
ORDER BY student_id
OFFSET 10 ROWS FETCH NEXT 10 ROWS ONLY;
```

### Filtering rows

`WHERE` filters individual rows. Combine conditions with `AND`, `OR`, and
`NOT`; use `BETWEEN` for an inclusive range, `IN` for a list of values, and
`LIKE` for a text pattern (`%` matches any number of characters and `_`
matches one character):

```sql
SELECT course_id, course_name, credits
FROM school.courses
WHERE credits BETWEEN 3 AND 5
  AND course_level IN ('beginner', 'advanced')
  AND NOT is_active
  AND course_name LIKE 'Course 1%';
```

Use `IS NULL` / `IS NOT NULL` rather than `= NULL`; see
[NULL handling](#nullif-coalesce-and-case). PostgreSQL's `ILIKE` is a
case-insensitive alternative to `LIKE`.

### LEFT and RIGHT joins

`LEFT JOIN` preserves every row from its left input; `RIGHT JOIN` preserves
every row from its right input. Unmatched columns from the other side are
filled with `NULL`. A `RIGHT JOIN` can usually be rewritten as a `LEFT JOIN`
by swapping the table order.

```sql
-- Keep the student even if they have no matching enrollment
SELECT s.student_id, e.course_id
FROM school.students AS s
LEFT JOIN school.enrollments AS e ON e.student_id = s.student_id
WHERE s.student_id = 1;

-- Keep every course, even if its department has no matching row
SELECT c.course_name, d.department_name
FROM school.departments AS d
RIGHT JOIN school.courses AS c ON c.department_id = d.department_id;
```

### GROUP BY, HAVING, and aggregate functions

`GROUP BY` forms groups for aggregates. `HAVING` filters those groups after
aggregation, while `WHERE` filters rows before grouping. Common aggregates
include `COUNT`, `AVG`, `SUM`, `MIN`, and `MAX`. `COUNT(grade)` ignores NULL
grades; `COUNT(*)` counts every enrollment row.

```sql
SELECT course_id,
       COUNT(*) AS enrollment_count,
       COUNT(grade) AS graded_count,
       AVG(grade) AS average_grade,
       SUM(grade) AS total_grade,
       MIN(grade) AS lowest_grade,
       MAX(grade) AS highest_grade
FROM school.enrollments
GROUP BY course_id
HAVING COUNT(*) >= 2
ORDER BY average_grade DESC NULLS LAST
LIMIT 10;
```

`GROUPING SETS`, `ROLLUP`, and `CUBE` compute multiple aggregation levels in
one query. `ROLLUP` produces subtotals following the column order; `CUBE`
produces all combinations of the specified groupings:

```sql
-- Detail by department and level, department subtotals, and grand total
SELECT department_id, course_level, COUNT(*) AS course_count,
       GROUPING(department_id) AS is_department_total,
       GROUPING(course_level) AS is_level_total
FROM school.courses
GROUP BY GROUPING SETS (
    (department_id, course_level),
    (department_id),
    ()
);

-- Hierarchical subtotals
SELECT department_id, course_level, COUNT(*) AS course_count
FROM school.courses
GROUP BY ROLLUP (department_id, course_level);

-- Every combination of department and course level
SELECT department_id, course_level, COUNT(*) AS course_count
FROM school.courses
GROUP BY CUBE (department_id, course_level);
```

## More query patterns

### Common Table Expressions (CTEs)

A CTE is a named result set available to one statement. It can make a
multi-step query easier to read:

```sql
WITH course_counts AS (
    SELECT course_id, COUNT(*) AS enrollment_count
    FROM school.enrollments
    GROUP BY course_id
)
SELECT c.course_name, cc.enrollment_count
FROM course_counts AS cc
JOIN school.courses AS c ON c.course_id = cc.course_id
ORDER BY cc.enrollment_count DESC
LIMIT 10;
```

### Recursive queries

A recursive CTE repeatedly runs its query using the previous result. It is
useful for hierarchies and graphs. This follows the sample course-prerequisite
chain from course `3001` toward its earliest prerequisite:

```sql
WITH RECURSIVE prerequisite_chain AS (
    SELECT course_id, prerequisite_course_id, 1 AS depth
    FROM school.course_prerequisites
    WHERE course_id = 3001

    UNION ALL

    SELECT cp.course_id, cp.prerequisite_course_id, pc.depth + 1
    FROM prerequisite_chain AS pc
    JOIN school.course_prerequisites AS cp
      ON cp.course_id = pc.prerequisite_course_id
)
SELECT depth, prerequisite_course_id
FROM prerequisite_chain
ORDER BY depth;
```

Recursive queries need a stopping condition; guard against cycles when the
underlying relationships can contain them.

### Set operations

Set operations combine compatible `SELECT` results: each query must return
the same number of columns with compatible types. `UNION` removes duplicates,
while `UNION ALL` keeps them. `INTERSECT` returns rows present in both results;
`EXCEPT` returns rows from the first result that are absent from the second.
Some databases call `EXCEPT` `MINUS`; PostgreSQL uses `EXCEPT`.

```sql
-- Students who are active or suspended (remove duplicates)
SELECT student_id FROM school.students WHERE status = 'active'
UNION
SELECT student_id FROM school.students WHERE status = 'suspended';

-- Active students who are in the US
SELECT student_id FROM school.students WHERE status = 'active'
INTERSECT
SELECT student_id FROM school.students WHERE country_code = 'US';

-- US students who are not suspended
SELECT student_id FROM school.students WHERE country_code = 'US'
EXCEPT
SELECT student_id FROM school.students WHERE status = 'suspended';
```

### Pivoting and unpivoting

PostgreSQL does not have built-in `PIVOT` and `UNPIVOT` keywords. Conditional
aggregation pivots row values into columns; `LATERAL ... VALUES` can turn
those columns back into rows:

```sql
-- Pivot: one row per country, with status counts as columns
SELECT country_code,
       COUNT(*) FILTER (WHERE status = 'active') AS active_count,
       COUNT(*) FILTER (WHERE status = 'inactive') AS inactive_count
FROM school.students
GROUP BY country_code;

-- Unpivot those counts back into (country, status, count) rows
WITH status_counts AS (
    SELECT country_code,
           COUNT(*) FILTER (WHERE status = 'active') AS active_count,
           COUNT(*) FILTER (WHERE status = 'inactive') AS inactive_count
    FROM school.students
    GROUP BY country_code
)
SELECT country_code, status, student_count
FROM status_counts
CROSS JOIN LATERAL (
    VALUES ('active', active_count), ('inactive', inactive_count)
) AS counts(status, student_count);
```

### Advanced joins

`FULL OUTER JOIN` keeps unmatched rows from both sides, `CROSS JOIN` produces
every combination of rows, and a `SELF JOIN` joins a table to itself (usually
with different aliases).

```sql
-- Keep departments even if they have no courses, and courses even if
-- their department is missing
SELECT d.department_name, c.course_name
FROM school.departments AS d
FULL OUTER JOIN school.courses AS c
  ON c.department_id = d.department_id;

-- Pair every department with both labels
SELECT d.department_name, labels.level
FROM school.departments AS d
CROSS JOIN (VALUES ('beginner'), ('advanced')) AS labels(level)
LIMIT 10;

-- A self join: show each course beside its prerequisite
SELECT c.course_name, prerequisite.course_name AS prerequisite_name
FROM school.course_prerequisites AS cp
JOIN school.courses AS c ON c.course_id = cp.course_id
JOIN school.courses AS prerequisite
  ON prerequisite.course_id = cp.prerequisite_course_id;
```

### Subqueries: correlated and non-correlated

A non-correlated subquery can run independently of the outer query. A
correlated subquery refers to a value from the current outer row:

```sql
-- Non-correlated: compare each grade with the overall average
SELECT student_id, course_id, grade
FROM school.enrollments
WHERE grade > (SELECT AVG(grade) FROM school.enrollments);

-- Correlated: count enrollments for each course
SELECT c.course_id, c.course_name,
       (SELECT COUNT(*)
        FROM school.enrollments AS e
        WHERE e.course_id = c.course_id) AS enrollment_count
FROM school.courses AS c
LIMIT 10;
```

Subqueries can appear in `SELECT`, `FROM`, or `WHERE`; a CTE is often a
readable alternative for a complex `FROM` subquery.

`ALL` and `ANY` compare a value with every value or at least one value from a
subquery. `SOME` is another spelling of `ANY`:

```sql
-- Credits must be at least as high as every course in department 1
SELECT course_id, credits
FROM school.courses
WHERE credits >= ALL (
    SELECT credits
    FROM school.courses
    WHERE department_id = 1
);

-- Credits must match at least one course in department 1
SELECT course_id, credits
FROM school.courses
WHERE credits = ANY (
    SELECT credits
    FROM school.courses
    WHERE department_id = 1
);
```

### EXISTS, IN, or JOIN?

Use `EXISTS` or `IN` to filter rows by whether a related value exists. Use a
`JOIN` when you also need columns from the matching table. A join can return
multiple copies of an outer row when it has multiple matches; `EXISTS` does
not multiply rows.

```sql
-- EXISTS: students with at least one enrollment
SELECT s.student_id
FROM school.students AS s
WHERE EXISTS (
    SELECT 1
    FROM school.enrollments AS e
    WHERE e.student_id = s.student_id
);

-- IN: same kind of filter using a list of student IDs
SELECT student_id
FROM school.students
WHERE student_id IN (
    SELECT student_id
    FROM school.enrollments
);

-- JOIN: use this form when enrollment columns are also needed
SELECT s.student_id, e.course_id, e.grade
FROM school.students AS s
JOIN school.enrollments AS e ON e.student_id = s.student_id;
```

These forms can have different behavior with `NULL` values and duplicates,
especially `NOT IN`; choose based on the result you need and check the query
plan rather than assuming one form is always faster.

## Transactions (TCL, also called transaction control)

Use a transaction to group changes. This example verifies the update before
rolling it back, so the sample data is unchanged:

```sql
BEGIN;

UPDATE school.students
SET city = 'Vancouver'
WHERE student_id = 1;

SELECT student_id, city
FROM school.students
WHERE student_id = 1;

ROLLBACK;
```

Use `COMMIT` instead of `ROLLBACK` when you want to keep the changes.

## Indexes

An index is a separate data structure PostgreSQL can use to find matching rows
without scanning the whole table. The setup script creates indexes on columns
used to join courses, instructors, and enrollments. For example, this query
can use the `courses_department_id_idx` index:

```sql
SELECT course_id, course_name
FROM school.courses
WHERE department_id = 1;
```

PostgreSQL chooses whether an index is worthwhile based on the query and table
statistics; an index is not guaranteed to make every query faster. Indexes
also use storage and add work to inserts, updates, and deletes, so index
columns that are commonly filtered, joined, or sorted rather than every
column. An index can be created on an expression, such as a function call:

```sql
CREATE INDEX IF NOT EXISTS students_lower_email_idx
ON school.students (lower(email));

SELECT student_id, email
FROM school.students
WHERE lower(email) = lower('student1@example.test');
```

The query expression should match the indexed expression for PostgreSQL to
use an expression index. Check a plan with `EXPLAIN`; `EXPLAIN ANALYZE` also
runs the query and reports actual timing:

```sql
EXPLAIN
SELECT course_id, course_name
FROM school.courses
WHERE department_id = 1;
```

The setup script also demonstrates built-in PostgreSQL functions such as
`generate_series` and `lpad`; the examples here use functions such as `lower`
and `concat_ws`.

## Writing a PostgreSQL function

A function takes inputs and returns a value (or a set of rows). Declare its
parameters, return type, language, and body. This SQL-language function looks
up a student's full name:

```sql
CREATE OR REPLACE FUNCTION school.student_full_name(p_student_id BIGINT)
RETURNS TEXT
LANGUAGE SQL
STABLE
AS $$
    SELECT concat_ws(' ', first_name, last_name)
    FROM school.students
    WHERE student_id = p_student_id;
$$;

SELECT school.student_full_name(1);
```

`STABLE` tells PostgreSQL the function returns the same result for the same
arguments within one statement. Use `IMMUTABLE` only when the result depends
solely on the arguments and never on table data or changing settings.

## NULLIF, COALESCE, and CASE

Use `IS NULL` and `IS NOT NULL` to test for missing values. Comparisons such
as `phone_number = NULL` do not work as expected because `NULL` means unknown:

```sql
SELECT student_id
FROM school.students
WHERE phone_number IS NULL;
```

`IFNULL` is used by some other database systems, but PostgreSQL uses
`COALESCE` for the same common purpose: return the first non-`NULL` value.

`NULLIF(a, b)` returns `NULL` when `a` equals `b`; otherwise it returns `a`.
It is often used to avoid division by zero:

```sql
SELECT 10.0 / NULLIF(0, 0) AS safe_result; -- NULL instead of a division error
```

`COALESCE(a, b, ...)` returns the first argument that is not `NULL`. For
example, display a fallback when a student has no phone number:

```sql
SELECT student_id, COALESCE(phone_number, 'No phone number') AS phone
FROM school.students
WHERE student_id = 1;
```

`CASE` is a conditional expression: it checks conditions in order and returns
the result for the first match. It can be used in a `SELECT` to label grades:

```sql
SELECT student_id, course_id, grade,
       CASE
           WHEN grade IS NULL THEN 'Not graded'
           WHEN grade >= 90 THEN 'A'
           WHEN grade >= 80 THEN 'B'
           WHEN grade >= 70 THEN 'C'
           ELSE 'Needs improvement'
       END AS grade_label
FROM school.enrollments
WHERE student_id = 1;
```

## Triggers

A trigger runs a function automatically when a specified table event occurs.
This example updates a timestamp before each student row is updated. `NEW`
represents the row being written; a `BEFORE` trigger can change it and return
it to PostgreSQL.

```sql
ALTER TABLE school.students
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP;

CREATE OR REPLACE FUNCTION school.set_student_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_student_updated_at ON school.students;
CREATE TRIGGER set_student_updated_at
BEFORE UPDATE ON school.students
FOR EACH ROW
EXECUTE FUNCTION school.set_student_updated_at();
```

Now an `UPDATE` fires the trigger for each affected student row:

```sql
UPDATE school.students
SET city = 'Vancouver'
WHERE student_id = 1;

SELECT student_id, city, updated_at
FROM school.students
WHERE student_id = 1;
```

## Views

A view saves a query under a name. It does not store a separate copy of the
query results:

```sql
CREATE OR REPLACE VIEW school.student_enrollments AS
SELECT s.student_id, s.first_name, s.last_name, c.course_name, e.grade
FROM school.enrollments AS e
JOIN school.students AS s ON s.student_id = e.student_id
JOIN school.courses AS c ON c.course_id = e.course_id;

SELECT *
FROM school.student_enrollments
WHERE student_id = 1;
```

## PostgreSQL complex data types

In addition to basic types such as `TEXT`, `DATE`, and `NUMERIC`, PostgreSQL
supports arrays, JSON, composite types, and range types. These examples show
how to construct and query them:

```sql
-- Array
SELECT ARRAY['sql', 'postgresql'] AS topics;
SELECT (ARRAY[10, 20, 30])[2] AS second_value;

-- JSONB: extract a value by key
SELECT '{"level": "beginner", "credits": 3}'::jsonb ->> 'level' AS level;

-- Range: test whether a value is within a range
SELECT DATE '2025-03-15' <@ daterange(DATE '2025-03-01', DATE '2025-04-01')
    AS is_in_range;
```

A composite type can be declared and used as a table column:

```sql
CREATE TYPE school.contact_info AS (
    email TEXT,
    phone TEXT
);

CREATE TABLE school.student_contacts (
    student_id BIGINT REFERENCES school.students (student_id),
    contact school.contact_info
);
```
