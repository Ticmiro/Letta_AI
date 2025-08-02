#!/bin/bash

#------------------------------------------------------------------
# KỊCH BẢN CÀI ĐẶT LETTA AI HOÀN THIỆN (v5.0 - Final Edition)
# Tác giả: Ticmiro
# Chức năng:
# - Tự động cài đặt Docker & Docker Compose.
# - Tự động cài đặt HTTPS với Let's Encrypt.
# - Sử dụng lệnh Docker Compose v2 (docker compose).
# - Tự động sửa lỗi định dạng file YAML.
#------------------------------------------------------------------

# --- Tiện ích ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
CYAN='\033[0;36m'

# --- BẢNG THÔNG TIN TÁC GIẢ ---
echo -e "${CYAN}####################################################################${NC}"
echo -e "${CYAN}#                                                                  #${NC}"
echo -e "${CYAN}#      ${YELLOW}KỊCH BẢN CÀI ĐẶT TỰ ĐỘNG HỆ SINH THÁI DỊCH VỤ VPS${NC}      ${CYAN}#${NC}"
echo -e "${CYAN}#                                                                  #${NC}"
echo -e "${CYAN}# ${GREEN}Tác giả: Ticmiro${NC}                                                ${CYAN}#${NC}"
echo -e "${CYAN}# ${GREEN}Một sản phẩm tâm huyết đóng góp cho cộng đồng.${NC}                 ${CYAN}#${NC}"
echo -e "${CYAN}#                                                                  #${NC}"
echo -e "${CYAN}# ${YELLOW}Follow me on GitHub:${NC} ${GREEN}https://github.com/Ticmiro${NC}               ${CYAN}#${NC}"
echo -e "${CYAN}# ${YELLOW}Connect on Facebook:${NC} ${GREEN}https://www.facebook.com/tic.miro${NC}      ${CYAN}#${NC}"
echo -e "${CYAN}#                                                                  #${NC}"
echo -e "${CYAN}####################################################################${NC}"
echo ""
echo -e "Nếu bạn thấy kịch bản này hữu ích, hãy tặng một ngôi sao ⭐ trên GitHub và kết nối với mình nhé!"
echo "------------------------------------------------------------------"

# --- 0. KIỂM TRA VÀ CÀI ĐẶT DOCKER (NẾU CẦN) ---
if ! [ -x "$(command -v docker)" ]; then
  echo -e "${YELLOW}Docker chưa được cài đặt. Bắt đầu quá trình cài đặt tự động...${NC}"
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  echo -e "${GREEN}Cài đặt Docker và Docker Compose thành công!${NC}"
else
  echo -e "${GREEN}Docker đã được cài đặt. Bỏ qua bước cài đặt.${NC}"
fi
echo "------------------------------------------------------------------"

# --- 1. THU THẬP THÔNG TIN TỪ NGƯỜI DÙNG ---
echo -e "${GREEN}Chào mừng bạn đến với kịch bản cài đặt Letta Server tự động!${NC}"
echo "------------------------------------------------------------------"

# (Phần thu thập thông tin giữ nguyên logic từ file của bạn)
[[ -z "$SERVER_HOST" ]] && read -p "Nhập tên miền hoặc IP của VPS: " SERVER_HOST
[[ -z "$OPENAI_API_KEY" ]] && read -p "Nhập OpenAI API Key (sk-...): " OPENAI_API_KEY
[[ -z "$LETTA_API_KEY" ]] && read -p "Tạo và nhập một Letta API Key (chuỗi ngẫu nhiên, bảo mật): " LETTA_API_KEY
[[ -z "$POSTGRES_PASSWORD" ]] && read -s -p "Nhập mật khẩu cho PostgreSQL User (tránh ký tự đặc biệt): " POSTGRES_PASSWORD && echo
[[ -z "$POSTGRES_USER" ]] && read -p "Nhập tên user của PostgreSQL (ví dụ: ticmiro2): " POSTGRES_USER
[[ -z "$POSTGRES_DB" ]] && read -p "Nhập tên database của PostgreSQL (ví dụ: ticmirodb2): " POSTGRES_DB
[[ -z "$POSTGRES_CONTAINER_NAME" ]] && read -p "Nhập tên container Docker của PostgreSQL (mặc định: postgres_db): " POSTGRES_CONTAINER_NAME
POSTGRES_CONTAINER_NAME=${POSTGRES_CONTAINER_NAME:-postgres_db}
if [[ "$ENABLE_HTTPS" != "true" ]]; then
    read -p "Bạn có muốn kích hoạt HTTPS với Let's Encrypt không? (y/n): " ACTIVATE_HTTPS
    if [[ "$ACTIVATE_HTTPS" == "y" || "$ACTIVATE_HTTPS" == "Y" ]]; then
        ENABLE_HTTPS="true"
    fi
fi
if [[ "$ENABLE_HTTPS" == "true" ]]; then
    if [[ -z "$SERVER_HOST" || "$SERVER_HOST" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}Lỗi: Cần phải có một tên miền (không phải IP) để kích hoạt HTTPS.${NC}"
        exit 1
    fi
    [[ -z "$LETSENCRYPT_EMAIL" ]] && read -p "Nhập email của bạn (dùng cho Let's Encrypt): " LETSENCRYPT_EMAIL
    if [[ -z "$LETSENCRYPT_EMAIL" ]]; then
        echo -e "${RED}Lỗi: Email là bắt buộc khi sử dụng Let's Encrypt.${NC}"
        exit 1
    fi
fi

# --- 2. KIỂM TRA CÁC ĐIỀU KIỆN TIÊN QUYẾT ---
echo "------------------------------------------------------------------"
echo -e "${YELLOW}Kiểm tra các điều kiện tiên quyết...${NC}"

# ĐÃ CẬP NHẬT: Kiểm tra Docker Compose phiên bản mới
if ! docker compose version &> /dev/null && ! [ -x "$(command -v docker-compose)" ]; then
  echo -e "${RED}Lỗi: Docker Compose (plugin hoặc standalone) chưa được cài đặt.${NC}" >&2
  exit 1
fi

if ! docker ps --filter "name=${POSTGRES_CONTAINER_NAME}" --format '{{.Names}}' | grep -wq "${POSTGRES_CONTAINER_NAME}"; then
    echo -e "${RED}Lỗi: Không tìm thấy container PostgreSQL '${POSTGRES_CONTAINER_NAME}' đang chạy.${NC}" >&2
    exit 1
fi
echo "=> Container PostgreSQL '${POSTGRES_CONTAINER_NAME}' đã sẵn sàng."

# --- 3. CÀI ĐẶT HTTPS (NẾU ĐƯỢC KÍCH HOẠT) ---
if [[ "$ENABLE_HTTPS" == "true" ]]; then
    echo "------------------------------------------------------------------"
    echo -e "${YELLOW}Bắt đầu quá trình cài đặt HTTPS...${NC}"
    if ! [ -x "$(command -v certbot)" ]; then
        echo "=> Certbot chưa được cài đặt. Đang cài đặt..."
        sudo apt-get update && sudo apt-get install -y certbot
    fi
    echo "=> Đang mở cổng 80 trên tường lửa (ufw) để xác thực SSL..."
    sudo ufw allow 80/tcp
    echo "=> Đang dừng các dịch vụ trên cổng 80 để xin chứng chỉ SSL..."
    # ĐÃ CẬP NHẬT: Dừng container Nginx (nếu có) trước khi xin cert
    sudo docker stop letta_nginx_proxy > /dev/null 2>&1 || true
    sudo docker rm letta_nginx_proxy > /dev/null 2>&1 || true
    echo "=> Đang xin chứng chỉ SSL cho miền ${SERVER_HOST}..."
    sudo certbot certonly --standalone -d "${SERVER_HOST}" --non-interactive --agree-tos -m "${LETSENCRYPT_EMAIL}"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Lỗi: Không thể xin chứng chỉ SSL. Vui lòng kiểm tra lại tên miền đã trỏ về IP của VPS chưa.${NC}"
        exit 1
    fi
    echo -e "${GREEN}=> Xin chứng chỉ SSL thành công!${NC}"
fi

# --- 4. TẠO TỆP CẤU HÌNH ---
echo "------------------------------------------------------------------"
echo "=> Đang tự động tìm Docker network của '${POSTGRES_CONTAINER_NAME}'..."
DOCKER_NETWORK_NAME=$(docker inspect -f '{{range $key, $value := .NetworkSettings.Networks}}{{$key}}{{end}}' "${POSTGRES_CONTAINER_NAME}")
if [ -z "$DOCKER_NETWORK_NAME" ]; then
    echo -e "${RED}Lỗi: Không thể tự động tìm thấy network của container '${POSTGRES_CONTAINER_NAME}'.${NC}" >&2
    exit 1
fi
echo -e "=> Tìm thấy network: ${GREEN}${DOCKER_NETWORK_NAME}${NC}"

echo -e "${YELLOW}Bắt đầu tạo thư mục và các tệp cấu hình...${NC}"
mkdir -p letta-server && cd letta-server

echo "=> Tạo tệp .env..."
cat <<EOF > .env
OPENAI_API_KEY=${OPENAI_API_KEY}
LETTA_API_KEY=${LETTA_API_KEY}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
EOF

echo "=> Tạo tệp nginx.conf..."
if [[ "$ENABLE_HTTPS" == "true" ]]; then
cat <<EOF > nginx.conf
events {}
http {
    server {
        listen 80;
        server_name ${SERVER_HOST};
        location /.well-known/acme-challenge/ { root /var/www/certbot; }
        location / { return 301 https://\$host\$request_uri; }
    }
    server {
        listen 443 ssl http2;
        server_name ${SERVER_HOST};
        ssl_certificate /etc/letsencrypt/live/${SERVER_HOST}/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/${SERVER_HOST}/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
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
else
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
        }
    }
}
EOF
fi

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
$(if [[ "$ENABLE_HTTPS" == "true" ]]; then 
  echo "      - /etc/letsencrypt:/etc/letsencrypt:ro"
  echo "      - /var/www/certbot:/var/www/certbot:ro"
fi)
    ports:
      - "80:80"
$(if [[ "$ENABLE_HTTPS" == "true" ]]; then 
  echo "      - \"443:443\""
fi)
    depends_on:
      - letta_server
    networks:
      - ${DOCKER_NETWORK_NAME}
networks:
  ${DOCKER_NETWORK_NAME}:
    external: true
EOF
echo -e "${GREEN}Tạo các tệp cấu hình thành công!${NC}"

# --- 5. TRIỂN KHAI HỆ THỐNG ---
echo "------------------------------------------------------------------"
echo -e "${YELLOW}Chuẩn bị khởi chạy các container...${NC}"

# ĐÃ THÊM MỚI: Tự động làm sạch file YAML
echo "=> Đang làm sạch tệp compose.yaml để đảm bảo tương thích..."
sed -i 's/\r$//' compose.yaml

# ĐÃ CẬP NHẬT: Sử dụng lệnh `docker compose` mới
sudo docker compose -f compose.yaml down --remove-orphans > /dev/null 2>&1
sudo docker compose -f compose.yaml up -d --force-recreate --remove-orphans

echo "------------------------------------------------------------------"
echo -e "${GREEN}🚀 Hoàn tất!${NC}"
echo "Đang kiểm tra trạng thái các container:"
docker ps --filter "name=letta"
echo ""
if [[ "$ENABLE_HTTPS" == "true" ]]; then
    echo "Bạn có thể truy cập Letta tại: https://${SERVER_HOST}"
else
    echo "Bạn có thể truy cập Letta tại: http://${SERVER_HOST}"
fi
# ĐÃ CẬP NHẬT: Sử dụng lệnh `docker compose` mới
echo "Để xem log, sử dụng lệnh: cd letta-server && sudo docker compose logs -f"
