# Sitio web Kloovi (`kloovi.app`)

Landing + Política de Privacidad + Términos de Servicio (estático, listo para Vercel).

## URLs

| Ruta | Uso |
|------|-----|
| `https://kloovi.app/` | Landing |
| `https://kloovi.app/privacy` | Play Console / OAuth Google |
| `https://kloovi.app/terms` | Play Console / OAuth Google |

## Deploy en Vercel (gratis)

1. Entra a [vercel.com](https://vercel.com) con GitHub (o sube la carpeta).
2. **Add New Project** → importa este repo (o solo la carpeta `website`).
3. Configura:
   - **Root Directory:** `website`
   - **Framework Preset:** Other
   - Build Command: *(vacío)*
   - Output Directory: `.` *(o déjalo vacío / `website` si root ya es website)*
4. Deploy.
5. **Domains** → agrega `kloovi.app` y `www.kloovi.app`.
6. En tu registrador de dominio, crea los DNS que Vercel indique (casi siempre registros `A`/`CNAME`).

## Play Console

- Privacy policy: `https://kloovi.app/privacy`
- En **Financial features**: declara que **no** ofreces servicios financieros / pagos. Kloovi solo administra comprobantes; el dinero se mueve fuera de la app.

## Google Auth / OAuth

En la pantalla de consentimiento OAuth, enlaza:

- Privacy: `https://kloovi.app/privacy`
- Terms: `https://kloovi.app/terms`

## Nota legal

Los textos están pensados para dejar claro el modelo real de Kloovi. No reemplazan asesoría de un abogado; conviene revisarlos antes de producción masiva.
