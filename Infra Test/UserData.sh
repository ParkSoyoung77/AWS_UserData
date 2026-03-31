#!/bin/bash
dnf update -y
dnf install nginx python3-pip -y
pip3 install fastapi uvicorn

# 1. 인덱스 페이지 생성 (HTML 메타 태그 추가로 더 확실하게 보호)
cat <<EOF > /usr/share/nginx/html/index.html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>1차 인프라 구축 완료</title>
    <style>
        body { font-family: sans-serif; text-align: center; margin-top: 50px; }
    </style>
</head>
<body>
    <h1>SY의 1차 인프라 테스트</h1>
    <p>Nginx 정적 페이지 접속 성공!</p>
    <button onclick="checkAPI()">FastAPI 연결 확인</button>
    <p id="api-result"></p>
    <script>
        function checkAPI() {
            fetch('/api/')
                .then(response => response.json())
                .then(data => { document.getElementById('api-result').innerText = data.message; });
        }
    </script>
</body>
</html>
EOF

# 2. FastAPI 설정 
mkdir -p /home/ec2-user/app
chown -R ec2-user:ec2-user /home/ec2-user/app
cat <<EOF > /home/ec2-user/app/main.py
from fastapi import FastAPI
app = FastAPI()
@app.get("/")
def read_root():
    return {"message": "축하합니다! ALB -> Nginx -> FastAPI 연결에 성공했습니다."}
EOF

# 3. 서비스 등록
cat <<EOF > /etc/systemd/system/fastapi.service
[Unit]
Description=FastAPI Service
After=network.target
[Service]
User=ec2-user
WorkingDirectory=/home/ec2-user/app
ExecStart=/usr/local/bin/uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now fastapi

# 4. Nginx 설정 (핵심: charset utf-8 추가)
cat <<'EOF' > /etc/nginx/conf.d/default.conf
server {
    listen 80;
    server_name _;
    charset utf-8; 

    location / {
        root /usr/share/nginx/html;
        index index.html;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:8000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF

systemctl enable --now nginx
systemctl restart nginx