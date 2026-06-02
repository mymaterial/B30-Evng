


cd /softwares/demo/schema/human_resources

grant dba to hr;

conn hr


CLOB DATA
----------




SELECT dbms_lob.getlength(clob_data) AS length, dbms_lob.substr(clob_data, 4000, 1) AS first_4000_chars
FROM clob_data_table;

create or replace directory blob_dir as '/home/oracle';

-- grant read, write on directory blob_dir to hr;

create table blob_data_table (
  id        number,
  blob_data blob
);

insert into blob_data_table (id, blob_data)
values (1, to_blob(bfilename('BLOB_DIR', 'hr_main.log')));

update blob_data_table
set    blob_data = bfilename('BLOB_DIR', 'hr_main.log')
where  id = 1;

select * from blob_data_table;

++++


+++++
-- Creating the procedure with an explicit cursor


BEGIN
  get_employee_data_explicit_cursor;
END;
/

++++


BEGIN
  process_data;
END;
/



BEGIN
    update_column_value(2, 'New_Value');
END;
/

CREATE OR REPLACE PROCEDURE print_sysdate IS
BEGIN
  DBMS_OUTPUT.PUT_LINE('Current date is: ' || TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS'));
END print_sysdate;
/


SET SERVEROUTPUT ON; -- Enable DBMS_OUTPUT

BEGIN
  print_sysdate;
END;
/







--

ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;

shutdown immediate;

startup mount;

alter database archivelog;

alter database open;

SELECT supplemental_log_data_min FROM v$database;

mkdir -p /softwares/dbs/arch

alter system switch logfile;

set lines 1200 pages 1200

select 'ALTER TABLE '||table_name||' ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;' from all_tables where owner = 'HR';

ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (PRIMARY KEY) COLUMNS;

ALTER TABLE REGIONS ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE LOCATIONS ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE DEPARTMENTS ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE JOBS ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE EMPLOYEES ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE JOB_HISTORY ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE CLOB_DATA_TABLE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE BLOB_DATA_TABLE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE RANDOM_DATA_TABLE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE TEST ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE COUNTRIES ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE IDENTITY_TST ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE SYSTEM_EVENTS ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;


--- complete preparing 

Solutions
==========

ALTER TABLE BLOB_DATA_TABLE ADD CONSTRAINT id_key PRIMARY KEY (id);

create table test(idx int, txt clob);

post activity
----------------

set serveroutput on

BEGIN
  get_employee_data;
END;
/

in PostgreSQL

call  get_employee_data();

\sf get_employee_data
\ef get_employee_data

Replace 
CALL aws_oracle_ext.dbms_output$put_line(a => CONCAT_WS('', 'Employee ID: ', v_employee_id, ', Name: ', v_first_name, ' ', v_last_name, ', Email: ', v_email));

With

RAISE NOTICE 'Employee ID: %, Name: % %, Email: %', v_employee_id, v_first_name, v_last_name, v_email;

:wq
;


select SUBSTR(col1, 0,1) from random_data_table;
select SUBSTR(col1,1,1) from random_data_table;

RAISE NOTICE 'Substring of col1: %', SUBSTR(rec.col1,1,5);



SELECT * FROM sales PARTITION (sales_january);
select * from sales_sales_january;

select current_timestamp;

SELECT * FROM SYSTEM_EVENTS;

INSERT INTO SYSTEM_EVENTS VALUES(4, 'EVNT-C1-09', 'Warning', '01-JAN-2018');

postgres=> INSERT INTO SYSTEM_EVENTS VALUES(4, 'EVNT-C1-09', 'Warning', '01-JAN-2018');
INSERT 0 1
postgres=>  SELECT * FROM SYSTEM_EVENTS;
 event_id | event_code | event_desciption |     event_time
----------+------------+------------------+---------------------
        1 | EVNT-C1-09 | Warning          | 2017-01-01 00:00:00
        7 | EVNT-E1-14 | Critical         | 2017-01-01 00:00:00
        9 | EVNT-A1-10 | Critical         | 2017-01-01 00:00:00
        4 | EVNT-C1-09 | Warning          | 2018-01-01 00:00:00
(4 rows)

postgres=>



CREATE TABLE sample_table (
    id int,
    column_with_null VARCHAR(50)
);

-- Insert some sample data
INSERT INTO sample_table VALUES (1, 'Value 1');
INSERT INTO sample_table VALUES (2, NULL);
INSERT INTO sample_table VALUES (3, 'Value 3');

SELECT COALESCE(column_with_null, 'Default_Value') from sample_table;

+++

-- Create a procedure that uses NVL
CREATE OR REPLACE PROCEDURE sample_procedure AS
    v_value VARCHAR2(50);
BEGIN
    -- Use NVL in a SELECT statement
    SELECT NVL(column_with_null, 'Default_Value') INTO v_value
    FROM sample_table
    WHERE id = 2;

    -- Display the result
    DBMS_OUTPUT.PUT_LINE('Result: ' || v_value);
END sample_procedure;
/

BEGIN
    sample_procedure;
END;
/

-- Create a function that uses COALESCE
CREATE OR REPLACE FUNCTION sample_function()
RETURNS VOID AS $$
DECLARE
    v_value VARCHAR;
BEGIN
    -- Use COALESCE in a SELECT statement
    SELECT COALESCE(column_with_null, 'Default_Value') INTO v_value
    FROM sample_table
    WHERE id = 2;

    -- Display the result
    RAISE NOTICE 'Result: %', v_value;
END;
$$ LANGUAGE plpgsql;

-- Execute the function
SELECT sample_function();

+++


postgres=>
postgres=> CLUSTER SYSTEM_EVENTS USING PK_EVENT_ID;
CLUSTER
postgres=> SELECT * FROM SYSTEM_EVENTS;
 event_id | event_code | event_desciption |     event_time
----------+------------+------------------+---------------------
        1 | EVNT-C1-09 | Warning          | 2017-01-01 00:00:00
        4 | EVNT-C1-09 | Warning          | 2018-01-01 00:00:00
        7 | EVNT-E1-14 | Critical         | 2017-01-01 00:00:00
        9 | EVNT-A1-10 | Critical         | 2017-01-01 00:00:00
(4 rows)

postgres=>





+++END+++++


nvl vs collsce
----------------


-- Create a sample table
CREATE TABLE sample_table (
    id NUMBER,
    column_with_null VARCHAR2(50)
);

-- Insert some sample data
INSERT INTO sample_table VALUES (1, 'Value 1');
INSERT INTO sample_table VALUES (2, NULL);
INSERT INTO sample_table VALUES (3, 'Value 3');

-- Create the update procedure
CREATE OR REPLACE PROCEDURE update_column_value(
    p_id NUMBER,
    p_new_value VARCHAR2
) AS
BEGIN
    UPDATE sample_table
    SET column_with_null = p_new_value
    WHERE id = p_id;
    
    COMMIT; -- Commit the transaction
END update_column_value;
/

BEGIN
    update_column_value(2, 'New_Value');
END;
/

SELECT NVL(column_with_null, 'Default_Value') from sample_table;

+++

CREATE TABLE sample_table (
    id int,
    column_with_null VARCHAR(50)
);

-- Insert some sample data
INSERT INTO sample_table VALUES (1, 'Value 1');
INSERT INTO sample_table VALUES (2, NULL);
INSERT INTO sample_table VALUES (3, 'Value 3');

SELECT COALESCE(column_with_null, 'Default_Value') from sample_table;

+++

-- Create a procedure that uses NVL
CREATE OR REPLACE PROCEDURE sample_procedure AS
    v_value VARCHAR2(50);
BEGIN
    -- Use NVL in a SELECT statement
    SELECT NVL(column_with_null, 'Default_Value') INTO v_value
    FROM sample_table
    WHERE id = 2;

    -- Display the result
    DBMS_OUTPUT.PUT_LINE('Result: ' || v_value);
END sample_procedure;
/

BEGIN
    sample_procedure;
END;
/

+++

-- Create a function that uses COALESCE
CREATE OR REPLACE FUNCTION sample_function()
RETURNS VOID AS $$
DECLARE
    v_value VARCHAR;
BEGIN
    -- Use COALESCE in a SELECT statement
    SELECT COALESCE(column_with_null, 'Default_Value') INTO v_value
    FROM sample_table
    WHERE id = 2;

    -- Display the result
    RAISE NOTICE 'Result: %', v_value;
END;
$$ LANGUAGE plpgsql;

-- Execute the function
SELECT sample_function();



