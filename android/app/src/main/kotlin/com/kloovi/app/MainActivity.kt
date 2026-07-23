package com.kloovi.app

import android.os.Bundle
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Mantiene el splash nativo hasta el primer frame de Flutter.
        installSplashScreen()
        super.onCreate(savedInstanceState)
    }
}
