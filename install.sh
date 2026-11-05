#!/bin/bash
# Instala o actualiza el honeypot (Cowrie). Ejecutar como root desde la carpeta
# del repo:  bash install.sh   — idempotente.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Ejecutar como root" >&2; exit 1; }
SRC="$(cd "$(dirname "$0")" && pwd)"
DEST=/opt/honeypot
log() { echo "==> $*"; }

if [ ! -f "$SRC/.env" ]; then
  cp "$SRC/.env.example" "$SRC/.env"
  echo "He creado .env a partir de .env.example. Revisa sobre todo PRUEBA_DESTINOS y vuelve a lanzarlo." >&2
  exit 1
fi
# shellcheck source=/dev/null
. "$SRC/.env"
NET=${HONEYPOT_SUBNET:-172.30.250.0/24}

log "Comprobando que la red $NET está libre"
for net in $(docker network ls -q); do
  name=$(docker network inspect -f '{{.Name}}' "$net")
  [ "$name" = honeypot ] && continue
  if docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' "$net" | tr ' ' '\n' | grep -qxF "$NET"; then
    echo "La red Docker '$name' ya usa $NET: cambia HONEYPOT_SUBNET en .env" >&2
    exit 1
  fi
done

log "Archivos"
install -m 755 "$SRC/honeypot-firewall" /usr/local/bin/honeypot-firewall
install -d -m 755 "$DEST"
install -m 644 "$SRC/docker-compose.yml" "$DEST/docker-compose.yml"
install -m 640 "$SRC/.env" "$DEST/.env"
install -m 755 "$SRC/prueba-aislamiento.sh" "$DEST/prueba-aislamiento.sh"
for d in var var/log var/log/cowrie var/lib var/lib/cowrie var/lib/cowrie/downloads var/lib/cowrie/tty; do
  install -d -o 999 -g 999 -m 750 "$DEST/$d"
done
install -m 644 "$SRC/honeypot.tmpfiles" /etc/tmpfiles.d/honeypot.conf
install -m 644 "$SRC/honeypot.service" /etc/systemd/system/honeypot.service

log "Arrancando (cortafuegos primero)"
docker compose --project-directory "$DEST" pull -q
systemctl daemon-reload
systemctl enable honeypot.service >/dev/null 2>&1
systemctl restart honeypot.service
sleep 5
docker ps --filter name=honeypot-cowrie --format '{{.Names}}  {{.Status}}  {{.Ports}}'

log "Prueba de aislamiento"
"$DEST/prueba-aislamiento.sh" || {
  echo "¡El aislamiento NO funciona! Paro el honeypot." >&2
  systemctl stop honeypot.service
  exit 1
}

log "Comprobando que escucha"
for p in "${SSH_PORT:-2222}" "${TELNET_PORT:-2223}"; do
  timeout 3 bash -c "</dev/tcp/127.0.0.1/$p" && echo "  ✓ puerto $p" || echo "  ✗ puerto $p no responde"
done
echo
echo "Listo. Falta el router: 22 → servidor:${SSH_PORT:-2222} y 23 → servidor:${TELNET_PORT:-2223} (TCP)."
echo "Para verlo: tail -f $DEST/var/log/cowrie/cowrie.json"
