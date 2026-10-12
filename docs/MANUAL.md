# 📘 Manual de usuario · Job Search Automation

Guía de uso diario: qué significa cada columna de la planilla, qué datos personales maneja el
sistema y qué protege. Para la instalación y el despliegue vuelve al [README](../README.md).

> Es un sistema **self-hosted** y personal: no tiene demo pública. Corre en tu propia VM y trabaja
> con tu hoja de vida, tu Google Drive y tu Telegram.

## Contenido

1. [En pocas palabras](#1-en-pocas-palabras)
2. [Paso a paso](#2-paso-a-paso)
3. [Qué información se maneja y dónde queda](#3-qué-información-se-maneja-y-dónde-queda)
4. [Seguridad: qué se garantiza](#4-seguridad-qué-se-garantiza)
5. [Límites y recomendaciones](#5-límites-y-recomendaciones)

---

## 1. En pocas palabras

Cada mañana de lunes a viernes, el sistema revisa cuatro portales de empleo, descarta lo que no
encaja, pide a una IA (Gemini) que califique cada oferta contra tu hoja de vida (HV) y se queda con
las 5 mejores de cada portal con **match ≥ 90 %**. Para ellas genera una HV adaptada (sin inventar
experiencia) en Google Docs y PDF, y te avisa por Telegram.

![Arquitectura](arquitectura.svg)

## 2. Paso a paso

### 2.1 La planilla (Google Sheet)

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

### 2.2 Rutina diaria (hora local)

| Hora | Qué pasa |
|---|---|
| 9:05 – 9:50 | Recolección de los cuatro portales |
| 10:05 – 11:35 (cada 15 min) | Generación de HV adaptadas y avisos por Telegram |
| 11:40 (viernes) | Limpieza del Drive: HV con más de 15 días a la papelera |
| 11:45 | Resumen diario por Telegram |
| 11:52 (viernes) | Métricas semanales del embudo |

### 2.3 Antes de postularte

1. Abre el Google Doc de la oferta.
2. Revisa `posible_alucinacion` y corrige lo que no sea cierto.
3. Sube el **PDF**. Si corregiste el Doc, descarga un PDF nuevo (*Archivo → Descargar → PDF*).
4. Actualiza `fecha_postulacion` y `estado`.

## 3. Qué información se maneja y dónde queda

| Dato | Para qué se usa | Dónde queda |
|---|---|---|
| Tu HV base (experiencia, formación, contacto, enlaces) | Calificar ofertas y generar HV adaptadas | Variable `HV_BASE_TEXT` del `.env` en la VM; se envía a la API de Gemini en cada evaluación y generación |
| Ofertas de empleo | Seleccionar las mejores | Tu Google Sheet; las descartadas se recuerdan 21 días para no reevaluarlas |
| HV adaptadas (Doc y PDF) | Postularte | Carpeta `HV` de tu Drive; se borran a los 15 días (recuperables 30 días en la papelera) |
| Credenciales (Gemini, Google OAuth2, Telegram) | Conectar los servicios | `.env` y credenciales de n8n en la VM; nunca en el repositorio |

## 4. Seguridad: qué se garantiza

- **Todo corre en tu infraestructura:** n8n self-hosted en tu VM de Google Cloud; no hay un
  servidor compartido con otras personas.
- **Secretos fuera del repositorio:** API keys y tokens en el `.env` de la VM, excluido por
  `.gitignore`; el acceso a Google usa OAuth2 con tu propia app.
- **Sin inventar datos:** el nombre y la línea de contacto se copian textuales de tu HV base; la IA
  no puede inventar experiencia, empresas, títulos ni certificaciones, y el chequeo
  anti-alucinación marca cualquier término nuevo.
- **Retención limitada** de las HV generadas en el Drive (15 días).
- **VM encendida solo 3 horas al día** (9:00 a 12:00), lo que reduce su exposición.

## 5. Límites y recomendaciones

- **Tu HV se envía a un proveedor de IA (Google Gemini)** en cada evaluación: no incluyas datos que
  no pondrías en una postulación (documento de identidad, dirección exacta).
- En el **nivel gratuito** de la API de Gemini, los términos de Google permiten usar lo que envías
  (tu HV y las ofertas) para mejorar sus productos. Si no quieres eso, usa una key de un proyecto
  con facturación (nivel de pago).
- Entra a n8n solo por el túnel SSH del despliegue (`localhost:5678`); no abras ese puerto a internet.
- Revisa siempre la HV adaptada antes de enviarla.
