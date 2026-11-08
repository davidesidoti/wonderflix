package it.wonderflix.tv

import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import it.wonderflix.tv.player.PlayerRegistry
import it.wonderflix.tv.player.PlayerViewFactory

class MainActivity : FlutterActivity() {
    private var players: PlayerRegistry? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val registry = PlayerRegistry(this, flutterEngine.dartExecutor.binaryMessenger)
        players = registry
        flutterEngine.platformViewsController.registry
            .registerViewFactory("wonderflix/player_view", PlayerViewFactory(registry))
        // Nome scelto in Impostazioni → Il mio Fire TV, per l'elenco dispositivi di Jellyfin.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "wonderflix/device")
            .setMethodCallHandler { call, result ->
                if (call.method == "name") {
                    result.success(
                        mapOf(
                            "settingsName" to Settings.Global.getString(contentResolver, "device_name"),
                            "model" to Build.MODEL,
                        ),
                    )
                } else {
                    result.notImplemented()
                }
            }
    }

    // Home durante un film: niente audio, download e punto di ripresa che avanzano in background.
    override fun onStop() {
        players?.pauseAll()
        super.onStop()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        players?.disposeAll()
        players = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
