#!/bin/bash

#------------------------------------------------------------------
# KỊCH BẢN CÀI ĐẶT TỰ ĐỘNG FULL-STACK (v12.0 - Final Merged)
# Tác giả: Ticmiro
# Chức năng:
# - Hợp nhất toàn bộ tính năng từ các kịch bản trước.
# - Cài đặt tùy chọn: PostgreSQL, Puppeteer, Crawl4AI, và Letta AI (có HTTPS).
# - Tự động hóa toàn bộ, từ cài đặt Docker đến triển khai dịch vụ.
#------------------------------------------------------------------

# --- Tiện ích & Bảng Tác giả ---
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; CYAN='\033[0;36m'
echo -e "${CYAN}####################################################################${NC}"
echo -e "${CYAN}#      KỊCH BẢN CÀI ĐẶT TỰ ĐỘNG HỆ SINH THÁI DỊCH VỤ VPS      #${NC}"
echo -e "${CYAN}# Tác giả: Ticmiro - https://github.com/Ticmiro                  #${NC}"
echo -e "${CYAN}####################################################################${NC}"
echo ""

# Dừng lại ngay lập tức nếu có bất kỳ lệnh nào thất bại
set -e

# --- 0. KIỂM TRA VÀ CÀI ĐẶT DOCKER ---
if ! [ -x "$(command -v docker)" ]; then
  echo -e "${YELLOW}Docker chưa được cài đặt. Bắt đầu cài đặt tự động...${NC}"
  sudo apt-get update -y
  sudo apt-get install -y ca-certificates curl gnupg
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo systemctl start docker
  sudo systemctl enable docker
else
  echo -e "${GREEN}Docker đã được cài đặt. Bỏ qua bước cài đặt.${NC}"
fi

# --- 1. HỎI NGƯỜI DÙNG VỀ CÁC DỊCH VỤ CẦN CÀI ĐẶT ---
echo "------------------------------------------------------------------"
echo -e "${GREEN}Vui lòng chọn các dịch vụ bạn muốn cài đặt:${NC}"
read -p "  - Cài đặt PostgreSQL + pgvector? (y/n): " INSTALL_POSTGRES
read -p "  - Cài đặt Dịch vụ API Puppeteer? (y/n): " INSTALL_PUPPETEER
read -p "  - Cài đặt Dịch vụ API Crawl4AI (có VNC)? (y/n): " INSTALL_CRAWL4AI
read -p "  - Cài đặt Dịch vụ Letta AI (có HTTPS)? (y/n): " INSTALL_LETTA

# --- 2. THU THẬP THÔNG TIN CẤU HÌNH ---
echo "------------------------------------------------------------------"
echo -e "${YELLOW}Vui lòng cung cấp các thông tin cấu hình cần thiết:${NC}"

# Khởi tạo các biến
POSTGRES_USER=""
POSTGRES_PASSWORD=""
POSTGRES_DB=""
PUPPETEER_PORT=""
CRAWL4AI_PORT=""
CRAWL4AI_VNC_PASSWORD=""
CRAWL4AI_API_KEY=""
LETTA_DOMAIN=""
LETSENCRYPT_EMAIL=""
OPENAI_API_KEY=""
LETTA_API_KEY=""

if [[ $INSTALL_POSTGRES == "y" || ($INSTALL_LETTA == "y" && -z "$POSTGRES_USER") ]]; then
    read -p "Nhập tên user cho database PostgreSQL: " POSTGRES_USER
    read -s -p "Nhập mật khẩu cho database PostgreSQL: " POSTGRES_PASSWORD && echo
    read -p "Nhập tên cho database PostgreSQL: " POSTGRES_DB
fi
if [[ $INSTALL_PUPPETEER == "y" ]]; then
    read -p "Nhập cổng cho Puppeteer API (ví dụ: 3000): " PUPPETEER_PORT
fi
if [[ $INSTALL_CRAWL4AI == "y" ]]; then
    read -p "Nhập OpenAI API Key (dùng cho Crawl4AI): " OPENAI_API_KEY
    read -p "Tạo và nhập một API Key cho dịch vụ Crawl4AI: " CRAWL4AI_API_KEY
    read -s -p "Tạo mật khẩu cho VNC của Crawl4AI: " CRAWL4AI_VNC_PASSWORD && echo
    read -p "Nhập cổng cho Crawl4AI API (ví dụ: 8000): " CRAWL4AI_PORT
fi
if [[ $INSTALL_LETTA == "y" ]]; then
    read -p "Nhập tên miền cho Letta AI (ví dụ: letta.yourdomain.com): " LETTA_DOMAIN
    read -p "Nhập email của bạn (dùng cho chứng chỉ SSL): " LETSENCRYPT_EMAIL
    if [[ -z "$OPENAI_API_KEY" ]]; then
        read -p "Nhập OpenAI API Key (cần cho Letta AI): " OPENAI_API_KEY
    fi
    read -p "Tạo và nhập một Letta API Key: " LETTA_API_KEY
    if [[ -z "$POSTGRES_USER" ]]; then
        echo "Letta AI yêu cầu database. Vui lòng cung cấp thông tin PostgreSQL:"
        read -p "Nhập tên user cho database PostgreSQL: " POSTGRES_USER
        read -s -p "Nhập mật khẩu cho database PostgreSQL: " POSTGRES_PASSWORD && echo
        read -p "Nhập tên cho database PostgreSQL: " POSTGRES_DB
    fi
fi

# --- 3. CÀI ĐẶT HTTPS CHO LETTA AI (NẾU CẦN) ---
if [[ $INSTALL_LETTA == "y" ]]; then
    echo "------------------------------------------------------------------"
    echo -e "${YELLOW}Bắt đầu quá trình cài đặt HTTPS cho Letta AI...${NC}"
    if ! [ -x "$(command -v certbot)" ]; then sudo apt-get update -y && sudo apt-get install -y certbot; fi
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

if [[ $INSTALL_PUPPETEER == "y" ]]; then
    echo "=> Đang tạo các tệp cho Dịch vụ Puppeteer..."
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
{ "name": "puppeteer-n8n-server", "version": "1.0.0", "description": "A Puppeteer server for n8n.", "main": "index.js", "scripts": { "start": "node index.js" }, "dependencies": { "express": "^4.19.2", "puppeteer": "^22.12.1" } }
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
    console.log(`Nhận yêu cầu: action='${action}' cho url='${url}'`);
    let browser = null;
    try {
        const launchOptions = { headless: true, args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage', '--disable-gpu'] };
        if (options.proxy) { console.log(`Đang sử dụng proxy: ${options.proxy}`); launchOptions.args.push(`--proxy-server=${options.proxy}`); }
        browser = await puppeteer.launch(launchOptions);
        const page = await browser.newPage();
        await page.setViewport({ width: 1920, height: 1080 });
        await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36');
        await page.goto(url, { waitUntil: 'networkidle2', timeout: 60000 });
        if (options.waitForSelector) { console.log(`Đang chờ selector: "${options.waitForSelector}"`); await page.waitForSelector(options.waitForSelector, { timeout: 30000 }); }
        if (options.humanlike_scroll) {
            console.log('Thực hiện hành vi giống người: Cuộn trang...');
            await page.evaluate(async () => { await new Promise((resolve) => { let totalHeight = 0; const distance = 100; const timer = setInterval(() => { const scrollHeight = document.body.scrollHeight; window.scrollBy(0, distance); totalHeight += distance; if (totalHeight >= scrollHeight) { clearInterval(timer); resolve(); } }, 200); }); });
            console.log('Đã cuộn xong trang.');
        }
        switch (action) {
            case 'scrapeWithSelectors':
                if (!options.selectors || Object.keys(options.selectors).length === 0) throw new Error('Hành động "scrapeWithSelectors" yêu cầu "selectors" trong options');
                const scrapedData = await page.evaluate((selectors) => { const results = {}; for (const key in selectors) { const element = document.querySelector(selectors[key]); results[key] = element ? element.innerText.trim() : null; } return results; }, options.selectors);
                console.log('Cào dữ liệu với selectors tùy chỉnh thành công.'); res.status(200).json(scrapedData); break;
            case 'screenshot':
                 const imageBuffer = await page.screenshot({ fullPage: true, encoding: 'base64' });
                 console.log('Chụp ảnh màn hình thành công.'); res.status(200).json({ screenshot_base64: imageBuffer }); break;
            default: throw new Error(`Action không hợp lệ: ${action}`);
        }
    } catch (error) { console.error(`Lỗi khi thực hiện action '${action}':`, error); res.status(500).json({ error: 'Failed to process request.', details: error.message });
    } finally { if (browser) await browser.close(); }
});
app.listen(port, () => console.log(`Puppeteer server đã sẵn sàng tại http://localhost:${port}`));
EOF
fi

if [[ $INSTALL_CRAWL4AI == "y" ]]; then
    echo "=> Đang cài đặt các tiện ích VNC trên máy chủ..."
    sudo apt-get update -y && sudo apt-get install -y xfce4 xfce4-goodies dbus-x11 tigervnc-standalone-server
    mkdir -p ~/.vnc
    echo "$CRAWL4AI_VNC_PASSWORD" | vncpasswd -f > ~/.vnc/passwd
    chmod 600 ~/.vnc/passwd
    cat <<'EOF' > ~/.vnc/xstartup
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startxfce4
EOF
    chmod +x ~/.vnc/xstartup
    echo "=> Đang tạo các tệp cho Dịch vụ Crawl4AI..."
    mkdir -p crawl4ai-api
    cat <<'EOF' > crawl4ai-api/Dockerfile
FROM python:3.10-slim
WORKDIR /app
COPY requirements.txt .
# Sửa lỗi: Cài đặt các phụ thuộc hệ thống thủ công và thay thế gói phông chữ.
RUN apt-get update && apt-get install -y \
    fontconfig \
    libharfbuzz0b \
    libxtst6 \
    libnss3 \
    libgtk-3-0 \
    libasound2 \
    fonts-unifont \
    && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir -r requirements.txt
RUN playwright install chromium
COPY . .
EXPOSE 8000
CMD ["uvicorn", "api_server:app", "--host", "0.0.0.0", "--port", "8000"]
EOF
    cat <<'EOF' > crawl4ai-api/requirements.txt
crawl4ai
fastapi
uvicorn[standard]
python-dotenv
colorama
EOF
    cat <<EOF > crawl4ai-api/.env
OPENAI_API_KEY="${OPENAI_API_KEY}"
CRAWL_API_KEY="${CRAWL4AI_API_KEY}"
EOF
    cat <<'EOF' > crawl4ai-api/create_profile.py
import asyncio, os
from crawl4ai.browser_profiler import BrowserProfiler
from crawl4ai.async_logger import AsyncLogger
async def main():
    logger = AsyncLogger(verbose=True)
    profiler = BrowserProfiler(logger=logger)
    print("--- Trình tạo Profile Đăng nhập ---")
    print("QUAN TRỌNG: Bạn cần có VNC hoặc một giao diện đồ họa để thấy và tương tác với trình duyệt sắp mở ra.")
    await profiler.interactive_manager()
if __name__ == "__main__": asyncio.run(main())
EOF
    cat <<'EOF' > crawl4ai-api/api_server.py
import os, signal, asyncio
from typing import Optional, List
from fastapi import FastAPI, HTTPException, Header, Depends
from fastapi.responses import Response
from pydantic import BaseModel
from crawl4ai import AsyncWebCrawler
from crawl4ai.async_configs import BrowserConfig, CrawlerRunConfig
from crawl4ai.browser_profiler import BrowserProfiler
from dotenv import load_dotenv
load_dotenv(); app = FastAPI()
async def verify_api_key(x_api_key: Optional[str] = Header(None)):
    SECRET_KEY = os.getenv("CRAWL_API_KEY")
    if not SECRET_KEY: raise HTTPException(status_code=500, detail="API Key not configured")
    if x_api_key != SECRET_KEY: raise HTTPException(status_code=401, detail="Unauthorized")
crawler_lock = asyncio.Lock()
class CrawlRequest(BaseModel): url: str
class ScreenshotRequest(BaseModel): url: str; full_page: bool = True
class ProfileCrawlRequest(BaseModel): url: str; profile_name: str
@app.post("/crawl", dependencies=[Depends(verify_api_key)])
async def simple_crawl(request: CrawlRequest):
    async with crawler_lock:
        try:
            async with AsyncWebCrawler(config=BrowserConfig(headless=True, verbose=False)) as crawler:
                result = await crawler.arun(url=request.url)
                if result.success: return {"success": True, "url": result.url, "markdown": result.markdown.raw_markdown, "metadata": result.metadata}
                raise HTTPException(status_code=400, detail=f"Crawl failed: {result.error_message}")
        except Exception as e: raise HTTPException(status_code=500, detail=str(e))
@app.post("/screenshot", response_class=Response, dependencies=[Depends(verify_api_key)])
async def take_screenshot(request: ScreenshotRequest):
    async with crawler_lock:
        try:
            async with AsyncWebCrawler(config=BrowserConfig(headless=True, verbose=False)) as crawler:
                result = await crawler.arun(url=request.url, config=CrawlerRunConfig(screenshot={"full_page": request.full_page}))
                if result.success and result.screenshot: return Response(content=result.screenshot, media_type="image/png")
                raise HTTPException(status_code=400, detail="Failed to take screenshot.")
        except Exception as e: raise HTTPException(status_code=500, detail=str(e))
@app.post("/crawl-with-profile", dependencies=[Depends(verify_api_key)])
async def crawl_with_profile(request: ProfileCrawlRequest):
    async with crawler_lock:
        profiler = BrowserProfiler()
        profile_path = profiler.get_profile_path(request.profile_name)
        if not profile_path or not os.path.exists(profile_path): raise HTTPException(status_code=404, detail=f"Profile '{request.profile_name}' not found.")
        try:
            async with AsyncWebCrawler(config=BrowserConfig(headless=True, verbose=False, user_data_dir=profile_path)) as crawler:
                result = await crawler.arun(url=request.url, config=CrawlerRunConfig(js_code="await new Promise(resolve => setTimeout(resolve, 5000)); return true;"))
                if result.success: return {"success": True, "url": result.url, "markdown": result.markdown.raw_markdown, "metadata": result.metadata}
                raise HTTPException(status_code=400, detail=f"Crawl failed: {result.error_message}")
        except Exception as e: raise HTTPException(status_code=500, detail=str(e))
@app.post("/restart", dependencies=[Depends(verify_api_key)])
async def restart_server():
    print("INFO: Received authenticated restart request. Shutting down...")
    os.kill(os.getpid(), signal.SIGINT); return {"message": "Server is restarting..."}
EOF
fi

if [[ $INSTALL_LETTA == "y" ]]; then
    echo "=> Đang tạo các tệp cho Dịch vụ Letta AI..."
    mkdir -p letta_config
    cat <<EOF > letta_config/.env
OPENAI_API_KEY="${OPENAI_API_KEY}"
LETTA_API_KEY="${LETTA_API_KEY}"
POSTGRES_USER="${POSTGRES_USER}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"
POSTGRES_DB="${POSTGRES_DB}"
EOF
    cat <<EOF > letta_config/nginx.conf
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
    # Sửa lỗi: Tạo file init.sql để kích hoạt pgvector
    cat <<'EOF' > init.sql
CREATE EXTENSION IF NOT EXISTS vector;
EOF
fi

# --- 5. TẠO TỆP DOCKER-COMPOSE.YML HOÀN CHỈNH ---
echo "=> Tạo tệp docker-compose.yml tổng hợp..."
echo "version: '3.8'" > docker-compose.yml
echo "services:" >> docker-compose.yml

if [[ $INSTALL_POSTGRES == "y" || $INSTALL_LETTA == "y" ]]; then
cat <<EOF >> docker-compose.yml
  postgres_db:
    image: pgvector/pgvector:pg16
    container_name: main_postgres_db
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    volumes:
      - main_postgres_data:/var/lib/postgresql/data
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql
    networks:
      - main-network
    restart: always
EOF
fi
if [[ $INSTALL_PUPPETEER == "y" ]]; then
cat <<EOF >> docker-compose.yml
  puppeteer_api:
    build: ./puppeteer-api
    container_name: puppeteer_api
    ports: ["${PUPPETEER_PORT:-3000}:3000"]
    networks: [main-network]
    restart: always
EOF
fi
if [[ $INSTALL_CRAWL4AI == "y" ]]; then
cat <<EOF >> docker-compose.yml
  crawl4ai_api:
    build: ./crawl4ai-api
    container_name: crawl4ai_api
    init: true
    ports:
      - "${CRAWL4AI_PORT:-8000}:8000"
    env_file:
      - ./crawl4ai-api/.env
    shm_size: '2g'
    environment:
      - DISPLAY=:1
    volumes:
      - ./crawl4ai_output:/app/output
      - crawler-profiles:/root/.crawl4ai/profiles
      - /tmp/.X11-unix:/tmp/.X11-unix
      - /var/run/dbus:/var/run/dbus
    networks:
      - main-network
    restart: unless-stopped
EOF
fi
if [[ $INSTALL_LETTA == "y" ]]; then
cat <<EOF >> docker-compose.yml
  letta_server:
    image: letta/letta:latest
    container_name: letta_api_server
    restart: unless-stopped
    env_file: ./letta_config/.env
    environment:
      - LETTA_PG_URI=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@main_postgres_db:5432/${POSTGRES_DB}
    networks: [main-network]
    depends_on:
      - postgres_db
  letta_nginx:
    image: nginx:stable-alpine
    container_name: letta_nginx_proxy
    restart: unless-stopped
    volumes: ["./letta_config/nginx.conf:/etc/nginx/nginx.conf", "/etc/letsencrypt:/etc/letsencrypt:ro", "/var/www/certbot:/var/www/certbot:ro"]
    ports: ["80:80", "443:443"]
    networks: [main-network]
    depends_on: [letta_server]
EOF
fi

cat <<EOF >> docker-compose.yml

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
sudo docker compose -f docker-compose.yml up -d --build

echo "------------------------------------------------------------------"
echo -e "${GREEN}🚀 Hoàn tất!${NC}"
echo "Các dịch vụ bạn chọn đã được triển khai thành công."
echo ""
echo -e "${YELLOW}##################################################################"
echo -e "${YELLOW}#                                                                #"
echo -e "${YELLOW}#    THÔNG TIN QUAN TRỌNG - HÃY LƯU LẠI NGAY LẬP TỨC           #"
echo -e "${YELLOW}#                                                                #"
echo -e "${YELLOW}##################################################################${NC}"
echo ""
echo "Các thông tin đăng nhập và API key này sẽ KHÔNG được hiển thị lại."
echo "Hãy sao chép và cất giữ ở nơi an toàn TRƯỚC KHI đóng cửa sổ terminal này."
echo ""

PUBLIC_IP=$(curl -s ifconfig.me)

if [[ $INSTALL_POSTGRES == "y" || $INSTALL_LETTA == "y" ]]; then
echo -e "${GREEN}--- 🐘 Thông tin kết nối PostgreSQL ---${NC}"
echo -e "  Host:             ${PUBLIC_IP}"
echo -e "  Port:             (Cổng nội bộ, truy cập qua tên dịch vụ 'main_postgres_db')"
echo -e "  Database:         ${POSTGRES_DB}"
echo -e "  User:             ${POSTGRES_USER}"
echo -e "  Password:         ${RED}(đã ẩn, là mật khẩu bạn đã nhập)${NC}"
echo ""
fi

if [[ $INSTALL_PUPPETEER == "y" ]]; then
echo -e "${GREEN}--- 📷 Thông tin API Puppeteer ---${NC}"
echo -e "  Endpoint:         http://${PUBLIC_IP}:${PUPPETEER_PORT:-3000}/scrape"
echo -e "  Method:           POST"
echo ""
fi

if [[ $INSTALL_CRAWL4AI == "y" ]]; then
echo -e "${GREEN}--- 🕷️ Thông tin API Crawl4AI ---${NC}"
echo -e "  Endpoint:         http://${PUBLIC_IP}:${CRAWL4AI_PORT:-8000}"
echo -e "  Header Name:      x-api-key"
echo -e "  Header Value:     ${RED}${CRAWL4AI_API_KEY}${NC}"
echo ""
fi

if [[ $INSTALL_LETTA == "y" ]]; then
echo -e "${GREEN}--- ✨ Thông tin API Letta AI ---${NC}"
echo -e "  Endpoint:         https://${LETTA_DOMAIN}"
echo -e "  Header Name:      Authorization"
echo -e "  Header Value:     Bearer ${RED}${LETTA_API_KEY}${NC}"
echo ""
fi

if [[ $INSTALL_CRAWL4AI == "y" ]]; then
    echo ""
    echo -e "${YELLOW}VIỆC CẦN LÀM (CHO CRAWL4AI): TẠO PROFILE ĐĂNG NHẬP${NC}"
    echo "1. Khởi động VNC Server:"
    echo -e "   - Chạy lệnh: ${YELLOW}vncserver -localhost no :1${NC}"
    echo -e "   - Mở cổng firewall: ${YELLOW}sudo ufw allow 5901/tcp${NC}"
    echo "2. Kết nối vào VPS bằng VNC Viewer (Địa chỉ: ${PUBLIC_IP}:1)."
    echo "3. Mở Terminal Emulator bên trong màn hình VNC và chạy:"
    echo -e "   ${YELLOW}xhost +${NC}"
    echo -e "   ${YELLOW}sudo docker exec -it crawl4ai_api python create_profile.py${NC}"
    echo "4. Đăng nhập vào trang web qua trình duyệt hiện ra, sau đó nhấn 'q' trong terminal để lưu."
fi

echo ""
echo "Để xem log của toàn bộ hệ thống, chạy lệnh: ${YELLOW}cd full-stack-app && sudo docker compose logs -f${NC}"
echo "=================================================================="