# 📘 Manual de usuario · Job Search Automation

Guía de uso diario: qué significa cada columna de la planilla, qué datos personales maneja el
sistema y qué protege. Para la instalación y el despliegue vuelve al [README](../README.md).

> Es un sistema **self-hosted** y personal: no tiene demo pública. Corre en tu propia VM y trabaja
> con tu hoja de vida, tu Google Drive y tu Telegram.

## Contenido

1. [Proyecto: objetivos y alcances](#1-proyecto-objetivos-y-alcances)
2. [Glosario](#2-glosario)
3. [Plataformas, base de datos y servicios](#3-plataformas-base-de-datos-y-servicios)
4. [Paso a paso](#4-paso-a-paso)
5. [Seguridad: tu información protegida](#5-seguridad-tu-información-protegida)
6. [Agradecimientos](#6-agradecimientos)

---

## 1. Proyecto: objetivos y alcances

### Objetivo

Cada mañana de lunes a viernes, el sistema revisa cuatro portales de empleo, descarta lo que no
encaja, pide a una IA (Gemini) que califique cada oferta contra tu hoja de vida (HV) y se queda con
las 5 mejores de cada portal con **match ≥ 83 %** (filtrando que la oferta tenga máximo 3 días de publicación y salario ≥ $3.000.000 COP o no especificado). Para ellas genera una HV adaptada (sin inventar
experiencia) en Google Docs y PDF, y te avisa por Telegram.

![Arquitectura](arquitectura.svg)

### Límites

- **Tu HV se envía a un proveedor de IA (Google Gemini)** en cada evaluación: no incluyas datos que
  no pondrías en una postulación (documento de identidad, dirección exacta).
- Según el tipo de cuenta, los términos de Google para la API de Gemini pueden permitir usar lo que
  envías (tu HV y las ofertas) para mejorar sus productos: revísalos antes de usar tu propia key.
- Entra a n8n solo por el túnel SSH del despliegue (`localhost:5678`); no abras ese puerto a internet.
- Revisa siempre la HV adaptada antes de enviarla.

## 2. Glosario

Palabras técnicas que aparecen en este manual, explicadas en lenguaje simple.

| Término | Qué significa |
|---|---|
| **API** | Puerta de entrada de un programa para que otros programas le pidan o le envíen datos. |
| **Base de datos** | Lugar donde la aplicación guarda la información de forma ordenada y permanente. |
| **Despliegue** | Publicar una nueva versión de la aplicación para que esté disponible en internet. |
| **Métricas** | Medidas de un equipo como uso de CPU, memoria, disco o red. |
| **Navegador** | Programa con el que abres páginas web: Chrome, Edge, Firefox, Safari. |
| **Nube** | Servidores de una empresa (Amazon, Microsoft, Google, Oracle…) donde la aplicación funciona sin depender de un computador propio. |
| **PDF** | Formato de documento que se ve igual en cualquier equipo. |
| **Servidor** | Computador en la nube que atiende las peticiones de la aplicación. |
| **Token** | Credencial temporal que la aplicación te entrega al iniciar sesión, en lugar de enviar tu contraseña en cada paso. |
| **Variables de entorno / secretos** | Claves y contraseñas internas de la aplicación, guardadas fuera del código para que no queden expuestas. |

## 3. Plataformas, base de datos y servicios

Qué servicio de nube, base de datos o API usa el proyecto y para qué sirve cada uno.

| Plataforma | Tipo | Qué hace en el proyecto |
|---|---|---|
| ![Google Cloud](https://img.shields.io/badge/Google_Cloud-4285F4?style=for-the-badge&logo=googlecloud&logoColor=white) | Nube | Una VM con Docker corre n8n; una política de horario la enciende a las 9:00 y la apaga a las 12:00, de lunes a viernes. |
| ![n8n](https://img.shields.io/badge/n8n-EA4B71?style=for-the-badge&logo=n8n&logoColor=white) | Automatización | Orquesta los workflows: recolección, filtro, evaluación con IA, HV adaptada, resumen y métricas. |
| ![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white) | Contenedores | Empaqueta n8n con `docker-compose.yml`, igual en local y en la VM. |
| ![Gemini](https://img.shields.io/badge/Gemini-8E75B2?style=for-the-badge&logo=googlegemini&logoColor=white) | API / servicio externo (IA) | Califica el % de compatibilidad de cada oferta y redacta la HV adaptada. |
| ![Google Sheets](https://img.shields.io/badge/Google_Sheets-34A853?style=for-the-badge&logo=googlesheets&logoColor=white) | API / servicio externo | Funciona como CRM: guarda las ofertas elegidas y coordina los workflows. |
| ![Google Docs](https://img.shields.io/badge/Google_Docs-4285F4?style=for-the-badge&logo=googledocs&logoColor=white) | API / servicio externo | Guarda cada HV adaptada con formato real y enlaces clicables. |
| ![Google Drive](https://img.shields.io/badge/Google_Drive-0F9D58?style=for-the-badge&logo=googledrive&logoColor=white) | API / servicio externo | Guarda Doc y PDF de cada HV en la carpeta `HV`, y los viernes manda a la papelera los de más de 15 días. |
| ![Telegram](https://img.shields.io/badge/Telegram-26A5E4?style=for-the-badge&logo=telegram&logoColor=white) | API / servicio externo | Avisa cada HV lista y envía el resumen del día y las métricas semanales. |

## 4. Paso a paso

### 4.1 La planilla (Google Sheet)

Cada fila es una oferta elegida:

| Columna | Qué contiene | ¿La editas tú? |
|---|---|---|
| `fuente` | Portal de origen | No |
| `titulo`, `empresa`, `ubicacion`, `url` | Datos de la oferta | No |
| `match_pct` | Porcentaje de compatibilidad calculado por la IA | No |
| `ats_tip` | Sugerencia para pasar filtros ATS | No |
| `perfil_sugerido` | Perfil de búsqueda con el que encaja | No |
| `generar` | `auto` (la eligió el sistema) o `X` para pedir una HV a mano | Sí |
| `hv_adaptada` | Enlace al Google Doc de la HV adaptada | Bórralo para regenerarla |
| `hv_pdf` | Enlace al PDF listo para subir | Bórralo para regenerarla |
| `posible_alucinacion` | Términos de la HV generada que no están en tu HV base, o `FALTAN ENLACES` | Revísalo antes de enviar |
| `fecha_postulacion`, `estado` | Tu seguimiento | Sí |

### 4.2 Rutina diaria (hora local)

| Hora | Qué pasa |
|---|---|
| 9:05 – 9:50 | Recolección de los cuatro portales |
| 10:05 – 11:35 (cada 15 min) | Generación de HV adaptadas y avisos por Telegram |
| 11:40 (viernes) | Limpieza del Drive: HV con más de 15 días a la papelera |
| 11:45 | Resumen diario por Telegram |
| 11:52 (viernes) | Métricas semanales del embudo |

### 4.3 Antes de postularte

1. Abre el Google Doc de la oferta.
2. Revisa `posible_alucinacion` y corrige lo que no sea cierto.
3. Sube el **PDF**. Si corregiste el Doc, descarga un PDF nuevo (*Archivo → Descargar → PDF*).
4. Actualiza `fecha_postulacion` y `estado`.

## 5. Seguridad: tu información protegida

Tu confianza es lo primero: la plataforma solo pide los datos necesarios para funcionar, los protege y no los comparte con terceros. Esto es lo que se guarda y cómo se protege.

### Qué datos se guardan y dónde

| Dato | Para qué se usa | Dónde queda |
|---|---|---|
| Tu HV base (experiencia, formación, contacto, enlaces) | Calificar ofertas y generar HV adaptadas | Variable `HV_BASE_TEXT` del `.env` en la VM; se envía a la API de Gemini en cada evaluación y generación |
| Ofertas de empleo | Seleccionar las mejores | Tu Google Sheet; las descartadas se recuerdan 21 días para no reevaluarlas |
| HV adaptadas (Doc y PDF) | Postularte | Carpeta `HV` de tu Drive; se borran a los 15 días (recuperables 30 días en la papelera) |
| Credenciales (Gemini, Google OAuth2, Telegram) | Conectar los servicios | `.env` y credenciales de n8n en la VM; nunca en el repositorio |

### Cómo se protege tu información

- **Todo corre en tu infraestructura:** n8n self-hosted en tu VM de Google Cloud; no hay un
  servidor compartido con otras personas.
- **Secretos fuera del repositorio:** API keys y tokens en el `.env` de la VM, excluido por
  `.gitignore`; el acceso a Google usa OAuth2 con tu propia app.
- **Sin inventar datos:** el nombre y la línea de contacto se copian textuales de tu HV base; la IA
  no puede inventar experiencia, empresas, títulos ni certificaciones, y el chequeo
  anti-alucinación marca cualquier término nuevo.
- **Retención limitada** de las HV generadas en el Drive (15 días).
- **Al día en seguridad:** n8n se mantiene solo en su última versión estable: cada día hábil
  se revisa si salió una nueva y, si es así, se aplica automáticamente antes de que la VM
  se encienda.
- **VM encendida solo 3 horas al día** (9:00 a 12:00), lo que reduce su exposición.

## 6. Agradecimientos

A mi familia, por su apoyo incondicional, su paciencia y por creer en cada proyecto incluso cuando apenas era una idea. Este trabajo también es de ustedes.

Y a ti, que usas esta plataforma: cada prueba, comentario y sugerencia ayuda a que siga mejorando.
