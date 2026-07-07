# Configuración magic link (Supabase)

El login usa **enlace mágico** enviado por email. No requiere editar plantillas (plan gratuito).

## 1. Redirect URL en Supabase

Dashboard → **Authentication** → **URL Configuration** → **Redirect URLs**

Añade:

```
matchpay://login-callback
```

(Puedes mantener temporalmente `padel-cobro://login-callback` si hay usuarios con builds antiguos.)

## 2. Provider Email

Dashboard → **Authentication** → **Providers** → **Email**

- Email habilitado
- La plantilla por defecto de magic link incluye el enlace; el usuario lo abre y vuelve a la app

## 3. Deep link Android

En `AndroidManifest.xml` ya está configurado:

- Scheme: `matchpay`
- Host: `login-callback`

## 4. Trigger de perfiles

Ejecuta en SQL Editor la migración **`003_email_profiles.sql`**, que:

- Añade la columna `email` en `profiles`
- Permite perfiles pre-creados por el organizador (sin login previo)
- Al hacer magic link, fusiona el perfil existente con el UUID de `auth.users` si el email coincide

## 5. Marcar organizador

```sql
UPDATE public.profiles
SET role = 'organizer', nombre = 'Tu nombre'
WHERE lower(trim(email)) = lower(trim('tu@email.com'));
```
