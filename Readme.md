Bạn là một Senior Database Engineer / DevOps Engineer có nhiều kinh nghiệm trong việc migrate database từ Oracle sang PostgreSQL trong môi trường Docker.

Bối cảnh hiện tại của tôi như sau:

- Tôi đang sử dụng Docker
- File @docker-compose.yaml  đã được cấu hình sẵn:
  - 01 Oracle Database
  - 01 PostgreSQL Database
- Toàn bộ thông tin connection (host, port, service name, user, password) của Oracle và PostgreSQL đều đã có trong file @docker-compose.yaml 
- Tôi đã import dữ liệu mẫu từ thư mục @data/  vào Oracle Database
- Tôi đã sử dụng AWS Schema Conversion Tool (SCT) để migrate toàn bộ schema (table, index, sequence, constraint, ...) từ Oracle sang PostgreSQL thành công
- Hiện tại:
  - Schema đã tồn tại đầy đủ trong PostgreSQL
  - Data vẫn chỉ tồn tại trong Oracle
  - Tôi cần migrate toàn bộ data của các bảng từ Oracle sang PostgreSQL

Yêu cầu chính:
👉 Hãy hướng dẫn tôi sử dụng tool Ora2Pg (được recommend để migrate Oracle → PostgreSQL) để migrate DATA của các bảng từ Oracle sang PostgreSQL một cách chi tiết, chính xác và có thể chạy được trong thực tế.

Yêu cầu chi tiết cho câu trả lời:

1. Giải thích ngắn gọn:
   - Ora2Pg là gì
   - Vì sao Ora2Pg phù hợp cho việc migrate data Oracle → PostgreSQL

2. Kiến trúc & luồng migration:
   - Mô tả luồng: Oracle DB → Ora2Pg → PostgreSQL DB

3. Cài đặt Ora2Pg:
   - Ưu tiên chạy Ora2Pg bằng Docker
   - Có thể dùng image trên dockerhub: https://hub.docker.com/r/georgmoser/ora2pg 
   - Hướng dẫn cách để Ora2Pg kết nối được tới Oracle và PostgreSQL dựa trên network trong docker-compose.yaml

4. Cấu hình Ora2Pg:
   - Hướng dẫn tạo file cấu hình ora2pg.conf
   - Lấy thông tin connection từ @docker-compose.yaml
   - Cấu hình kết nối:
     - Oracle (ORACLE_DSN, USER, PASSWORD)
     - PostgreSQL (PG_DSN, USER, PASSWORD)
   - Cung cấp ví dụ file ora2pg.conf đầy đủ

5. Migration DATA (phần quan trọng nhất):
   - Chỉ migrate DATA, KHÔNG cần migrate schema
   - Cấu hình:
     - TYPE = DATA
     - SCHEMA
     - TABLES (all tables hoặc chỉ định)
     - COMMIT / BATCH_SIZE
   - Giải thích rõ từng option
   - Script liên quan thì sẽ tạo và để chung trong folder: @migrate-data/ 

6. Thực thi migration:
   - Các command line cụ thể:
     - Test kết nối Oracle
     - Test kết nối PostgreSQL
     - Export data
     - Import data vào PostgreSQL
   - Ví dụ command ora2pg có thể copy & chạy

7. Kiểm tra & validate sau migration:
   - So sánh số lượng record giữa Oracle và PostgreSQL
   - SQL kiểm tra data
   - Gợi ý cách phát hiện lỗi data

8. Xử lý các vấn đề thường gặp:
   - Encoding (UTF-8)
   - DATE / TIMESTAMP
   - NUMBER → NUMERIC
   - Constraint / Foreign Key / Trigger
   - Performance khi migrate data lớn

9. Best practices:
   - Backup trước khi migrate
   - Disable constraint & trigger khi import
   - Migrate theo batch
   - Log & rollback strategy

Yêu cầu output:
- Trả lời bằng tiếng Việt
- Có ví dụ thực tế
- Có file config mẫu + command mẫu
- Phù hợp cho môi trường Docker
- Có thể copy & chạy được
- Trình bày rõ ràng, có tiêu đề từng phần