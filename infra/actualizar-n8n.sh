#!/bin/bash
# Aplica en la VM lo que hay en main. Lo ejecuta infra/arranque.sh después del git reset.
#
# - Sin cambios en workflows/ ni en docker-compose.yml: no toca n8n (no corta ejecuciones).
# - Con cambios: detiene n8n, importa y publica los workflows en un contenedor aparte y vuelve
#   a levantarlo. n8n usa SQLite: dos procesos escribiendo a la vez lo bloquean
#   (SQLITE_BUSY), por eso la importación nunca corre con n8n encendido.
set -euo pipefail

# Ejecutado a mano (sin infra/arranque.sh): toma el mismo candado para no cruzarse con el cron
if [ -z "${SINCRONIZACION_CON_CANDADO:-}" ]; then
  exec 9>/var/lock/actualizar-n8n.lock
  flock -w 900 9
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ESTADO=/var/lib/jobsearch/ultimo-commit
cd "$REPO_DIR"

echo "=== $(date -u '+%F %T') UTC · sincronizando $(git rev-parse --short HEAD)"

# 1. El arranque y el cron también se alimentan del repositorio
mkdir -p /var/lib/jobsearch
echo "REPO_DIR=$REPO_DIR" > /etc/default/jobsearch
cmp -s infra/arranque.sh /usr/local/bin/actualizar-n8n.sh \
  || install -m 0755 infra/arranque.sh /usr/local/bin/actualizar-n8n.sh
cmp -s infra/jobsearch-autoupdate.cron /etc/cron.d/jobsearch-autoupdate \
  || install -m 0644 infra/jobsearch-autoupdate.cron /etc/cron.d/jobsearch-autoupdate

# 2. ¿Hay algo que aplicar?
actual=$(git rev-parse HEAD)
anterior=$(cat "$ESTADO" 2>/dev/null || true)
corriendo=$(docker ps --filter name=^n8n$ --filter status=running --quiet)

if [ -n "$anterior" ] && git cat-file -e "$anterior^{commit}" 2>/dev/null; then
  cambios=$(git diff --name-only "$anterior" "$actual" -- workflows docker-compose.yml)
else
  cambios="(primera sincronización)"
fi

if [ -z "$cambios" ]; then
  [ -n "$corriendo" ] || docker compose up -d
  echo "$actual" > "$ESTADO"
  echo "Sin cambios en workflows ni en docker-compose.yml."
  exit 0
fi
echo "Cambios a aplicar:"; echo "$cambios"

# 3. De 9:00 a 12:00 (Bogotá) corren los workflows: el cron no detiene n8n en ese horario.
#    Los cambios quedan pendientes y los aplica el arranque de la VM a las 8:40.
hora=$(TZ=America/Bogota date +%H%M)
if [ "${1:-}" = "--cron" ] && [ -n "$corriendo" ] && (( 10#$hora >= 900 && 10#$hora < 1200 )); then
  echo "Horario de los workflows: los cambios se aplican en el próximo arranque."
  exit 0
fi

# 4. Importar y publicar con n8n detenido (un solo proceso sobre la base)
docker compose pull --quiet n8n
# Si algo falla con n8n detenido, se vuelve a levantar: nunca queda apagado por una
# sincronización. El registro del fallo se conserva (el cron sobrescribe el suyo).
trap 'echo "Falló la sincronización (línea $LINENO): se levanta n8n de nuevo" >&2
      cp /var/log/autoupdate.log /var/log/autoupdate-ultimo-error.log 2>/dev/null || true
      docker compose up -d' ERR
docker compose stop n8n
# Las variables del bloque se expanden dentro del contenedor, no aquí.
# shellcheck disable=SC2016
docker compose run --rm --no-deps -T --entrypoint sh n8n -c '
  set -e
  n8n import:workflow --separate --input=/workflows
  for id in $(n8n list:workflow --onlyId | grep -E "^[A-Za-z0-9]{16}$"); do
    n8n publish:workflow --id="$id" || echo "No se pudo publicar $id (¿faltan credenciales?)"
  done'

# 5. Levantar n8n y esperar a que responda
docker compose up -d
for _ in $(seq 1 60); do
  if curl -fsS http://127.0.0.1:5678/healthz > /dev/null 2>&1; then
    echo "$actual" > "$ESTADO"
    # Limpieza: imágenes y contenedores que ya no usa nadie (versiones viejas de n8n)
    docker container prune -f > /dev/null
    docker image prune -af > /dev/null
    echo "=== $(docker inspect -f '{{.Config.Image}}' n8n) listo con $(git rev-parse --short HEAD)"
    exit 0
  fi
  sleep 5
done
echo "n8n no respondió en 5 minutos" >&2
exit 1
