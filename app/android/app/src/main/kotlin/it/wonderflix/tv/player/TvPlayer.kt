package it.wonderflix.tv.player

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView
import androidx.media3.ui.SubtitleView

/** Un `ExoPlayer` dietro il contratto del canale; gli eventi escono da [emit]. */
@OptIn(UnstableApi::class)
class TvPlayer(context: Context, private val id: Int, private val emit: (String, Any?) -> Unit) :
    Player.Listener {

    private val player = ExoPlayer.Builder(context.applicationContext).build()
    private val handler = Handler(Looper.getMainLooper())
    private val tick = object : Runnable {
        override fun run() {
            emitPosition()
            handler.postDelayed(this, TICK_MS)
        }
    }

    private var view: PlayerView? = null
    private var subtitleScale = 1f
    private var dataSourceFactory: DefaultHttpDataSource.Factory? = null
    private var mediaItem: MediaItem? = null
    private var awaitingLoad = false
    private var buffering = false
    private var duration = C.TIME_UNSET
    private var pendingSubtitle: PendingSubtitle? = null
    private var released = false

    init {
        player.addListener(this)
    }

    fun attach(view: PlayerView) {
        if (released) return
        this.view?.player = null
        this.view = view
        view.player = player
        view.keepScreenOn = player.isPlaying
        applySubtitleScale()
    }

    fun detach(view: PlayerView) {
        if (this.view !== view) return
        view.player = null
        view.keepScreenOn = false
        this.view = null
    }

    fun open(url: String, headers: Map<String, String>, startMs: Long) {
        finishPendingSubtitle(null)
        emit("completed", false)
        awaitingLoad = true
        duration = C.TIME_UNSET
        dataSourceFactory = DefaultHttpDataSource.Factory()
            .setDefaultRequestProperties(headers)
            .setConnectTimeoutMs(HTTP_TIMEOUT_MS)
            .setReadTimeoutMs(HTTP_TIMEOUT_MS)
        mediaItem = MediaItem.Builder()
            .setUri(url)
            .setMimeType(if (url.contains(".m3u8")) MimeTypes.APPLICATION_M3U8 else null)
            .build()
        // Le scelte di tracce del file precedente non valgono per questo.
        player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
            .clearOverrides()
            .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
            .build()
        player.playWhenReady = false
        prepare(startMs)
    }

    // DefaultMediaSourceFactory sceglie HlsMediaSource (mime M3U8) o ProgressiveMediaSource
    // e unisce i SubtitleConfiguration, che le due factory da sole ignorerebbero.
    private fun prepare(startMs: Long) {
        val source = DefaultMediaSourceFactory(dataSourceFactory!!).createMediaSource(mediaItem!!)
        player.setMediaSource(source, startMs)
        player.prepare()
    }

    fun stop() {
        finishPendingSubtitle(null)
        awaitingLoad = false
        player.stop()
        player.clearMediaItems()
        mediaItem = null
    }

    fun play() = player.play()

    fun pause() = player.pause()

    fun seek(ms: Long) {
        player.seekTo(ms)
        emitPosition()
    }

    fun setVolume(volume: Float) {
        player.volume = volume
    }

    fun setRate(rate: Float) {
        player.playbackParameters = PlaybackParameters(rate)
    }

    fun tracks(): List<Map<String, Any?>> {
        val list = mutableListOf<Map<String, Any?>>()
        player.currentTracks.groups.forEachIndexed { g, group ->
            val type = typeName(group.type) ?: return@forEachIndexed
            for (t in 0 until group.length) {
                val format = group.getTrackFormat(t)
                list += mapOf(
                    "id" to "$g:$t",
                    "type" to type,
                    "formatId" to format.id,
                    "title" to format.label,
                    "language" to format.language,
                )
            }
        }
        return list
    }

    fun selectAudio(track: String?) = select(C.TRACK_TYPE_AUDIO, track)

    fun selectSubtitle(track: String?) = select(C.TRACK_TYPE_TEXT, track)

    private fun select(trackType: Int, track: String?) {
        val builder = player.trackSelectionParameters.buildUpon()
        if (track == null) {
            builder.setTrackTypeDisabled(trackType, true)
        } else {
            val parts = track.split(':').map { it.toIntOrNull() }
            val group = parts.getOrNull(0)?.let { player.currentTracks.groups.getOrNull(it) }
            val index = parts.getOrNull(1)
            if (parts.size != 2 || group == null || group.type != trackType || index == null || index !in 0 until group.length) {
                Log.w(TAG, "traccia sconosciuta: $track")
                return
            }
            builder.setTrackTypeDisabled(trackType, false)
                .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, index))
        }
        player.trackSelectionParameters = builder.build()
    }

    fun addSubtitle(url: String, title: String?, language: String?, done: (String?) -> Unit) {
        val item = mediaItem ?: return done(null)
        finishPendingSubtitle(null)
        val config = MediaItem.SubtitleConfiguration.Builder(Uri.parse(url))
            .setMimeType(subtitleMime(url))
            .setLabel(title)
            .setLanguage(language)
            .build()
        val configs = item.localConfiguration!!.subtitleConfigurations + config
        mediaItem = item.buildUpon().setSubtitleConfigurations(configs).build()
        // Dopo la nuova preparazione i gruppi sono altri: la scelta dell'audio va rifatta.
        val audio = player.trackSelectionParameters.overrides.values
            .firstOrNull { it.type == C.TRACK_TYPE_AUDIO }
            ?.let { o -> o.trackIndices.firstOrNull()?.let { o.mediaTrackGroup.getFormat(it).id } }
        // Il file è il periodo 0, l'n-esimo sottotitolo esterno il periodo n.
        val pending = PendingSubtitle("${configs.size}:", audio, done)
        pendingSubtitle = pending
        handler.postDelayed(pending.timeout, SUBTITLE_TIMEOUT_MS)
        prepare(player.currentPosition)
    }

    private fun subtitleMime(url: String): String? {
        val path = (Uri.parse(url).path ?: url).lowercase()
        return when {
            path.endsWith(".ass") || path.endsWith(".ssa") -> MimeTypes.TEXT_SSA
            path.endsWith(".srt") -> MimeTypes.APPLICATION_SUBRIP
            path.endsWith(".vtt") -> MimeTypes.TEXT_VTT
            else -> null
        }
    }

    private fun finishPendingSubtitle(trackId: String?) {
        val pending = pendingSubtitle ?: return
        pendingSubtitle = null
        handler.removeCallbacks(pending.timeout)
        pending.done(trackId)
    }

    /**
     * Il sottotitolo in attesa non è arrivato (errore o 10 s): toglie il suo
     * SubtitleConfiguration, così non torna nei prossimi addSubtitle, e riprepara
     * alla posizione attuale mantenendo play/pausa. Con la stessa struttura di prima
     * i gruppi tornano uguali e le scelte di tracce precedenti valgono di nuovo.
     */
    private fun dropPendingSubtitle() {
        val item = mediaItem
        finishPendingSubtitle(null)
        if (item == null) return
        val configs = item.localConfiguration!!.subtitleConfigurations
        mediaItem = item.buildUpon().setSubtitleConfigurations(configs.dropLast(1)).build()
        prepare(player.currentPosition)
    }

    fun setSubtitleDelay(ms: Long) {
        Log.w(TAG, "setSubtitleDelay($ms ms) ignorato: Media3 non ha un ritardo dei sottotitoli")
    }

    fun setSubtitleScale(scale: Float) {
        subtitleScale = scale
        applySubtitleScale()
    }

    private fun applySubtitleScale() {
        view?.subtitleView?.setFractionalTextSize(SubtitleView.DEFAULT_TEXT_SIZE_FRACTION * subtitleScale)
    }

    fun dispose() {
        if (released) return
        released = true
        handler.removeCallbacks(tick)
        finishPendingSubtitle(null)
        view?.let { detach(it) }
        player.removeListener(this)
        player.release()
    }

    private fun emitPosition() {
        emit("position", player.currentPosition)
        emit("buffer", player.bufferedPosition)
    }

    private fun emitDuration() {
        val d = player.duration
        if (d != C.TIME_UNSET && d != duration) {
            duration = d
            emit("duration", d)
        }
    }

    override fun onPlaybackStateChanged(playbackState: Int) {
        val nowBuffering = playbackState == Player.STATE_BUFFERING
        if (nowBuffering != buffering) {
            buffering = nowBuffering
            emit("buffering", nowBuffering)
        }
        when (playbackState) {
            Player.STATE_READY -> {
                emitDuration()
                if (awaitingLoad) {
                    awaitingLoad = false
                    emit("loaded", null)
                    emitPosition()
                }
            }
            Player.STATE_ENDED -> emit("completed", true)
        }
    }

    override fun onTimelineChanged(timeline: Timeline, reason: Int) = emitDuration()

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        emit("playing", isPlaying)
        view?.keepScreenOn = isPlaying // niente salvaschermo durante il film
        handler.removeCallbacks(tick)
        if (isPlaying) handler.post(tick) else emitPosition()
    }

    override fun onPlayerError(error: PlaybackException) {
        Log.e(TAG, "player $id", error)
        // Durante addSubtitle l'errore è (quasi certamente) del sottotitolo: il film continua
        // senza. Se invece era del file, la nuova preparazione fallisce di nuovo e arriva qui.
        if (pendingSubtitle != null) return dropPendingSubtitle()
        awaitingLoad = false
        emit("error", error.message?.let { "${error.errorCodeName}: $it" } ?: error.errorCodeName)
    }

    override fun onRenderedFirstFrame() = emit("firstFrame", null)

    override fun onTracksChanged(tracks: Tracks) {
        val pending = pendingSubtitle ?: return
        val subtitle = find(tracks, C.TRACK_TYPE_TEXT) { it.id?.startsWith(pending.prefix) == true } ?: return
        pending.audioFormatId?.let { old ->
            val merged = if (':' in old) old else "0:$old"
            find(tracks, C.TRACK_TYPE_AUDIO) { it.id == merged }?.let { selectAudio(it) }
        }
        selectSubtitle(subtitle)
        finishPendingSubtitle(subtitle)
    }

    private fun find(tracks: Tracks, type: Int, match: (Format) -> Boolean): String? {
        tracks.groups.forEachIndexed { g, group ->
            if (group.type != type) return@forEachIndexed
            for (t in 0 until group.length) if (match(group.getTrackFormat(t))) return "$g:$t"
        }
        return null
    }

    private fun typeName(type: Int) = when (type) {
        C.TRACK_TYPE_VIDEO -> "video"
        C.TRACK_TYPE_AUDIO -> "audio"
        C.TRACK_TYPE_TEXT -> "subtitle"
        else -> null
    }

    private inner class PendingSubtitle(
        val prefix: String,
        val audioFormatId: String?,
        val done: (String?) -> Unit,
    ) {
        val timeout = Runnable { if (pendingSubtitle === this) dropPendingSubtitle() }
    }

    private companion object {
        const val TAG = "TvPlayer"
        const val TICK_MS = 250L
        const val HTTP_TIMEOUT_MS = 60_000
        const val SUBTITLE_TIMEOUT_MS = 10_000L
    }
}
