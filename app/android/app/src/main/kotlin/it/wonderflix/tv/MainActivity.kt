package it.wonderflix.tv

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import it.wonderflix.tv.player.PlayerRegistry
import it.wonderflix.tv.player.PlayerViewFactory
import java.io.File

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
                when (call.method) {
                    "name" -> result.success(
                        mapOf(
                            "settingsName" to Settings.Global.getString(contentResolver, "device_name"),
                            "model" to Build.MODEL,
                        ),
                    )
                    "installApk" -> try {
                        result.success(installApk(File(call.argument<String>("path")!!)))
                    } catch (e: Exception) {
                        result.error("install_failed", e.toString(), null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // Aggiornamento (features/update): "needsPermission" apre le impostazioni del permesso e
    // non avvia nulla; l'utente torna e preme di nuovo Aggiorna.
    private fun installApk(apk: File): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            try {
                startActivity(
                    Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")),
                )
            } catch (e: ActivityNotFoundException) {
                // Fire OS vecchi: niente pagina per singola app.
                startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS))
            }
            return "needsPermission"
        }
        val uri = FileProvider.getUriForFile(this, "$packageName.updates", apk)
        startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        return "started"
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
