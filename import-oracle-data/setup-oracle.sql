-- Script để setup Oracle database trước khi import
-- Chạy script này với quyền SYSDBA hoặc SYSTEM

-- Kết nối vào PDB XEPDB1
ALTER SESSION SET CONTAINER = XEPDB1;

-- Tạo directory object để trỏ đến thư mục dump
CREATE OR REPLACE DIRECTORY DUMP_DIR AS '/opt/oracle/dump';
GRANT READ, WRITE ON DIRECTORY DUMP_DIR TO SYSTEM;
GRANT READ, WRITE ON DIRECTORY DUMP_DIR TO PUBLIC;

-- Tạo user TRUYENNHIEM_NEW nếu chưa tồn tại
-- (User sẽ được tạo tự động khi import, nhưng có thể tạo trước nếu cần)
BEGIN
   EXECUTE IMMEDIATE 'CREATE USER TRUYENNHIEM_NEW IDENTIFIED BY "TRUYENNHIEM_NEW"';
EXCEPTION
   WHEN OTHERS THEN
      IF SQLCODE = -01920 THEN
         NULL; -- User đã tồn tại, bỏ qua
      ELSE
         RAISE;
      END IF;
END;
/

-- Tạo tablespace TRUYENNHIEM_NEW nếu chưa tồn tại
-- (Oracle XE thường chỉ hỗ trợ một tablespace chính, nhưng có thể tạo thêm)
BEGIN
   EXECUTE IMMEDIATE 'CREATE TABLESPACE TRUYENNHIEM_NEW DATAFILE ''/opt/oracle/oradata/XE/XEPDB1/truyennhiem_new.dbf'' SIZE 500M AUTOEXTEND ON NEXT 100M MAXSIZE UNLIMITED';
EXCEPTION
   WHEN OTHERS THEN
      IF SQLCODE = -01543 THEN
         NULL; -- Tablespace đã tồn tại, bỏ qua
      ELSE
         RAISE;
      END IF;
END;
/

-- Cấp quyền cho user
GRANT CONNECT, RESOURCE, UNLIMITED TABLESPACE TO TRUYENNHIEM_NEW;
GRANT READ, WRITE ON DIRECTORY DUMP_DIR TO TRUYENNHIEM_NEW;
ALTER USER TRUYENNHIEM_NEW DEFAULT TABLESPACE TRUYENNHIEM_NEW;
ALTER USER TRUYENNHIEM_NEW QUOTA UNLIMITED ON TRUYENNHIEM_NEW;

COMMIT;
