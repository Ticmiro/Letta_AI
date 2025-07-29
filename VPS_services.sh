#!/bin/bash

#------------------------------------------------------------------
# KỊCH BẢN CÀI ĐẶT TỰ ĐỘNG HOÀN THIỆN (v3.0 - Final Corrected)
# Tác giả: Ticmiro & Gemini
# Chức năng:
# - Giữ nguyên 100% mã nguồn gốc, dễ đọc.
# - Sửa lỗi "docker-compose command not found".
# - Thêm bảng tổng hợp thông tin đăng nhập và API sau khi cài đặt.
#------------------------------------------------------------------

# --- Tiện ích ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}Chào mừng đến với kịch bản cài đặt tự động hoàn thiện!${NC}"
echo "------------------------------------------------------------------"

# --- 1. HỎI NGƯỜI DÙNG VỀ CÁC DỊCH VỤ CẦN CÀI ĐẶT ---
read -p "Bạn có muốn cài đặt PostgreSQL + pgvector không? (y/n): " INSTALL_POSTGRES
read -p "Bạn có muốn cài đặt Dịch vụ API Puppeteer không? (y/n): " INSTALL_PUPPETEER
read -p "Bạn có muốn cài đặt Dịch vụ API Crawl4AI (có VNC) không? (y/n): " INSTALL_CRAWL4AI

# --- 2. THU THẬP CÁC THÔNG TIN CẤU HÌNH ---
echo -e "${YELLOW}Vui lòng cung cấp các thông tin cấu hình cần thiết:${NC}"

# Khởi tạo biến
POSTGRES_USER=""
POSTGRES_PASSWORD=""
POSTGRES_DB=""
OPENAI_API_KEY=""
CRAWL_API_KEY=""
VNC_PASSWORD=""

if [[ $INSTALL_POSTGRES == "y" ]]; then
    read -p "Nhập tên cho PostgreSQL User (ví dụ: ticmiro2): " POSTGRES_USER
    read -s -p "Nhập mật khẩu cho PostgreSQL User: " POSTGRES_PASSWORD
    echo
    read -p "Nhập tên cho PostgreSQL Database (ví dụ: ticmirodb2): " POSTGRES_DB
fi

if [[ $INSTALL_CRAWL4AI == "y" ]]; then
    read -p "Nhập OpenAI API Key của bạn: " OPENAI_API_KEY
    read -p "Tạo và nhập một API Key cho dịch vụ Crawl4AI: " CRAWL_API_KEY
    read -s -p "Tạo mật khẩu cho VNC (để tạo profile): " VNC_PASSWORD
    echo
fi

# --- 3. BẮT ĐẦU CÀI ĐẶT VÀ TẠO TỆP ---
echo "------------------------------------------------------------------"
echo -e "${YELLOW}Bắt đầu tạo tệp và cài đặt... Thao tác này có thể mất vài phút.${NC}"

mkdir -p my-services-stack
cd my-services-stack

DOCKER_COMPOSE_CONTENT="version: '3.8'\n\nservices:"

# --- Cấu hình cho PostgreSQL ---
if [[ $INSTALL_POSTGRES == "y" ]]; then
    echo "=> Đang cấu hình cho PostgreSQL..."
    DOCKER_COMPOSE_CONTENT+="\n  postgres_db:\n    image: pgvector/pgvector:pg16\n    container_name: postgres_db\n    environment:\n      POSTGRES_USER: ${POSTGRES_USER}\n      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}\n      POSTGRES_DB: ${POSTGRES_DB}\n    volumes:\n      - postgres_data:/var/lib/postgresql/data\n    ports:\n      - \"5432:5432\"\n    networks:\n      - my-app-network\n    restart: always"
fi

# --- Cấu hình cho Dịch vụ Puppeteer ---
if [[ $INSTALL_PUPPETEER == "y" ]]; then
    echo "=> Đang tạo các tệp cho Dịch vụ Puppeteer..."
    mkdir -p puppeteer-api
    
    cat <<'EOF' > puppeteer-api/Dockerfile
# Sử dụng image chính thức của Puppeteer
FROM ghcr.io/puppeteer/puppeteer:22.10.0

# Chuyển sang user ROOT để có toàn quyền
USER root

# Tạo thư mục làm việc
RUN mkdir -p /home/pptruser/app

# Gán quyền sở hữu của thư mục này cho user 'pptruser' (user mặc định của image)
RUN chown -R pptruser:pptruser /home/pptruser/app

# Đặt thư mục làm việc
WORKDIR /home/pptruser/app

# Sao chép các file package trước
COPY package*.json ./

# Chuyển về lại user pptruser để chạy các lệnh tiếp theo một cách an toàn
USER pptruser

# Bây giờ npm install sẽ chạy với user pptruser trong thư mục mà nó sở hữu
RUN npm install

# Sao chép phần còn lại của mã nguồn (với quyền sở hữu của pptruser)
COPY --chown=pptruser:pptruser . .

# Chạy ứng dụng khi container khởi động
CMD ["npm", "start"]
EOF

    cat <<'EOF' > puppeteer-api/package.json
{
  "name": "puppeteer-n8n-server",
  "version": "1.0.0",
  "description": "A Puppeteer server for n8n.",
  "main": "index.js",
  "scripts": {
    "start": "node index.js"
  },
  "dependencies": {
    "express": "^4.19.2",
    "puppeteer": "^22.12.1"
  }
}
EOF

    cat <<'EOF' > puppeteer-api/index.js
const express = require('express');
const puppeteer = require('puppeteer');

const app = express();
const port = 3000;

app.use(express.json({ limit: '50mb' }));

app.post('/scrape', async (req, res) => {
    const { url, action = 'scrapeWithSelectors', options = {} } = req.body;

    if (!url) {
        return res.status(400).json({ error: 'URL is required' });
    }

    console.log(`Nhận yêu cầu: action='${action}' cho url='${url}'`);

    let browser = null;
    try {
        const launchOptions = {
            headless: true,
            args: [
                '--no-sandbox',
                '--disable-setuid-sandbox',
                '--disable-dev-shm-usage',
                '--disable-gpu'
            ]
        };

        if (options.proxy) {
            console.log(`Đang sử dụng proxy: ${options.proxy}`);
            launchOptions.args.push(`--proxy-server=${options.proxy}`);
        }

        browser = await puppeteer.launch(launchOptions);
        const page = await browser.newPage();
        await page.setViewport({ width: 1920, height: 1080 });
        await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36');

        await page.goto(url, { waitUntil: 'networkidle2', timeout: 60000 });

        if (options.waitForSelector) {
            console.log(`Đang chờ selector: "${options.waitForSelector}"`);
            await page.waitForSelector(options.waitForSelector, { timeout: 30000 });
        }
        
        if (options.humanlike_scroll) {
            console.log('Thực hiện hành vi giống người: Cuộn trang...');
            await page.evaluate(async () => {
                await new Promise((resolve) => {
                    let totalHeight = 0;
                    const distance = 100;
                    const timer = setInterval(() => {
                        const scrollHeight = document.body.scrollHeight;
                        window.scrollBy(0, distance);
                        totalHeight += distance;

                        if (totalHeight >= scrollHeight) {
                            clearInterval(timer);
                            resolve();
                        }
                    }, 200);
                });
            });
            console.log('Đã cuộn xong trang.');
        }

        switch (action) {
            case 'scrapeWithSelectors':
                if (!options.selectors || Object.keys(options.selectors).length === 0) {
                    throw new Error('Hành động "scrapeWithSelectors" yêu cầu "selectors" trong options');
                }
                const scrapedData = await page.evaluate((selectors) => {
                    const results = {};
                    for (const key in selectors) {
                        const element = document.querySelector(selectors[key]);
                        results[key] = element ? element.innerText.trim() : null;
                    }
                    return results;
                }, options.selectors);

                console.log('Cào dữ liệu với selectors tùy chỉnh thành công.');
                res.status(200).json(scrapedData);
                break;
                
            case 'screenshot':
                 const imageBuffer = await page.screenshot({ fullPage: true, encoding: 'base64' });
                 console.log('Chụp ảnh màn hình thành công.');
                 res.status(200).json({ screenshot_base64: imageBuffer });
                 break;

            default:
                throw new Error(`Action không hợp lệ: ${action}`);
        }

    } catch (error) {
        console.error(`Lỗi khi thực hiện action '${action}':`, error);
        res.status(500).json({ error: 'Failed to process request.', details: error.message });
    } finally {
        if (browser) {
            await browser.close();
        }
    }
});

app.listen(port, () => {
    console.log(`Puppeteer server đã sẵn sàng tại http://localhost:${port}`);
});
EOF

    DOCKER_COMPOSE_CONTENT+="\n  puppeteer_api:\n    build: ./puppeteer-api\n    container_name: puppeteer_api\n    ports:\n      - \"3000:3000\"\n    networks:\n      - my-app-network\n    restart: always"
fi

# --- Cấu hình cho Dịch vụ Crawl4AI ---
if [[ $INSTALL_CRAWL4AI == "y" ]]; then
    echo "=> Đang tạo các tệp cho Dịch vụ Crawl4AI..."
    sudo apt-get update > /dev/null 2>&1 && sudo apt-get install -y xfce4 xfce4-goodies dbus-x11 tigervnc-standalone-server > /dev/null 2>&1
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
    mkdir -p crawl4ai-api
    cat <<'EOF' > crawl4ai-api/Dockerfile
FROM python:3.10-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
RUN playwright install --with-deps chromium
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
CRAWL_API_KEY="${CRAWL_API_KEY}"
EOF
    cat <<'EOF' > crawl4ai-api/create_profile.py
import asyncio
from crawl4ai.browser_profiler import BrowserProfiler
from crawl4ai.async_logger import AsyncLogger

async def main():
    logger = AsyncLogger(verbose=True)
    profiler = BrowserProfiler(logger=logger)

    print("--- Trình tạo Profile Đăng nhập ---")
    print("QUAN TRỌNG: Bạn cần có VNC hoặc một giao diện đồ họa để thấy và tương tác với trình duyệt sắp mở ra.")

    await profiler.interactive_manager()

if __name__ == "__main__":
    asyncio.run(main())
EOF
    cat <<'EOF' > crawl4ai-api/api_server.py
import os
import signal
import asyncio
from typing import Optional, List
from fastapi import FastAPI, HTTPException, Header, Depends
from fastapi.responses import Response
from pydantic import BaseModel
from crawl4ai import AsyncWebCrawler
from crawl4ai.async_configs import BrowserConfig, CrawlerRunConfig
from crawl4ai.browser_profiler import BrowserProfiler
from dotenv import load_dotenv

load_dotenv()
app = FastAPI()

async def verify_api_key(x_api_key: Optional[str] = Header(None)):
    SECRET_KEY = os.getenv("CRAWL_API_KEY")
    if not SECRET_KEY: raise HTTPException(status_code=500, detail="API Key not configured on server")
    if x_api_key != SECRET_KEY: raise HTTPException(status_code=401, detail="Unauthorized: Invalid API Key")

crawler_lock = asyncio.Lock()

class CrawlRequest(BaseModel): url: str
class ScreenshotRequest(BaseModel): url: str; full_page: bool = True
class ProfileCrawlRequest(BaseModel):
    url: str
    profile_name: str

@app.post("/crawl", dependencies=[Depends(verify_api_key)])
async def simple_crawl(request: CrawlRequest):
    async with crawler_lock:
        try:
            browser_config = BrowserConfig(headless=True, verbose=False)
            async with AsyncWebCrawler(config=browser_config) as crawler:
                result = await crawler.arun(url=request.url)
                if result.success: return {"success": True, "url": result.url, "markdown": result.markdown.raw_markdown, "metadata": result.metadata}
                raise HTTPException(status_code=400, detail=f"Crawl failed: {result.error_message}")
        except Exception as e: raise HTTPException(status_code=500, detail=str(e))

@app.post("/screenshot", response_class=Response, dependencies=[Depends(verify_api_key)])
async def take_screenshot(request: ScreenshotRequest):
    async with crawler_lock:
        try:
            browser_config = BrowserConfig(headless=True, verbose=False)
            async with AsyncWebCrawler(config=browser_config) as crawler:
                run_config = CrawlerRunConfig(screenshot={"full_page": request.full_page})
                result = await crawler.arun(url=request.url, config=run_config)
                if result.success and result.screenshot: return Response(content=result.screenshot, media_type="image/png")
                raise HTTPException(status_code=400, detail="Failed to take screenshot.")
        except Exception as e: raise HTTPException(status_code=500, detail=str(e))

@app.post("/crawl-with-profile", dependencies=[Depends(verify_api_key)])
async def crawl_with_profile(request: ProfileCrawlRequest):
    async with crawler_lock:
        profiler = BrowserProfiler()
        profile_path = profiler.get_profile_path(request.profile_name)
        if not profile_path or not os.path.exists(profile_path):
            raise HTTPException(status_code=404, detail=f"Profile '{request.profile_name}' not found.")
        try:
            profile_browser_config = BrowserConfig(headless=True, verbose=False, user_data_dir=profile_path)
            async with AsyncWebCrawler(config=profile_browser_config) as crawler:
                run_config = CrawlerRunConfig(js_code="await new Promise(resolve => setTimeout(resolve, 5000)); return true;")
                result = await crawler.arun(url=request.url, config=run_config)
                if result.success:
                    return {"success": True, "url": result.url, "markdown": result.markdown.raw_markdown, "metadata": result.metadata}
                raise HTTPException(status_code=400, detail=f"Crawl failed with profile: {result.error_message}")
        except Exception as e:
            raise HTTPException(status_code=500, detail=str(e))

@app.post("/restart", dependencies=[Depends(verify_api_key)])
async def restart_server():
    print("INFO: Received authenticated restart request. Shutting down...")
    os.kill(os.getpid(), signal.SIGINT)
    return {"message": "Server is restarting..."}
EOF

    DOCKER_COMPOSE_CONTENT+="\n  crawl4ai_api:\n    build: ./crawl4ai-api\n    container_name: crawl4ai_api\n    init: true\n    ports:\n      - \"8000:8000\"\n    env_file:\n      - ./crawl4ai-api/.env\n    shm_size: '2g'\n    environment:\n      - DISPLAY=:1\n    volumes:\n      - ./crawl4ai_output:/app/output\n      - crawler-profiles:/root/.crawl4ai/profiles\n      - /tmp/.X11-unix:/tmp/.X11-unix\n      - /var/run/dbus:/var/run/dbus\n    networks:\n      - my-app-network\n    restart: unless-stopped"
fi

DOCKER_COMPOSE_CONTENT+="\n\nnetworks:\n  my-app-network:\n    driver: bridge\n\nvolumes:\n  postgres_data:\n  crawler-profiles:"

echo "=> Tạo tệp docker-compose.yml tổng hợp..."
echo -e "$DOCKER_COMPOSE_CONTENT" > docker-compose.yml

# --- 4. TRIỂN KHAI HỆ THỐNG ---
echo "------------------------------------------------------------------"
echo -e "${YELLOW}Bắt đầu build và khởi chạy các dịch vụ... Quá trình này có thể mất vài phút.${NC}"
sudo docker compose up -d --build

# --- 5. HƯỚNG DẪN CUỐI CÙNG ---
echo "=================================================================="
echo -e "${GREEN}🚀 CÀI ĐẶT HOÀN TẤT! 🚀${NC}"
echo "Các dịch vụ bạn chọn đã được triển khai thành công."

echo ""
echo -e "${RED}##################################################################"
echo -e "${RED}#                                                                #"
echo -e "${RED}#      THÔNG TIN QUAN TRỌNG - HÃY LƯU LẠI NGAY LẬP TỨC           #"
echo -e "${RED}#                                                                #"
echo -e "${RED}##################################################################${NC}"
echo ""
echo -e "Các thông tin đăng nhập và API key này sẽ ${YELLOW}KHÔNG${NC} được hiển thị lại."
echo -e "Hãy sao chép và cất giữ ở nơi an toàn ${RED}TRƯỚC KHI${NC} đóng cửa sổ terminal này."
echo ""

if [[ $INSTALL_POSTGRES == "y" ]]; then
echo -e "${GREEN}--- 🐘 Thông tin kết nối PostgreSQL ---${NC}"
echo -e "  Host:             <IP_CUA_BAN>"
echo -e "  Port:             5432"
echo -e "  Database:         ${YELLOW}${POSTGRES_DB}${NC}"
echo -e "  User:             ${YELLOW}${POSTGRES_USER}${NC}"
echo -e "  Password:         ${RED}${POSTGRES_PASSWORD}${NC}"
echo ""
fi

if [[ $INSTALL_PUPPETEER == "y" ]]; then
echo -e "${GREEN}---  puppeteer Thông tin API Puppeteer ---${NC}"
echo -e "  Endpoint:         ${YELLOW}http://<IP_CUA_BAN>:3000/scrape${NC}"
echo -e "  Method:           POST"
echo ""
fi

if [[ $INSTALL_CRAWL4AI == "y" ]]; then
echo -e "${GREEN}--- 🕷️ Thông tin API Crawl4AI ---${NC}"
echo -e "  Endpoint:         ${YELLOW}http://<IP_CUA_BAN>:8000${NC}"
echo -e "  Header Name:      x-api-key"
echo -e "  Header Value:     ${RED}${CRAWL_API_KEY}${NC}"
echo ""
fi

if [[ $INSTALL_CRAWL4AI == "y" ]]; then
    echo ""
    echo -e "${YELLOW}VIỆC CẦN LÀM (CHO CRAWL4AI): TẠO PROFILE ĐĂNG NHẬP${NC}"
    echo "1. Khởi động VNC Server:"
    echo "   - Chạy lệnh: ${YELLOW}vncserver -localhost no :1${NC}"
    echo "   - Mở cổng firewall: ${YELLOW}sudo ufw allow 5901/tcp${NC}"
    echo "2. Kết nối vào VPS bằng VNC Viewer (Địa chỉ: <IP_CUA_BAN>:1)."
    echo "3. Mở Terminal Emulator bên trong màn hình VNC và chạy:"
    echo -e "   ${YELLOW}xhost +${NC}"
    echo -e "   ${YELLOW}sudo docker exec -it crawl4ai_api python create_profile.py${NC}"
    echo "4. Đăng nhập vào trang web qua trình duyệt hiện ra, sau đó nhấn 'q' trong terminal để lưu."
fi

echo ""
echo "Để xem log của toàn bộ hệ thống, chạy lệnh: ${YELLOW}cd my-services-stack && sudo docker-compose logs -f${NC}"
echo "=================================================================="
