# Google Sign-In (Kloovi / Supabase)

El login principal es **Continuar con Google**. El magic link sigue como alternativa (“Usar correo”).

Package Android: `com.matchpay.app` · iOS bundle: `com.matchpay.app`

## 1. Google Cloud Console

1. Abre [Google Cloud Console](https://console.cloud.google.com/) → el mismo proyecto de Firebase/FCM si ya lo tienes.
2. **APIs & Services → Credentials → Create credentials → OAuth client ID**

Crea **tres** clients (mínimo Web + Android):

### A) Web application (obligatorio)

- Tipo: **Web application**
- Anota el **Client ID** (`….apps.googleusercontent.com`) → es `GOOGLE_WEB_CLIENT_ID`
- Anota el **Client secret** → va en Supabase (paso 2)

### B) Android

- Tipo: **Android**
- Package name: `com.matchpay.app`
- SHA-1 (debug):

```bash
keytool -list -v -alias androiddebugkey \
  -keystore ~/.android/debug.keystore -storepass android -keypass android
```

- SHA-1 (release): el de tu keystore de Play / `key.properties`

### C) iOS (si compilas iPhone)

- Tipo: **iOS**
- Bundle ID: `com.matchpay.app`
- Anota el Client ID → `GOOGLE_IOS_CLIENT_ID`
- En `ios/Runner/Info.plist`, añade un URL scheme con el **Reversed Client ID**
  (aparece en el detalle del client iOS / en `GoogleService-Info.plist`).

## 2. Supabase Dashboard

**Authentication → Providers → Google**

- Enable Google
- **Client ID**: el de tipo **Web** (y, si tienes, también el iOS separado por coma; el Web primero)
- **Client Secret**: el secret del client Web
- En iOS nativo: marca **Skip nonce check** si lo pide la doc de Supabase

No hace falta redirect `matchpay://` para Google nativo (sí sigue haciendo falta para magic link).

## 3. Compilar la app

El botón de Google **solo aparece** si pasas el Web Client ID:

```bash
flutter run \
  --dart-define=GOOGLE_WEB_CLIENT_ID=TU_WEB_CLIENT_ID.apps.googleusercontent.com \
  --dart-define=GOOGLE_IOS_CLIENT_ID=TU_IOS_CLIENT_ID.apps.googleusercontent.com
```

(En Android puedes omitir `GOOGLE_IOS_CLIENT_ID`.)

Si usas scripts / IDE: añade las mismas defines que ya usas para `SUPABASE_*` / `FIREBASE_*`.

## 4. Probar

1. Hot restart / rebuild (no solo hot reload tras añadir el define).
2. Login → **Continuar con Google** → elige cuenta.
3. Misma cuenta que ya usó magic link (mismo email) debería fusionar con el perfil existente vía `handle_new_user`.
4. Sin cuenta Google → “Usar correo (enlace mágico)” igual que antes.

## 5. Errores frecuentes

| Síntoma | Causa típica |
|--------|----------------|
| No aparece el botón Google | Falta `GOOGLE_WEB_CLIENT_ID` en el run |
| `10:` / ApiException | SHA-1 debug/release no registrado en client Android |
| Provider not enabled | Google desactivado en Supabase |
| No ID Token | Falta client **Web** como `serverClientId` |
| iOS no abre Google | Falta URL scheme del reversed client ID |
