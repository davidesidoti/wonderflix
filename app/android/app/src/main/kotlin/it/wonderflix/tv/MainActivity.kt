package it.wonderflix.tv

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
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
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        players?.disposeAll()
        players = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
