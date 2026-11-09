#!/usr/bin/env bash
set -Eeuo pipefail

SERVER_IP="${1:-}"
CUSTOM_CERT="${2:-}"
CUSTOM_KEY="${3:-}"
TLS_DIR="/etc/nginx/tls"
CERT_FILE="$TLS_DIR/image-uploader.crt"
KEY_FILE="$TLS_DIR/image-uploader.key"
NGINX_NAME="image-uploader"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Uruchom skrypt jako root: sudo bash $0 <IP-serwera> [certyfikat.crt klucz.key]." >&2
  exit 1
fi

if [[ -z "$SERVER_IP" ]]; then
  echo "Podaj adres IP serwera, np. 192.168.1.12." >&2
  exit 1
fi

if [[ -n "$CUSTOM_CERT" && -z "$CUSTOM_KEY" || -z "$CUSTOM_CERT" && -n "$CUSTOM_KEY" ]]; then
  echo "Podaj jednocześnie ścieżkę do certyfikatu i klucza albo pomiń oba argumenty." >&2
  exit 1
fi

if ! command -v nginx >/dev/null 2>&1; then
  echo "Nie znaleziono Nginx. Najpierw uruchom install.sh." >&2
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "Nie znaleziono OpenSSL ani apt-get; zainstaluj OpenSSL ręcznie i uruchom skrypt ponownie." >&2
    exit 1
  fi
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y openssl
fi

if [[ -d /etc/nginx/sites-available && -d /etc/nginx/sites-enabled ]]; then
  NGINX_CONFIG="/etc/nginx/sites-available/$NGINX_NAME"
else
  NGINX_CONFIG="/etc/nginx/conf.d/$NGINX_NAME.conf"
fi

if [[ ! -f "$NGINX_CONFIG" ]] || ! grep -Fqx "# Managed by image-uploader scripts" "$NGINX_CONFIG"; then
  echo "Nie znaleziono zarządzanej konfiguracji $NGINX_CONFIG. Najpierw uruchom install.sh." >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ -n "$CUSTOM_CERT" ]]; then
  if [[ ! -f "$CUSTOM_CERT" || ! -f "$CUSTOM_KEY" ]]; then
    echo "Nie znaleziono wskazanego pliku certyfikatu lub klucza." >&2
    exit 1
  fi
  cp "$CUSTOM_CERT" "$TMP_DIR/image-uploader.crt"
  cp "$CUSTOM_KEY" "$TMP_DIR/image-uploader.key"
else
  openssl req -x509 -newkey rsa:3072 -sha256 -days 365 -nodes \
    -keyout "$TMP_DIR/image-uploader.key" \
    -out "$TMP_DIR/image-uploader.crt" \
    -subj "/CN=$SERVER_IP" \
    -addext "subjectAltName=IP:$SERVER_IP"
fi

if ! openssl x509 -in "$TMP_DIR/image-uploader.crt" -noout -checkip "$SERVER_IP"; then
  echo "Certyfikat nie zawiera podanego adresu IP ($SERVER_IP) w SAN." >&2
  exit 1
fi

if ! openssl pkey -in "$TMP_DIR/image-uploader.key" -noout >/dev/null 2>&1; then
  echo "Nie można odczytać klucza prywatnego." >&2
  exit 1
fi

CERT_PUBLIC_KEY="$(openssl x509 -in "$TMP_DIR/image-uploader.crt" -pubkey -noout)"
PRIVATE_PUBLIC_KEY="$(openssl pkey -in "$TMP_DIR/image-uploader.key" -pubout 2>/dev/null)"
if [[ "$CERT_PUBLIC_KEY" != "$PRIVATE_PUBLIC_KEY" ]]; then
  echo "Certyfikat i klucz prywatny do siebie nie pasują." >&2
  exit 1
fi

install -d -o root -g root -m 0755 "$TLS_DIR"
install -o root -g root -m 0644 "$TMP_DIR/image-uploader.crt" "$CERT_FILE"
install -o root -g root -m 0600 "$TMP_DIR/image-uploader.key" "$KEY_FILE"

cp "$NGINX_CONFIG" "$TMP_DIR/nginx-config.backup"
cat > "$NGINX_CONFIG" <<'NGINX'
# Managed by image-uploader scripts
server {
    listen 8080 ssl default_server;
    server_name _;

    ssl_certificate /etc/nginx/tls/image-uploader.crt;
    ssl_certificate_key /etc/nginx/tls/image-uploader.key;

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

if ! nginx -t; then
  cp "$TMP_DIR/nginx-config.backup" "$NGINX_CONFIG"
  echo "Błędna konfiguracja Nginx; przywrócono poprzednią konfigurację." >&2
  exit 1
fi

systemctl reload nginx
echo "HTTPS włączony: https://$SERVER_IP:8080/"
if [[ -z "$CUSTOM_CERT" ]]; then
  echo "Użyto certyfikatu samopodpisanego. Dodaj go do zaufanych certyfikatów klientów, aby usunąć ostrzeżenie przeglądarki."
fi
