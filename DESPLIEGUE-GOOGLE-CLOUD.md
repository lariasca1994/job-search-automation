# Desplegar en Google Cloud (VM e2-micro del nivel gratuito)

Guía para dejar n8n corriendo en una VM de Google Cloud que se enciende a las
9:00 y se apaga a las 12:00, de lunes a viernes. Los comandos `gcloud` se
ejecutan desde **Cloud Shell** (el ícono `>_` arriba a la derecha en
[console.cloud.google.com](https://console.cloud.google.com)) o desde tu PC con
el SDK de Google Cloud instalado.

## Por qué una VM y no Cloud Run

n8n tiene que estar encendido para disparar sus horarios internos. Cloud Run
escala a cero sin tráfico entrante, así que los horarios no se dispararían. Una
`e2-micro` está en el nivel *Always Free* de Compute Engine (en `us-west1`,
`us-central1` o `us-east1`, con 30 GB de disco estándar).

Activa una alerta de presupuesto en $1 (*Facturación → Presupuestos y
alertas*): es gratis y te avisa si algo sale del nivel gratuito.

## 0. Variables

Define estos valores una vez (ajústalos a tu gusto) y úsalos en todos los pasos:

```bash
VM=n8n-busqueda-empleo
REGION=us-central1
ZONE=us-central1-a
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

## 2. Horario de encendido y apagado (L-V, 9:00 a 12:00)

```bash
gcloud compute resource-policies create instance-schedule horario-vm \
  --region=$REGION \
  --vm-start-schedule="0 9 * * 1-5" \
  --vm-stop-schedule="0 12 * * 1-5" \
  --timezone=$ZONA_HORARIA

gcloud compute instances add-resource-policies $VM \
  --zone=$ZONE --resource-policies=horario-vm
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

# la e2-micro trae 1 GB de RAM: 2 GB de swap
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
docker compose up -d
```

Si tu repo es privado, `git clone` te pedirá un token de acceso de GitHub.

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
2. Importa y activa los workflows (en la VM):
   ```bash
   docker exec -u node n8n n8n import:workflow --separate --input=/workflows
   for id in $(docker exec -u node n8n n8n list:workflow --onlyId); do
     docker exec -u node n8n n8n publish:workflow --id=$id
   done
   docker compose restart n8n
   ```

## Despliegue continuo automático

El despliegue está 100% automatizado y no requiere intervención manual:

1. **Al encenderse la VM (9:00 AM L-V):** El metadato `startup-script` de Compute Engine ejecuta `/usr/local/bin/actualizar-n8n.sh`, que hace `git pull origin main`, levanta Docker, importa y publica los 8 workflows en n8n y reinicia el servicio.
2. **Durante la ventana de ejecución (9:00 a 12:00):** Un cron job (`/etc/cron.d/jobsearch-autoupdate`) verifica GitHub cada 5 minutos. Si hay nuevos commits en `main`, sincroniza y recarga n8n en caliente.
3. **En GitHub:** GitHub Actions (`.github/workflows/ci.yml`) valida la integridad y sintaxis JSON de todos los workflows en cada push.

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

## Costos

- *Facturación → Informes*: filtra por el proyecto y confirma que Compute
  Engine está en $0.
- La IP externa de la VM es efímera y cambia en cada encendido; no se usa para
  nada, así que no hace falta reservarla (una IP estática con la VM apagada sí
  cobra).
