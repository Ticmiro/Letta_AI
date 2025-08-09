#!/bin/bash

#------------------------------------------------------------------
# KỊCH BẢN CÀI ĐẶT LETTA AI HOÀN THIỆN (v6.0 - Smart Port Handling)
# Tác giả: Ticmiro
# Chức năng:
# - Tự động phát hiện, dừng và khởi động lại dịch vụ chiếm cổng 80.
# - Tự động cài đặt Docker & Docker Compose.
# - Tự động cài đặt HTTPS với Let's Encrypt.
# - Tự động xử lý mạng Docker và lỗi định dạng file YAML.
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
# (Phần thu thập thông tin giữ nguyên)
echo -e "${GREEN}Chào mừng bạn đến với kịch bản cài đặt Letta Server tự động!${NC}"
echo "------------------------------------------------------------------"
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
# (Phần này giữ nguyên)
echo "------------------------------------------------------------------"
echo -e "${YELLOW}Kiểm tra các điều kiện tiên quyết...${NC}"
if ! docker compose version &> /dev/null && ! [ -x "$(command -v docker-compose)" ]; then
  echo -e "${RED}Lỗi: Docker Compose (plugin hoặc standalone) chưa được cài đặt.${NC}" >&2
  exit 1
fi
if ! docker ps --filter "name=${POSTGRES_CONTAINER_NAME}" --format '{{.Names}}' | grep -wq "${POSTGRES_CONTAINER_NAME}"; then
    echo -e "${RED}Lỗi: Không tìm thấy container PostgreSQL '${POSTGRES_CONTAINER_NAME}' đang chạy.${NC}" >&2
    exit 1
fi
echo "=> Container PostgreSQL '${POSTGRES_CONTAINER_NAME}' đã sẵn sàng."


# --- 3. CÀI ĐẶT HTTPS VÀ TỰ ĐỘNG XỬ LÝ XUNG ĐỘT CỔNG 80 ---
if [[ "$ENABLE_HTTPS" == "true" ]]; then
    echo "------------------------------------------------------------------"
    echo -e "${YELLOW}Bắt đầu quá trình cài đặt HTTPS...${NC}"
    if ! [ -x "$(command -v certbot)" ]; then
        echo "=> Certbot chưa được cài đặt. Đang cài đặt..."
        sudo apt-get update && sudo apt-get install -y certbot
    fi
    
    # --- LOGIC MỚI: TỰ ĐỘNG XỬ LÝ XUNG ĐỘT CỔNG 80 ---
    CONFLICTING_SERVICE=""
    CONFLICTING_CONTAINER_ID=""
    
    echo "=> Đang kiểm tra cổng 80..."
    # Ưu tiên kiểm tra Docker container trước
    CONFLICTING_CONTAINER_ID=$(sudo docker ps -q -f "publish=80")
    
    if [ -n "$CONFLICTING_CONTAINER_ID" ]; then
        CONFLICTING_SERVICE="docker"
        CONFLICTING_CONTAINER_NAME=$(sudo docker inspect --format '{{.Name}}' $CONFLICTING_CONTAINER_ID | sed 's/\///')
        echo -e "${YELLOW}Phát hiện cổng 80 đang được sử dụng bởi container Docker: ${CONFLICTING_CONTAINER_NAME}${NC}"
        echo "=> Tạm thời dừng container này để xin chứng chỉ SSL..."
        sudo docker stop $CONFLICTING_CONTAINER_ID
    # Nếu không phải Docker, kiểm tra các dịch vụ hệ thống phổ biến
    elif sudo lsof -i :80 -sTCP:LISTEN -t >/dev/null ; then
        if sudo lsof -i :80 | grep -q "nginx"; then
            CONFLICTING_SERVICE="nginx"
            echo -e "${YELLOW}Phát hiện cổng 80 đang được sử dụng bởi dịch vụ Nginx của hệ thống.${NC}"
            echo "=> Tạm thời dừng Nginx..."
            sudo systemctl stop nginx
        elif sudo lsof -i :80 | grep -q "apache2"; then
            CONFLICTING_SERVICE="apache2"
            echo -e "${YELLOW}Phát hiện cổng 80 đang được sử dụng bởi dịch vụ Apache2 của hệ thống.${NC}"
            echo "=> Tạm thời dừng Apache2..."
            sudo systemctl stop apache2
        fi
    fi
    # --- KẾT THÚC LOGIC PHÁT HIỆN ---
    
    echo "=> Đang xin chứng chỉ SSL cho miền ${SERVER_HOST}..."
    sudo certbot certonly --standalone -d "${SERVER_HOST}" --non-interactive --agree-tos -m "${LETSENCRYPT_EMAIL}"
    CERTBOT_EXIT_CODE=$?

    # --- LOGIC MỚI: KHÔI PHỤC LẠI DỊCH VỤ BAN ĐẦU ---
    if [ -n "$CONFLICTING_SERVICE" ]; then
        echo "=> Khởi động lại dịch vụ ban đầu đã bị dừng..."
        if [ "$CONFLICTING_SERVICE" == "docker" ]; then
            sudo docker start $CONFLICTING_CONTAINER_ID
            echo -e "${GREEN}=> Container ${CONFLICTING_CONTAINER_NAME} đã được khởi động lại.${NC}"
        else
            sudo systemctl start $CONFLICTING_SERVICE
            echo -e "${GREEN}=> Dịch vụ ${CONFLICTING_SERVICE} đã được khởi động lại.${NC}"
        fi
    fi
    # --- KẾT THÚC LOGIC KHÔI PHỤC ---

    if [ $CERTBOT_EXIT_CODE -ne 0 ]; then
        echo -e "${RED}Lỗi: Không thể xin chứng chỉ SSL. Đã khôi phục dịch vụ ban đầu. Vui lòng kiểm tra lại tên miền đã trỏ về IP của VPS chưa.${NC}"
        exit 1
    fi
    echo -e "${GREEN}=> Xin chứng chỉ SSL thành công!${NC}"
fi


# --- CÁC BƯỚC CÒN LẠI GIỮ NGUYÊN ---
# ...
# 4. XỬ LÝ MẠNG DOCKER THÔNG MINH
# 5. TẠO TỆP CẤU HÌNH
# 6. TRIỂN KHAI HỆ THỐNG
# 7. HƯỚNG DẪN CUỐI CÙNG
# ...
# --- 4. XỬ LÝ MẠNG DOCKER THÔNG MINH ---
echo "------------------------------------------------------------------"
echo "=> Kiểm tra và xử lý mạng Docker..."
DETECTED_NETWORK=$(docker inspect -f '{{range $key, $value := .NetworkSettings.Networks}}{{$key}}{{end}}' "${POSTGRES_CONTAINER_NAME}")
if [[ "$DETECTED_NETWORK" == "bridge" ]]; then
    echo -e "${YELLOW}Cảnh báo: Container PostgreSQL đang sử dụng mạng 'bridge' mặc định.${NC}"
    DOCKER_NETWORK_NAME="letta-net"
    echo -e "${YELLOW}Tự động tạo/sử dụng mạng '${DOCKER_NETWORK_NAME}' và kết nối container vào đó.${NC}"
    if ! sudo docker network inspect "$DOCKER_NETWORK_NAME" &> /dev/null; then
        sudo docker network create "$DOCKER_NETWORK_NAME"
    fi
    if ! sudo docker inspect "${POSTGRES_CONTAINER_NAME}" | grep -q "\"NetworkID\": \"$(sudo docker network inspect -f '{{.Id}}' "$DOCKER_NETWORK_NAME")\""; then
        sudo docker network connect "$DOCKER_NETWORK_NAME" "${POSTGRES_CONTAINER_NAME}"
        echo -e "${GREEN}=> Đã kết nối container '${POSTGRES_CONTAINER_NAME}' vào mạng '${DOCKER_NETWORK_NAME}'.${NC}"
    fi
else
    DOCKER_NETWORK_NAME="$DETECTED_NETWORK"
fi
echo -e "=> Sử dụng mạng cuối cùng: ${GREEN}${DOCKER_NETWORK_NAME}${NC}"

# --- 5. TẠO TỆP CẤU HÌNH ---
echo "------------------------------------------------------------------"
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

# --- 6. TRIỂN KHAI HỆ THỐNG ---
echo "------------------------------------------------------------------"
echo -e "${YELLOW}Chuẩn bị khởi chạy các container...${NC}"
echo "=> Đang làm sạch tệp compose.yaml để đảm bảo tương thích..."
sed -i 's/\r$//' compose.yaml
sudo docker compose -f compose.yaml down --remove-orphans > /dev/null 2>&1
sudo docker compose -f compose.yaml up -d --force-recreate --remove-orphans

# --- 7. HƯỚNG DẪN CUỐI CÙNG ---
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
echo "Để xem log, sử dụng lệnh: cd letta-server && sudo docker compose logs -f"
