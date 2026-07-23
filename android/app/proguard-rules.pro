# Firebase / FCM / Crashlytics — R8 no debe eliminar ComponentRegistrars.
# Sin esto, initializeApp falla con:
# "FirebaseCrashlytics component is not present"
# y Probar marca error aunque un token antiguo siga recibiendo push.

-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class io.flutter.plugins.firebase.** { *; }

-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-keepattributes SourceFile,LineNumberTable
