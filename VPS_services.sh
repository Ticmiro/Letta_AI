#!/bin/bash

#------------------------------------------------------------------
# KỊCH BẢN CÀI ĐẶT TỰ ĐỘNG HOÀN THIỆN
# Tác giả: Ticmiro & Gemini
# Chức năng:
# - Cài đặt tùy chọn: PostgreSQL+pgvector, Puppeteer API, Crawl4AI API.
# - Sử dụng 100% mã nguồn và cấu hình đã được cung cấp.
# - Tự động hóa toàn bộ quá trình tạo tệp và triển khai Docker.
#------------------------------------------------------------------

# --- Tiện ích ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Dừng lại ngay lập tức nếu có bất kỳ lệnh nào thất bại
set -e

echo -e "${GREEN}Chào mừng đến với kịch bản cài đặt tự động hoàn thiện!${NC}"
echo "------------------------------------------------------------------"

# --- 1. HỎI NGƯỜI DÙNG VỀ CÁC DỊCH VỤ CẦN CÀI ĐẶT ---
read -p "Bạn có muốn cài đặt PostgreSQL + pgvector không? (y/n): " INSTALL_POSTGRES
read -p "Bạn có muốn cài đặt Dịch vụ API Puppeteer không? (y/n): " INSTALL_PUPPETEER
read -p "Bạn có muốn cài đặt Dịch vụ API Crawl4AI (có VNC) không? (y/n): " INSTALL_CRAWL4AI

# --- 2. THU THẬP CÁC THÔNG TIN CẤU HÌNH ---
echo -e "${YELLOW}Vui lòng cung cấp các thông tin cấu hình cần thiết:${NC}"

if [[ $INSTALL_POSTGRES == "y" ]]; then
    read -p "Nhập tên cho PostgreSQL User (ví dụ: myuser): " POSTGRES_USER
    read -s -p "Nhập mật khẩu cho PostgreSQL User: " POSTGRES_PASSWORD
    echo
    read -p "Nhập tên cho PostgreSQL Database (ví dụ: mydb): " POSTGRES_DB
    read -p "Nhập cổng cho PostgreSQL (ví dụ: 5432): " POSTGRES_PORT
fi

if [[ $INSTALL_PUPPETEER == "y" ]]; then
    read -p "Nhập cổng cho Puppeteer API (ví dụ: 3000): " PUPPETEER_PORT
fi

if [[ $INSTALL_CRAWL4AI == "y" ]]; then
    read -p "Nhập OpenAI API Key của bạn: " OPENAI_API_KEY
    read -p "Tạo và nhập một API Key cho dịch vụ Crawl4AI: " CRAWL_API_KEY
    read -s -p "Tạo mật khẩu cho VNC (để tạo profile): " VNC_PASSWORD
    echo
    read -p "Nhập cổng cho Crawl4AI API (ví dụ: 8000): " CRAWL4AI_PORT
fi

# --- 3. BẮT ĐẦU CÀI ĐẶT VÀ TẠO TỆP ---
echo "------------------------------------------------------------------"
echo -e "${YELLOW}Bắt đầu tạo tệp và cài đặt... Thao tác này có thể mất vài phút.${NC}"

# Tạo thư mục dự án chính
mkdir -p my-services-stack
cd my-services-stack

# Chuỗi để xây dựng docker-compose.yml động
DOCKER_COMPOSE_CONTENT="version: '3.8'

services:"

# --- Cấu hình cho PostgreSQL ---
if [[ $INSTALL_POSTGRES == "y" ]]; then
    echo "=> Đang cấu hình cho PostgreSQL..."
    DOCKER_COMPOSE_CONTENT+="
  postgres_db:
    image: pgvector/pgvector:pg16
    container_name: postgres_db
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - \"${POSTGRES_PORT:-5432}:5432\"
    networks:
      - my-app-network
    restart: always"
fi

# --- Cấu hình cho Dịch vụ Puppeteer ---
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
    DOCKER_COMPOSE_CONTENT+="
  puppeteer_api:
    build: ./puppeteer-api
    container_name: puppeteer_api
    ports:
      - \"${PUPPETEER_PORT}:3000\"
    networks:
      - my-app-network
    restart: always"
fi

# --- Cấu hình cho Dịch vụ Crawl4AI ---
if [[ $INSTALL_CRAWL4AI == "y" ]]; then
    echo "=> Đang cài đặt các tiện ích VNC trên máy chủ..."
    sudo apt-get update && sudo apt-get install -y xfce4 xfce4-goodies dbus-x11 tigervnc-standalone-server
    mkdir -p ~/.vnc
    echo "$VNC_PASSWORD" | vncpasswd -f > ~/.vnc/passwd
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
RUN pip install --no-cache-dir -r requirements.txt && playwright install --with-deps chromium
COPY . .
EXPOSE 8000
CMD ["uvicorn", "api_server:app", "--host", "0.0.0.0", "--port", "8000"]
EOF
    # SỬA LỖI Ở ĐÂY: Mỗi thư viện nằm trên một dòng riêng
    cat <<'EOF' > crawl4ai-api/requirements.txt
crawl4ai
fastapi
uvicorn[standard]
python-dotenv
colorama
EOF
    cat <<EOF > crawl4ai-api/.env
OPENAI_API_KEY="${OPENAI_API_KEY}"
CRAWL_API_KEY="${CRAWL_API_KEY}"
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
    DOCKER_COMPOSE_CONTENT+="
  crawl4ai_api:
    build: ./crawl4ai-api
    container_name: crawl4ai_api
    init: true
    ports:
      - \"${CRAWL4AI_PORT}:8000\"
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
      - my-app-network
    restart: unless-stopped"
fi

# --- Hoàn thiện docker-compose.yml ---
DOCKER_COMPOSE_CONTENT+="

networks:
  my-app-network:
    driver: bridge

volumes:
  postgres_data:
  crawler-profiles:"

# Ghi tệp docker-compose.yml cuối cùng
echo "=> Tạo tệp docker-compose.yml tổng hợp..."
echo -e "$DOCKER_COMPOSE_CONTENT" > docker-compose.yml

# --- 4. TRIỂN KHAI HỆ THỐNG ---
echo "------------------------------------------------------------------"
echo -e "${YELLOW}Bắt đầu build và khởi chạy các dịch vụ... Quá trình này có thể mất RẤT LÂU.${NC}"
sudo docker compose up -d --build

# --- 5. HƯỚNG DẪN CUỐI CÙNG ---
echo "=================================================================="
echo -e "${GREEN}🚀 CÀI ĐẶT HOÀN TẤT! 🚀${NC}"
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

if [[ $INSTALL_POSTGRES == "y" ]]; then
echo "--- 🐘 Thông tin kết nối PostgreSQL ---"
echo -e "  Host:           $(curl -s ifconfig.me)"
echo -e "  Port:           ${POSTGRES_PORT:-5432}"
echo -e "  Database:       ${POSTGRES_DB}"
echo -e "  User:           ${POSTGRES_USER}"
echo -e "  Password:       (đã ẩn)"
echo ""
fi

if [[ $INSTALL_PUPPETEER == "y" ]]; then
echo "---  puppeteer Thông tin API Puppeteer ---"
echo -e "  Endpoint:       http://$(curl -s ifconfig.me):${PUPPETEER_PORT}/scrape"
echo -e "  Method:         POST"
echo ""
fi

if [[ $INSTALL_CRAWL4AI == "y" ]]; then
echo "--- 🕷️ Thông tin API Crawl4AI ---"
echo -e "  Endpoint:       http://$(curl -s ifconfig.me):${CRAWL4AI_PORT}"
echo -e "  Header Name:    x-api-key"
echo -e "  Header Value:   ${CRAWL_API_KEY}"
echo ""
fi

if [[ $INSTALL_CRAWL4AI == "y" ]]; then
    echo ""
    echo -e "${YELLOW}VIỆC CẦN LÀM (CHO CRAWL4AI): TẠO PROFILE ĐĂNG NHẬP${NC}"
    echo "1. Khởi động VNC Server:"
    echo -e "   - Chạy lệnh: ${YELLOW}vncserver -localhost no :1${NC}"
    echo -e "   - Mở cổng firewall: ${YELLOW}sudo ufw allow 5901/tcp${NC}"
    echo "2. Kết nối vào VPS bằng VNC Viewer (Địa chỉ: $(curl -s ifconfig.me):1)."
    echo "3. Mở Terminal Emulator bên trong màn hình VNC và chạy:"
    echo -e "   ${YELLOW}xhost +${NC}"
    echo -e "   ${YELLOW}sudo docker exec -it crawl4ai_api python create_profile.py${NC}"
    echo "4. Đăng nhập vào trang web qua trình duyệt hiện ra, sau đó nhấn 'q' trong terminal để lưu."
fi

echo ""
echo "Để xem log của toàn bộ hệ thống, chạy lệnh: ${YELLOW}cd my-services-stack && sudo docker compose logs -f${NC}"
echo "=================================================================="