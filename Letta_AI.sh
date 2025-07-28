#!/bin/bash

#------------------------------------------------------------------
# Kịch bản cài đặt Letta Server tự động
# Hỗ trợ cả chế độ tương tác và chế độ tham số dòng lệnh.
#------------------------------------------------------------------

# Màu sắc để thông báo
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Hàm hiển thị hướng dẫn sử dụng ---
usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -d, --domain <domain/ip>      Tên miền hoặc địa chỉ IP của VPS."
    echo "  -o, --openai-key <key>        OpenAI API Key của bạn."
    echo "  -l, --letta-key <key>         Letta API Key bảo mật của bạn."
    echo "  -p, --pg-password <password>  Mật khẩu của user PostgreSQL."
    echo "  -u, --pg-user <user>          Tên user của PostgreSQL (ví dụ: ticmiro2)."
    echo "  -n, --pg-db <dbname>          Tên database của PostgreSQL (ví dụ: ticmirodb2)."
    echo "  -c, --pg-container <name>     Tên container Docker của PostgreSQL (mặc định: postgres_db)."
    echo "  -h, --help                    Hiển thị hướng dẫn này."
    echo ""
    echo "Nếu không có tùy chọn nào được cung cấp, kịch bản sẽ chạy ở chế độ tương tác."
    exit 1
}

# --- Xử lý các tham số dòng lệnh ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -d|--domain) SERVER_HOST="$2"; shift ;;
        -o|--openai-key) OPENAI_API_KEY="$2"; shift ;;
        -l|--letta-key) LETTA_API_KEY="$2"; shift ;;
        -p|--pg-password) POSTGRES_PASSWORD="$2"; shift ;;
        -u|--pg-user) POSTGRES_USER="$2"; shift ;;
        -n|--pg-db) POSTGRES_DB="$2"; shift ;;
        -c|--pg-container) POSTGRES_CONTAINER_NAME="$2"; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

# --- Chế độ tương tác nếu thiếu thông tin ---
echo -e "${GREEN}Chào mừng bạn đến với kịch bản cài đặt Letta Server tự động!${NC}"
echo "------------------------------------------------------------------"

# Hỏi thông tin nếu chưa được cung cấp qua tham số
[[ -z "$SERVER_HOST" ]] && read -p "Nhập tên miền hoặc IP của VPS: " SERVER_HOST
[[ -z "$OPENAI_API_KEY" ]] && read -p "Nhập OpenAI API Key (sk-...): " OPENAI_API_KEY
[[ -z "$LETTA_API_KEY" ]] && read -p "Tạo và nhập một Letta API Key (chuỗi ngẫu nhiên, bảo mật): " LETTA_API_KEY
[[ -z "$POSTGRES_PASSWORD" ]] && read -s -p "Nhập mật khẩu cho PostgreSQL User: " POSTGRES_PASSWORD && echo
[[ -z "$POSTGRES_USER" ]] && read -p "Nhập tên user của PostgreSQL (ví dụ: ticmiro2): " POSTGRES_USER
[[ -z "$POSTGRES_DB" ]] && read -p "Nhập tên database của PostgreSQL (ví dụ: ticmirodb2): " POSTGRES_DB
[[ -z "$POSTGRES_CONTAINER_NAME" ]] && read -p "Nhập tên container Docker của PostgreSQL (mặc định: postgres_db): " POSTGRES_CONTAINER_NAME

# Gán giá trị mặc định nếu vẫn trống
POSTGRES_CONTAINER_NAME=${POSTGRES_CONTAINER_NAME:-postgres_db}

# --- Kiểm tra các điều kiện cần thiết ---
echo "------------------------------------------------------------------"
echo -e "${YELLOW}Kiểm tra các điều kiện tiên quyết...${NC}"

if ! [ -x "$(command -v docker)" ] || ! [ -x "$(command -v docker-compose)" ]; then
  echo -e "${RED}Lỗi: Docker hoặc Docker Compose chưa được cài đặt. Vui lòng cài đặt trước.${NC}" >&2
  exit 1
fi

if ! docker ps --filter "name=${POSTGRES_CONTAINER_NAME}" --format '{{.Names}}' | grep -wq "${POSTGRES_CONTAINER_NAME}"; then
    echo -e "${RED}Lỗi: Không tìm thấy container PostgreSQL '${POSTGRES_CONTAINER_NAME}' đang chạy.${NC}" >&2
    exit 1
fi
echo "=> Container PostgreSQL '${POSTGRES_CONTAINER_NAME}' đã sẵn sàng."

echo "=> Đang tự động tìm Docker network của '${POSTGRES_CONTAINER_NAME}'..."
DOCKER_NETWORK_NAME=$(docker inspect -f '{{range $key, $value := .NetworkSettings.Networks}}{{$key}}{{end}}' "${POSTGRES_CONTAINER_NAME}")

if [ -z "$DOCKER_NETWORK_NAME" ]; then
    echo -e "${RED}Lỗi: Không thể tự động tìm thấy network của container '${POSTGRES_CONTAINER_NAME}'.${NC}" >&2
    exit 1
fi
echo -e "=> Tìm thấy network: ${GREEN}${DOCKER_NETWORK_NAME}${NC}"

# --- Tạo thư mục và các tệp cấu hình ---
echo "------------------------------------------------------------------"
echo -e "${YELLOW}Bắt đầu tạo thư mục và các tệp cấu hình...${NC}"
mkdir -p letta-server
cd letta-server

# Tạo tệp .env
echo "=> Tạo tệp .env..."
cat <<EOF > .env
# Tệp này được tạo tự động
OPENAI_API_KEY=${OPENAI_API_KEY}
LETTA_API_KEY=${LETTA_API_KEY}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
EOF

# Tạo tệp nginx.conf
echo "=> Tạo tệp nginx.conf..."
cat <<EOF > nginx.conf
events {}
http {
    server {
        listen 80;
        server_name ${SERVER_HOST};
        location / {
            proxy_pass http://letta_api_server:8283;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
        }
    }
}
EOF

# Tạo tệp compose.yaml
echo "=> Tạo tệp compose.yaml..."
cat <<EOF > compose.yaml
services:
  letta_server:
    image: letta/letta:latest
    container_name: letta_api_server
    restart: unless-stopped
    env_file:
      - .env
    environment:
      - LETTA_PG_URI=postgresql://${POSTGRES_USER}:\${POSTGRES_PASSWORD}@${POSTGRES_CONTAINER_NAME}:5432/${POSTGRES_DB}
      - OPENAI_API_KEY=\${OPENAI_API_KEY}
      - LETTA_API_KEY=\${LETTA_API_KEY}
    networks:
      - ${DOCKER_NETWORK_NAME}
  letta_nginx:
    image: nginx:stable-alpine
    container_name: letta_nginx_proxy
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
    ports:
      - "80:80"
    depends_on:
      - letta_server
    networks:
      - ${DOCKER_NETWORK_NAME}
networks:
  ${DOCKER_NETWORK_NAME}:
    external: true
EOF

echo -e "${GREEN}Tạo các tệp cấu hình thành công!${NC}"

# --- Khởi chạy Docker Compose ---
echo "------------------------------------------------------------------"
echo -e "${YELLOW}Chuẩn bị khởi động các container...${NC}"

docker-compose -f compose.yaml down --remove-orphans
docker-compose -f compose.yaml up -d --force-recreate --remove-orphans

echo "------------------------------------------------------------------"
echo -e "${GREEN}🚀 Hoàn tất!${NC}"
echo "Đang kiểm tra trạng thái các container:"
docker ps --filter "name=letta"
echo ""
echo "Bạn có thể truy cập Letta tại: http://${SERVER_HOST}"
echo "Để xem log, sử dụng lệnh: docker-compose -f compose.yaml logs -f"