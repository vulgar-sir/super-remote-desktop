FROM python:3.12-slim

# Python package mirror (empty = official PyPI)
ARG PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 TZ=Asia/Shanghai SUPERDESK_DATA=/data

WORKDIR /srv
COPY requirements.txt .
RUN pip install --no-cache-dir ${PIP_INDEX_URL:+-i $PIP_INDEX_URL} -r requirements.txt
COPY app ./app

VOLUME /data
# Bound to localhost only; the nginx gateway publishes /api and /admin on the public port.
CMD ["uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", "21120", "--proxy-headers", "--forwarded-allow-ips", "127.0.0.1"]
