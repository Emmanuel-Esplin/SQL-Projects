# syntax=docker/dockerfile:1
# Diamond Tracker container image. Settings come from DT_* environment
# variables at run time; nothing secret is built into the image.
#
#   docker build -t diamond-tracker diamond_company/app
#   docker run --rm -p 127.0.0.1:8000:8000 --env-file diamond_company/app/.env \
#     -e DT_DB_HOST=host.docker.internal -v dt-storage:/app/storage diamond-tracker

# Pinned by digest; Dependabot proposes updates
FROM python:3.15-slim@sha256:65a65fc7b30b06cb6df4930fd4650697cb23f4c2698ab81fc87e4b031bc36928

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    DT_STORAGE_DIR=/app/storage

WORKDIR /app

RUN groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --home-dir /app --shell /usr/sbin/nologin app

COPY requirements.txt .
RUN pip install --no-compile -r requirements.txt

COPY diamond_app ./diamond_app
RUN mkdir -p /app/storage && chown app:app /app/storage

# Code is owned by root and read-only to the app; only storage is writable
USER 10001:10001
VOLUME ["/app/storage"]
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD ["python", "-c", "import sys, urllib.request; sys.exit(urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=4).status != 200)"]

# --no-server-header hides the server software; --proxy-headers trusts
# X-Forwarded-* only from a proxy on 127.0.0.1 (adjust --forwarded-allow-ips
# when a reverse proxy runs elsewhere)
CMD ["uvicorn", "diamond_app.main:app", "--host", "0.0.0.0", "--port", "8000", \
     "--no-server-header", "--proxy-headers", "--forwarded-allow-ips", "127.0.0.1"]
