#!/bin/bash
# Arranque de la sincronización con GitHub. Se instala como /usr/local/bin/actualizar-n8n.sh
# (lo llaman el startup-script de la VM y el cron). Solo trae el código de main y le pasa el
# control a infra/actualizar-n8n.sh, que es donde vive la lógica.
set -euo pipefail

# Ruta del repositorio en la VM (la escribe infra/actualizar-n8n.sh al instalarse)
# shellcheck source=/dev/null
source /etc/default/jobsearch

# Una sola sincronización a la vez (arranque y cron pueden coincidir)
exec 9>/var/lock/actualizar-n8n.lock
flock -w 900 9
export SINCRONIZACION_CON_CANDADO=1

cd "$REPO_DIR"
git config --system --get-all safe.directory | grep -qx "$REPO_DIR" \
  || git config --system --add safe.directory "$REPO_DIR"
git fetch --quiet origin main
git reset --quiet --hard origin/main

exec bash "$REPO_DIR/infra/actualizar-n8n.sh" "$@"
