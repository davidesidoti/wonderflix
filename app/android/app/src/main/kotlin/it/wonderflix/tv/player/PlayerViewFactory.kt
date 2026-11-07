package it.wonderflix.tv.player

import android.content.Context
import android.graphics.Color
import android.view.View
import android.view.ViewGroup
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/** Platform view `wonderflix/player_view`: la `PlayerView` del player `{id}`. */
@OptIn(UnstableApi::class)
class PlayerViewFactory(private val registry: PlayerRegistry) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val view = PlayerView(context).apply {
            useController = false
            resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
            setShutterBackgroundColor(Color.BLACK)
            setBackgroundColor(Color.BLACK)
            // I tasti del telecomando restano a Flutter, che disegna i controlli.
            isFocusable = false
            descendantFocusability = ViewGroup.FOCUS_BLOCK_DESCENDANTS
        }
        val id = ((args as? Map<*, *>)?.get("id") as? Number)?.toInt()
        val player = id?.let { registry.player(it) }
        player?.attach(view)
        return object : PlatformView {
            override fun getView(): View = view

            override fun dispose() {
                player?.detach(view)
            }
        }
    }
}
