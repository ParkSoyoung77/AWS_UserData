#!/bin/bash
# 1. 패키지 설치
dnf update -y
dnf install nginx python3-pip -y
pip3 install fastapi uvicorn mysql-connector-python pydantic

# 2. 한글 깨짐 방지 설정
cat <<EOF > /etc/nginx/conf.d/charset.conf
charset utf-8;
EOF

# 3. 디렉토리 구조 생성
mkdir -p /home/ec2-user/app
chown -R ec2-user:ec2-user /home/ec2-user/app

# 4. 프론트엔드 (SY님이 지정하신 글쓰기 UI 포함 index.html)
cat <<EOF > /usr/share/nginx/html/index.html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>SY의 AWS 게시판</title>
    <style>
        body { font-family: 'Segoe UI', sans-serif; text-align: center; background: #f8f9fa; padding: 20px; }
        .container { max-width: 900px; margin: auto; background: white; padding: 25px; border-radius: 15px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .board-img { width: 120px; margin-bottom: 15px; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; table-layout: fixed; } /* 테이블 레이아웃 고정 */
        th, td { border: 1px solid #ddd; padding: 12px; word-wrap: break-word; } /* 내용이 길면 자동 줄바꿈 */
        th { background: #009639; color: white; }
        .write-box { background: #eee; padding: 20px; border-radius: 10px; margin-top: 30px; text-align: left; }
        .write-box input, .write-box textarea { width: 95%; margin-bottom: 10px; padding: 8px; border-radius: 5px; border: 1px solid #ccc; }
        .btn { background: #009639; color: white; border: none; padding: 10px 20px; border-radius: 5px; cursor: pointer; }
    </style>
</head>
<body>
    <div class="container">
        <img src="https://내-버킷.s3.ap-south-2.amazonaws.com/nginx.jpg" class="board-img">
        <h1>SY의 실시간 AWS 게시판</h1>

        <div id="board-list">목록 로딩 중...</div>

        <div class="write-box">
            <h3>비회원 글쓰기</h3>
            <input type="text" id="author" placeholder="작성자 이름">
            <input type="password" id="pw" placeholder="비밀번호">
            <input type="text" id="title" placeholder="제목">
            <textarea id="content" rows="4" placeholder="내용을 입력하세요"></textarea>
            <button class="btn" onclick="writePost()">게시글 등록</button>
        </div>
    </div>

    <script>
        function loadList() {
            fetch('/api/list')
                .then(res => res.json())
                .then(data => {
                    if(!data || data.length === 0) {
                        document.getElementById('board-list').innerHTML = "<p>게시글이 없습니다.</p>";
                        return;
                    }
                    // [수정] 테이블 헤더에 '내용' 추가
                    let html = '<table><tr><th style="width: 50px;">번호</th><th>제목</th><th style="width: 100px;">작성자</th><th>내용</th><th style="width: 110px;">작성일</th></tr>';
                    data.forEach(item => {
                        // [수정] 데이터 행에 'item.content' 추가
                        html += \`<tr><td>\${item.id}</td><td>\${item.title}</td><td>\${item.author_name}</td><td>\${item.content}</td><td>\${item.created_at}</td></tr>\`;
                    });
                    html += '</table>';
                    document.getElementById('board-list').innerHTML = html;
                });
        }

        function writePost() {
            const payload = {
                author_name: document.getElementById('author').value,
                password: document.getElementById('pw').value,
                title: document.getElementById('title').value,
                content: document.getElementById('content').value,
                list_num: 1
            };

            fetch('/api/write', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify(payload)
            }).then(() => {
                alert('등록되었습니다!');
                location.reload();
            });
        }
        loadList();
    </script>
</body>
</html>
EOF

# 5. 백엔드 (GET/POST 기능이 모두 포함된 main.py)
# 5. 백엔드 (GET/POST 기능 및 content 조회 추가)
cat <<EOF > /home/ec2-user/app/main.py
from fastapi import FastAPI
from pydantic import BaseModel
import mysql.connector
from mysql.connector import Error

app = FastAPI()

# RDS 접속 정보
db_config = {
    'host': '내_DB_사설_IP',
    'user': '유저_아이디',
    'password': '패스워드',
    'database': 'board'
}

class Post(BaseModel):
    author_name: str
    password: str
    title: str
    content: str
    list_num: int

@app.get("/list")
def get_list():
    try:
        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor(dictionary=True)
        # [핵심 수정] SELECT 문에 content를 추가하여 프론트엔드로 전달합니다.
        cursor.execute("SELECT id, title, author_name, content, DATE_FORMAT(created_at, '%Y-%m-%d') as created_at FROM board_table ORDER BY id DESC")
        res = cursor.fetchall()
        cursor.close()
        conn.close()
        return res
    except Error as e:
        return {"error": str(e)}

@app.post("/write")
def create_post(post: Post):
    try:
        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor()
        sql = "INSERT INTO board_table (list_num, author_name, password, title, content) VALUES (%s, %s, %s, %s, %s)"
        cursor.execute(sql, (post.list_num, post.author_name, post.password, post.title, post.content))
        conn.commit()
        cursor.close()
        conn.close()
        return {"status": "success"}
    except Error as e:
        return {"error": str(e)}
EOF

# 6. FastAPI 서비스 등록
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

# 7. Nginx 리버스 프록시 설정 (가장 중요)
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