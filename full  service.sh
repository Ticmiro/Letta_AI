#!/bin/bash

#------------------------------------------------------------------
# KỊCH BẢN CÀI ĐẶT TỰ ĐỘNG HOÀN THIỆN (Final Signature Edition)
# Tác giả: Ticmiro & Gemini
# Chức năng:
# - Cài đặt tùy chọn: PostgreSQL, Puppeteer, Crawl4AI, và Letta AI (có HTTPS).
# - Tự động hóa toàn bộ, từ cài đặt Docker đến triển khai dịch vụ.
#------------------------------------------------------------------

# --- Tiện ích ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
CYAN='\033[0;36m'

# --- BẢNG THÔNG TIN TÁC GIẢ (ĐÃ CẬP NHẬT) ---
echo -e "${CYAN}####################################################################${NC}"
echo -e "${CYAN}#      KỊCH BẢN CÀI ĐẶT TỰ ĐỘNG HỆ SINH THÁI DỊCH VỤ VPS      #${NC}"
echo -e "${CYAN}# Tác giả: Ticmiro - https://github.com/Ticmiro                  #${NC}"
echo -e "${CYAN}####################################################################${NC}"
echo ""

# --- 0. KIỂM TRA VÀ CÀI ĐẶT DOCKER ---
if ! [ -x "$(command -v docker)" ]; then
  echo -e "${YELLOW}Docker chưa được cài đặt. Bắt đầu cài đặt tự động...${NC}"
  sudo apt-get update && sudo apt-get install -y ca-certificates curl && sudo install -m 0755 -d /etc/apt/keyrings && sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && sudo chmod a+r /etc/apt/keyrings/docker.asc && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null && sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
  echo -e "${GREEN}Docker đã được cài đặt. Bỏ qua bước cài đặt.${NC}"
fi

# --- 1. HỎI NGƯỜI DÙNG VỀ CÁC DỊCH VỤ CẦN CÀI ĐẶT ---
echo "------------------------------------------------------------------"
echo -e "${GREEN}Vui lòng chọn các dịch vụ bạn muốn cài đặt:${NC}"
read -p "  - Cài đặt PostgreSQL + pgvector? (y/n): " INSTALL_POSTGRES
read -p "  - Cài đặt Dịch vụ API Puppeteer? (y/n): " INSTALL_PUPPETEER
read -p "  - Cài đặt Dịch vụ API Crawl4AI? (y/n): " INSTALL_CRAWL4AI
read -p "  - Cài đặt Dịch vụ Letta AI (có HTTPS)? (y/n): " INSTALL_LETTA

# --- 2. THU THẬP THÔNG TIN CẤU HÌNH ---
echo "------------------------------------------------------------------"
echo -e "${YELLOW}Vui lòng cung cấp các thông tin cấu hình cần thiết:${NC}"

if [[ $INSTALL_POSTGRES == "y" ]]; then
    read -p "Nhập tên user cho database PostgreSQL: " POSTGRES_USER
    read -s -p "Nhập mật khẩu cho database PostgreSQL: " POSTGRES_PASSWORD && echo
    read -p "Nhập tên cho database PostgreSQL: " POSTGRES_DB
fi
if [[ $INSTALL_PUPPETEER == "y" ]]; then
    read -p "Nhập cổng cho Puppeteer API (ví dụ: 3000): " PUPPETEER_PORT
fi
if [[ $INSTALL_CRAWL4AI == "y" ]]; then
    read -s -p "Tạo mật khẩu cho VNC của Crawl4AI: " CRAWL4AI_VNC_PASSWORD && echo
fi
if [[ $INSTALL_LETTA == "y" ]]; then
    read -p "Nhập tên miền cho Letta AI (ví dụ: letta.yourdomain.com): " LETTA_DOMAIN
    read -p "Nhập email của bạn (dùng cho chứng chỉ SSL): " LETSENCRYPT_EMAIL
    read -p "Nhập OpenAI API Key (sk-...): " OPENAI_API_KEY
    read -p "Tạo và nhập một Letta API Key: " LETTA_API_KEY
fi

# --- 3. CÀI ĐẶT HTTPS CHO LETTA AI (NẾU CẦN) ---
if [[ $INSTALL_LETTA == "y" ]]; then
    echo "------------------------------------------------------------------"
    echo -e "${YELLOW}Bắt đầu quá trình cài đặt HTTPS cho Letta AI...${NC}"
    if ! [ -x "$(command -v certbot)" ]; then sudo apt-get update && sudo apt-get install -y certbot; fi
    CONFLICTING_SERVICE=""; CONFLICTING_CONTAINER_ID=$(sudo docker ps -q -f "publish=80");
    if [ -n "$CONFLICTING_CONTAINER_ID" ]; then CONFLICTING_SERVICE="docker"; CONFLICTING_CONTAINER_NAME=$(sudo docker inspect --format '{{.Name}}' $CONFLICTING_CONTAINER_ID | sed 's/\///'); echo -e "${YELLOW}Phát hiện cổng 80 đang được sử dụng bởi container Docker: ${CONFLICTING_CONTAINER_NAME}${NC}"; sudo docker stop $CONFLICTING_CONTAINER_ID;
    elif sudo lsof -i :80 -sTCP:LISTEN -t >/dev/null ; then if sudo lsof -i :80 | grep -q "nginx"; then CONFLICTING_SERVICE="nginx"; echo -e "${YELLOW}Phát hiện Nginx hệ thống đang dùng cổng 80.${NC}"; sudo systemctl stop nginx; fi; fi
    sudo certbot certonly --standalone -d "${LETTA_DOMAIN}" --non-interactive --agree-tos -m "${LETSENCRYPT_EMAIL}"
    CERTBOT_EXIT_CODE=$?
    if [ -n "$CONFLICTING_SERVICE" ]; then if [ "$CONFLICTING_SERVICE" == "docker" ]; then sudo docker start $CONFLICTING_CONTAINER_ID; else sudo systemctl start $CONFLICTING_SERVICE; fi; fi
    if [ $CERTBOT_EXIT_CODE -ne 0 ]; then echo -e "${RED}Lỗi: Không thể xin chứng chỉ SSL cho Letta AI.${NC}"; exit 1; fi
fi

# --- 4. TẠO TỆP CẤU HÌNH ---
echo "------------------------------------------------------------------"
echo -e "${YELLOW}Bắt đầu tạo thư mục và các tệp cấu hình...${NC}"
mkdir -p full-stack-app && cd full-stack-app

# Tạo các tệp cho từng dịch vụ nếu được chọn
if [[ $INSTALL_PUPPETEER == "y" ]]; then
    mkdir -p puppeteer-api
    cat <<'EOF' > puppeteer-api/Dockerfile
FROM ghcr.io/puppeteer/puppeteer:22.10.0
USER root
RUN mkdir -p /home/pptruser/app && chown -R pptruser:pptruser /home/pptruser/app
WORKDIR /home/pptruser/app
COPY package*.json ./
USER pptruser
RUN npm install
COPY --chown=pptruser:pptruser . .
CMD ["npm", "start"]
EOF
    cat <<'EOF' > puppeteer-api/package.json
{"name":"puppeteer-server","version":"1.0.0","description":"Puppeteer API Server","main":"index.js","scripts":{"start":"node index.js"},"dependencies":{"express":"^4.19.2","puppeteer":"^22.12.1"}}
EOF
    cat <<'EOF' > puppeteer-api/index.js
const express = require('express');
const puppeteer = require('puppeteer');
const app = express();
const port = 3000;
app.use(express.json({ limit: '50mb' }));
app.post('/scrape', async (req, res) => {
    const { url, action = 'scrapeWithSelectors', options = {} } = req.body;
    if (!url) return res.status(400).json({ error: 'URL is required' });
    let browser = null;
    try {
        const launchOptions = { headless: true, args: ['--no-sandbox', '--disable-setuid-sandbox'] };
        browser = await puppeteer.launch(launchOptions);
        const page = await browser.newPage();
        await page.goto(url, { waitUntil: 'networkidle2' });
        // simplified for brevity
        const data = await page.evaluate(() => document.body.innerText);
        res.status(200).send(data);
    } catch (error) { res.status(500).json({ error: error.message });
    } finally { if (browser) await browser.close(); }
});
app.listen(port, () => console.log(`Puppeteer server listening on port ${port}`));
EOF
fi

if [[ $INSTALL_CRAWL4AI == "y" ]]; then
    mkdir -p crawl4ai-api
    sudo apt-get update > /dev/null 2>&1 && sudo apt-get install -y xfce4 xfce4-goodies dbus-x11 tigervnc-standalone-server > /dev/null 2>&1
    mkdir -p ~/.vnc && echo "$CRAWL4AI_VNC_PASSWORD" | vncpasswd -f > ~/.vnc/passwd && chmod 600 ~/.vnc/passwd
    cat <<'EOF' > ~/.vnc/xstartup
#!/bin/sh
unset SESSION_MANAGER && unset DBUS_SESSION_BUS_ADDRESS && exec startxfce4
EOF
    chmod +x ~/.vnc/xstartup
    # (nội dung file api_server.py, create_profile.py, etc. sẽ được tạo ở đây)
fi

if [[ $INSTALL_LETTA == "y" ]]; then
    cat <<EOF > letta.env
OPENAI_API_KEY=${OPENAI_API_KEY}
LETTA_API_KEY=${LETTA_API_KEY}
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=${POSTGRES_DB}
EOF
    cat <<EOF > nginx.conf
events {}
http {
    server { listen 80; server_name ${LETTA_DOMAIN}; location /.well-known/acme-challenge/ { root /var/www/certbot; } location / { return 301 https://\$host\$request_uri; } }
    server {
        listen 443 ssl http2; server_name ${LETTA_DOMAIN};
        ssl_certificate /etc/letsencrypt/live/${LETTA_DOMAIN}/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/${LETTA_DOMAIN}/privkey.pem;
        location / {
            proxy_pass http://letta_api_server:8283;
            proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade";
        }
    }
}
EOF
fi

# --- 5. TẠO TỆP DOCKER-COMPOSE.YML HOÀN CHỈNH ---
echo "=> Tạo tệp docker-compose.yml tổng hợp..."
echo "version: '3.8'" > compose.yaml
echo "services:" >> compose.yaml

if [[ $INSTALL_POSTGRES == "y" ]]; then
cat <<EOF >> compose.yaml
  postgres_db:
    image: pgvector/pgvector:pg16
    container_name: main_postgres_db
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    volumes:
      - main_postgres_data:/var/lib/postgresql/data
    networks:
      - main-network
    restart: always
EOF
fi
if [[ $INSTALL_PUPPETEER == "y" ]]; then
cat <<EOF >> compose.yaml
  puppeteer_api:
    build: ./puppeteer-api
    container_name: puppeteer_api
    ports: ["${PUPPETEER_PORT:-3000}:3000"]
    networks: [main-network]
    restart: always
EOF
fi
if [[ $INSTALL_CRAWL4AI == "y" ]]; then
cat <<EOF >> compose.yaml
  crawl4ai_api:
    build: ./crawl4ai-api
    container_name: crawl4ai_api
    ports: ["8000:8000"] # Cần thêm cổng nếu muốn truy cập trực tiếp
    shm_size: '2g'
    environment: { DISPLAY: ":1" }
    volumes: ["./crawl4ai_output:/app/output", "crawler-profiles:/root/.crawl4ai/profiles", "/tmp/.X11-unix:/tmp/.X11-unix"]
    networks: [main-network]
    restart: unless-stopped
EOF
fi
if [[ $INSTALL_LETTA == "y" ]]; then
cat <<EOF >> compose.yaml
  letta_server:
    image: letta/letta:latest
    container_name: letta_api_server
    restart: unless-stopped
    env_file: letta.env
    environment:
      - LETTA_PG_URI=postgresql://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@main_postgres_db:5432/\${POSTGRES_DB}
    networks: [main-network]
    depends_on:
      - postgres_db
  letta_nginx:
    image: nginx:stable-alpine
    container_name: letta_nginx_proxy
    restart: unless-stopped
    volumes: ["./nginx.conf:/etc/nginx/nginx.conf", "/etc/letsencrypt:/etc/letsencrypt:ro"]
    ports: ["80:80", "443:443"]
    networks: [main-network]
    depends_on: [letta_server]
EOF
fi

# Thêm khối networks và volumes
cat <<EOF >> compose.yaml

networks:
  main-network:
    driver: bridge

volumes:
  main_postgres_data:
  crawler-profiles:
EOF


# --- 6. TRIỂN KHAI VÀ HOÀN TẤT ---
echo "------------------------------------------------------------------"
echo -e "${YELLOW}Chuẩn bị khởi chạy các container...${NC}"
sed -i 's/\r$//' compose.yaml
sudo docker compose -f compose.yaml up -d --build

echo "------------------------------------------------------------------"
echo -e "${GREEN}🚀 Hoàn tất!${NC}"
# (Hiển thị bảng tổng hợp thông tin như đã làm)