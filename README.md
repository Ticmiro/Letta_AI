Cách 1: Cài đặt với chế độ tương tác (dễ nhất)
Người dùng chỉ cần sao chép và chạy lệnh này. Kịch bản sẽ tự hỏi bạn các thông tin cần thiết.

bash <(curl -sL https://raw.githubusercontent.com/TEN_CUA_BAN/letta-installer/main/install_letta.sh)

Cách 2: Cài đặt với các tùy chọn (cho người dùng nâng cao)
Người dùng có thể cung cấp sẵn thông tin để cài đặt nhanh hơn mà không cần phải nhập liệu.

bash <(curl -sL https://raw.githubusercontent.com/TEN_CUA_BAN/letta-installer/main/install_letta.sh) \
-d "letta.your-domain.com" \
-o "sk-xxxxxxxxxxxx" \
-l "my-super-secret-key" \
-p "my_pg_password" \
-u "my_pg_user" \
-n "my_pg_database" \
-c "my_postgres_container"
