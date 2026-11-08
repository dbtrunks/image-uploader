#!/usr/bin/env bash
set -Eeuo pipefail

PUBLISH_DIR="${1:-/tmp/image-uploader-publish}"
APP_DIR="/opt/image-uploader"
DATA_DIR="/var/lib/image-uploader"
SERVICE_USER="image-uploader"
SERVICE_GROUP="image-uploader"
SERVICE_FILE="/etc/systemd/system/image-uploader.service"
NGINX_NAME="image-uploader"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Uruchom skrypt jako root: sudo bash $0 [katalog-publish]." >&2
  exit 1
fi

if [[ ! -x "$PUBLISH_DIR/ImageUploader" ]]; then
  echo "Nie znaleziono wykonywalnego pliku $PUBLISH_DIR/ImageUploader. Najpierw opublikuj aplikację dla linux-x64." >&2
  exit 1
fi

if [[ ! -f "$PUBLISH_DIR/appsettings.json" || ! -d "$PUBLISH_DIR/wwwroot" ]]; then
  echo "Katalog publikacji musi zawierać appsettings.json oraz wwwroot." >&2
  exit 1
fi

if ! command -v nginx >/dev/null 2>&1; then
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "Nie znaleziono Nginx ani apt-get. Zainstaluj Nginx ręcznie i uruchom skrypt ponownie." >&2
    exit 1
  fi
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y nginx
fi

for command_name in systemctl getent groupadd useradd install find; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Brak wymaganego polecenia: $command_name." >&2
    exit 1
  fi
done

if [[ -d /etc/nginx/sites-available && -d /etc/nginx/sites-enabled ]]; then
  NGINX_CONFIG="/etc/nginx/sites-available/$NGINX_NAME"
  NGINX_ENABLED="/etc/nginx/sites-enabled/$NGINX_NAME"
else
  NGINX_CONFIG="/etc/nginx/conf.d/$NGINX_NAME.conf"
  NGINX_ENABLED=""
fi

if [[ -e "$NGINX_CONFIG" ]] && ! grep -Fqx "# Managed by image-uploader scripts" "$NGINX_CONFIG"; then
  echo "$NGINX_CONFIG już istnieje i nie jest zarządzany przez ten skrypt; nie nadpisano pliku." >&2
  exit 1
fi

if [[ -n "$NGINX_ENABLED" && -e "$NGINX_ENABLED" && ! -L "$NGINX_ENABLED" ]]; then
  echo "$NGINX_ENABLED już istnieje i nie jest dowiązaniem; nie nadpisano pliku." >&2
  exit 1
fi

if systemctl is-active --quiet image-uploader.service; then
  systemctl stop image-uploader.service
fi

if ! getent group "$SERVICE_GROUP" >/dev/null; then
  groupadd --system "$SERVICE_GROUP"
fi

if ! id "$SERVICE_USER" >/dev/null 2>&1; then
  useradd --system --gid "$SERVICE_GROUP" --no-create-home \
    --home-dir /nonexistent --shell /usr/sbin/nologin "$SERVICE_USER"
fi

install -d -o root -g root -m 0755 "$APP_DIR"
install -d -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 0750 \
  "$DATA_DIR/uploads" "$DATA_DIR/images"

cp -a "$PUBLISH_DIR"/. "$APP_DIR"/
chown -R root:root "$APP_DIR"
find "$APP_DIR" -type d -exec chmod 0755 {} +
find "$APP_DIR" -type f -exec chmod 0644 {} +
chmod 0755 "$APP_DIR/ImageUploader"

cat > "$SERVICE_FILE" <<'UNIT'
[Unit]
Description=Image Uploader
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=image-uploader
Group=image-uploader
WorkingDirectory=/opt/image-uploader
ExecStart=/opt/image-uploader/ImageUploader
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=ASPNETCORE_URLS=http://127.0.0.1:8282
Restart=on-failure
RestartSec=5
UMask=0027
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/image-uploader

[Install]
WantedBy=multi-user.target
UNIT

install -d -o root -g root -m 0755 "$(dirname "$NGINX_CONFIG")"
cat > "$NGINX_CONFIG" <<'NGINX'
# Managed by image-uploader scripts
server {
    listen 8080 default_server;
    server_name _;

    client_max_body_size 52m;

    location / {
        proxy_pass http://127.0.0.1:8282;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_request_buffering off;
        proxy_read_timeout 300s;
    }
}
NGINX

if [[ -n "$NGINX_ENABLED" && ! -L "$NGINX_ENABLED" ]]; then
  ln -s "$NGINX_CONFIG" "$NGINX_ENABLED"
fi

nginx -t
systemctl daemon-reload
systemctl enable --now image-uploader.service
systemctl enable --now nginx
systemctl reload nginx

echo "Instalacja zakończona. HTTP: http://<IP-serwera>:8080/"
echo "HTTPS możesz włączyć poleceniem: sudo bash addHttps.sh <IP-serwera>"
