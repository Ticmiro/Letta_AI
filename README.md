Cách 1: Cài đặt với chế độ tương tác (dễ nhất)
Người dùng chỉ cần sao chép và chạy lệnh này. Kịch bản sẽ tự hỏi bạn các thông tin cần thiết. \

bash <(curl -sL https://raw.githubusercontent.com/Ticmiro/Letta_AI/refs/heads/main/letta_https.sh)

Cách 2: Cài đặt với các tùy chọn (cho người dùng nâng cao)
Người dùng có thể cung cấp sẵn thông tin để cài đặt nhanh hơn mà không cần phải nhập liệu.

bash <(curl -sL https://raw.githubusercontent.com/Ticmiro/Letta_AI/refs/heads/main/Letta_AI.sh) \
-d "letta.your-domain.com" \
-o "sk-xxxxxxxxxxxx" \
-l "my-super-secret-key" \
-p "my_pg_password" \
-u "my_pg_user" \
-n "my_pg_database" \
-c "my_postgres_container"
lệnh cài thư viện craw4ai kèm posgrest SQL \
bash <(curl -sL https://raw.githubusercontent.com/Ticmiro/Letta_AI/refs/heads/main/VPS_services.sh) \
bash <(curl -sL https://raw.githubusercontent.com/Ticmiro/Letta_AI/refs/heads/main/lette_update_09-08-25.sh) \
lệnh cài đặt full dịch vụ \
bash <(curl -sL https://raw.githubusercontent.com/Ticmiro/Letta_AI/refs/heads/main/full%20%20service.sh)
