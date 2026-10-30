# Desplegar en Google Cloud (VM con Docker)

Guía para dejar n8n corriendo en una VM de Google Cloud que se enciende a las
8:40 y se apaga a las 12:00, de lunes a viernes. Los comandos `gcloud` se
ejecutan desde **Cloud Shell** (el ícono `>_` arriba a la derecha en
[console.cloud.google.com](https://console.cloud.google.com)) o desde tu PC con
el SDK de Google Cloud instalado.

## Por qué una VM y no Cloud Run

n8n tiene que estar encendido para disparar sus horarios internos. Cloud Run
escala a cero sin tráfico entrante, así que los horarios no se dispararían. Basta
una VM pequeña (1 GB de RAM y 30 GB de disco estándar).

## 0. Variables

Define estos valores una vez (ajústalos a tu gusto) y úsalos en todos los pasos:

```bash
VM=n8n-busqueda-empleo
REGION=<tu-region>
ZONE=<tu-zona>
ZONA_HORARIA=America/Mexico_City   # la tuya, formato IANA
REPO=https://github.com/<tu-usuario>/<tu-repo>.git
```

## 1. Crear la VM

```bash
gcloud compute instances create $VM \
  --zone=$ZONE \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=30GB \
  --boot-disk-type=pd-standard
```

No hace falta IP estática ni abrir puertos: al editor de n8n se entra por un
túnel SSH (paso 6), y n8n solo escucha en `localhost` dentro de la VM.

## 2. Horario de encendido y apagado (L-V, 8:40 a 12:00)

```bash
gcloud compute resource-policies create instance-schedule n8n-horario \
  --region=$REGION \
  --vm-start-schedule="40 8 * * 1-5" \
  --vm-stop-schedule="0 12 * * 1-5" \
  --timezone=$ZONA_HORARIA

gcloud compute instances add-resource-policies $VM \
  --zone=$ZONE --resource-policies=n8n-horario
```

La cuenta de servicio de Compute Engine necesita el rol
*Compute Instance Admin (v1)* para que la política pueda encender y apagar la VM.

## 3. Docker y swap

```bash
gcloud compute ssh $VM --zone=$ZONE
```

Dentro de la VM:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg git
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker $USER

# con 1 GB de RAM: 2 GB de swap
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
exit
```

Vuelve a entrar con `gcloud compute ssh $VM --zone=$ZONE` para que el grupo
`docker` quede aplicado.

## 4. Código y `.env`

```bash
git clone $REPO job-search-automation
cd job-search-automation
cp .env.example .env
nano .env        # completa todas las variables (ver README → Configuración)
chmod 600 .env
sudo bash infra/actualizar-n8n.sh
exit
```

Si tu repo es privado, `git clone` te pedirá un token de acceso de GitHub.

La primera ejecución de `infra/actualizar-n8n.sh` levanta n8n, importa y publica los
workflows, e instala la sincronización con GitHub (ver *Despliegue continuo automático*).
Falta indicarle a la VM que la ejecute al encenderse (desde tu PC):

```bash
gcloud compute instances add-metadata $VM --zone=$ZONE \
  --metadata=startup-script=/usr/local/bin/actualizar-n8n.sh
```

## 5. Google: APIs y OAuth

En la consola de Google Cloud de tu proyecto:

1. **APIs y servicios → Biblioteca**: habilita **Google Sheets API**,
   **Google Docs API** y **Google Drive API**.
2. **Google Auth Platform → Marca**: nombre de la app, correo de asistencia,
   correo de contacto del desarrollador, y enlaces públicos a una página principal
   y a una política de privacidad (pueden ser páginas simples en GitHub Pages);
   agrega su dominio en *Dominios autorizados*.
3. **Público**: pulsa **Publicar app** para dejarla **"En producción"**. En
   modo "Prueba", Google anula el permiso cada 7 días y los workflows dejan de
   escribir en la planilla sin avisar.
4. **Clientes → Crear cliente (Aplicación web)**, con esta URI de redireccionamiento:
   ```
   http://localhost:5678/rest/oauth2-credential/callback
   ```

## 6. Entrar al editor (túnel SSH)

Desde tu PC:

```bash
gcloud compute ssh $VM --zone=$ZONE --ssh-flag="-L 5678:localhost:5678" --ssh-flag="-N"
```

Deja esa terminal abierta y abre `http://localhost:5678`. La primera vez,
n8n te pide crear la cuenta owner: **guarda esa contraseña**.

## 7. Credenciales e importación

1. En n8n → **Credentials**, crea con estos nombres exactos (con el Client ID y
   el secreto del paso 5):
   - `Google Sheets account` (tipo *Google Sheets OAuth2 API*)
   - `Google Docs account` (tipo *Google Docs OAuth2 API*)

   Pulsa *Sign in with Google* en cada una. Si Google muestra "app no
   verificada": *Configuración avanzada → Ir a la app*, marca todos los permisos.
2. Vuelve a importar y activar los workflows, ya con las credenciales (en la VM):
   ```bash
   sudo rm -f /var/lib/jobsearch/ultimo-commit
   sudo /usr/local/bin/actualizar-n8n.sh
   ```
   No uses `docker exec ... import:workflow` con n8n encendido: bloquea su base de datos.

## Despliegue continuo automático

El despliegue está 100% automatizado y se alimenta solo de `main`. Todo lo que corre en la
VM está en [`infra/`](infra/):

| Archivo | Se instala como | Qué hace |
|---|---|---|
| `infra/arranque.sh` | `/usr/local/bin/actualizar-n8n.sh` | Trae `main` (`git fetch` + `reset`) y pasa el control al script siguiente. Evita dos sincronizaciones a la vez. |
| `infra/actualizar-n8n.sh` | — (corre desde el repo) | Reinstala el arranque y el cron si cambiaron. Si cambió algo en `workflows/` o en `docker-compose.yml`, detiene n8n, importa y publica los workflows en un contenedor aparte y vuelve a levantarlo. Si no, no toca n8n. |
| `infra/jobsearch-autoupdate.cron` | `/etc/cron.d/jobsearch-autoupdate` | Ejecuta la sincronización cada 5 minutos mientras la VM está encendida. |

1. **Al encenderse la VM (8:40 L-V):** el metadato `startup-script` ejecuta la sincronización y aplica todo lo pendiente antes del primer workflow (9:05).
2. **Mientras está encendida:** el cron la repite cada 5 minutos. Un push que solo cambia
   documentación no reinicia n8n. Uno que cambia workflows o el `docker-compose.yml` se
   aplica en menos de 5 minutos fuera del horario de los workflows; de 9:00 a 12:00 queda
   pendiente para el arranque siguiente, para no cortar ejecuciones.
3. **Si una sincronización falla** con n8n detenido, el script lo vuelve a levantar y guarda
   el registro en `/var/log/autoupdate-ultimo-error.log`.
4. **En GitHub:** GitHub Actions (`.github/workflows/ci.yml`) valida en cada push la sintaxis
   de los workflows, el `docker-compose.yml` y los scripts de `infra/`. De domingo a jueves a las 18:00, `.github/workflows/version-n8n.yml` revisa si hay
   una versión estable de n8n más nueva que la fijada; si la hay, la fija, valida el compose
   y la sube a `main`, y la VM la aplica en su arranque de las 8:40.

La importación nunca corre con n8n encendido: n8n guarda todo en SQLite y dos procesos
escribiendo a la vez bloquean la base.

### Limpieza (cada 15 días y en cada actualización)

| Dónde | Qué se borra | Quién lo hace |
|---|---|---|
| VM | Imágenes y contenedores de Docker que ya no se usan (versiones viejas de n8n) | `infra/actualizar-n8n.sh`, después de cada actualización exitosa |
| VM | Historial de ejecuciones de n8n con más de 15 días | n8n (`EXECUTIONS_DATA_MAX_AGE` en `docker-compose.yml`) |
| VM | Registros del contenedor (máximo 3 archivos de 10 MB) | Docker (`logging` en `docker-compose.yml`) |
| GitHub | Ejecuciones de workflows y cachés de más de 15 días | `.github/workflows/depuracion.yml`, los días 1 y 16 |
| Drive | HV con más de 15 días (a la papelera) | Workflow *Limpieza Drive HV*, los viernes |

Para forzar una actualización manual en cualquier momento:
```bash
sudo /usr/local/bin/actualizar-n8n.sh
```

## Probar un workflow a mano

Cada workflow tiene un disparador `Ejecutar a mano (prueba)`. Desde el editor:
abre el workflow y pulsa *Execute workflow*. Por CLI (en la VM):

```bash
docker exec -u node -e N8N_RUNNERS_BROKER_PORT=5680 n8n n8n execute --id=<id-del-workflow>
```
