package it.wonderflix.tv.player

import android.app.Activity
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.os.Build
import android.view.Display
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Canale `wonderflix/player`: un [TvPlayer] per id, un solo flusso di eventi per tutti. */
class PlayerRegistry(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val players = mutableMapOf<Int, TvPlayer>()
    private var nextId = 1
    private var sink: EventChannel.EventSink? = null

    init {
        MethodChannel(messenger, "wonderflix/player").setMethodCallHandler(this)
        EventChannel(messenger, "wonderflix/player/events").setStreamHandler(this)
    }

    fun player(id: Int): TvPlayer? = players[id]

    fun disposeAll() {
        players.values.forEach { it.dispose() }
        players.clear()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "create" -> {
                val id = nextId++
                players[id] = TvPlayer(activity, id) { type, value ->
                    sink?.success(mapOf("id" to id, "type" to type, "value" to value))
                }
                return result.success(id)
            }
            "decoderCapabilities" -> return result.success(decoderCapabilities())
        }
        // Un id già eliminato (o mancante): la chiamata viene ignorata.
        val id = call.argument<Number>("id")?.toInt()
        val player = id?.let { players[it] } ?: return result.success(null)
        when (call.method) {
            "open" -> player.open(
                call.argument<String>("url")!!,
                call.argument<Map<String, String>>("headers") ?: emptyMap(),
                call.argument<Number>("startMs")?.toLong() ?: 0L,
            )
            "stop" -> player.stop()
            "play" -> player.play()
            "pause" -> player.pause()
            "seek" -> player.seek(call.argument<Number>("ms")!!.toLong())
            "setVolume" -> player.setVolume(call.argument<Number>("volume")!!.toFloat())
            "setRate" -> player.setRate(call.argument<Number>("rate")!!.toFloat())
            "tracks" -> return result.success(player.tracks())
            "selectAudio" -> player.selectAudio(call.argument("track"))
            "selectSubtitle" -> player.selectSubtitle(call.argument("track"))
            "addSubtitle" -> return player.addSubtitle(
                call.argument<String>("url")!!,
                call.argument("title"),
                call.argument("language"),
            ) { result.success(it) }
            "setSubtitleDelay" -> player.setSubtitleDelay(call.argument<Number>("ms")!!.toLong())
            "setSubtitleScale" -> player.setSubtitleScale(call.argument<Number>("scale")!!.toFloat())
            "dispose" -> {
                players.remove(id)
                player.dispose()
            }
            else -> return result.notImplemented()
        }
        result.success(null)
    }

    private fun decoderCapabilities(): Map<String, Any> {
        val video = linkedMapOf<String, MutableMap<String, Any>>()
        val audio = linkedSetOf<String>()
        for (info in MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos) {
            if (info.isEncoder) continue
            for (mime in info.supportedTypes) {
                val caps = info.getCapabilitiesForType(mime)
                val videoCaps = caps.videoCapabilities
                if (videoCaps == null) {
                    // Audio: anche i decoder software (AAC e MP3 lo sono sempre su Android).
                    if (caps.audioCapabilities != null) audio += mime
                    continue
                }
                // image/heic e simili hanno videoCapabilities ma non sono video.
                if (!mime.startsWith("video/") || !isHardware(info)) continue
                // Il valore 2 è HEVCProfileMain10 ma anche AVCProfileMain, VP9Profile1, ...
                val tenBit = mime.equals(MediaFormat.MIMETYPE_VIDEO_HEVC, ignoreCase = true) && caps.profileLevels.any {
                    it.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10
                }
                // Più decoder per lo stesso mime (es. `.secure`): vale il migliore.
                val entry = video.getOrPut(mime) {
                    mutableMapOf("mime" to mime, "maxWidth" to 0, "maxHeight" to 0, "tenBit" to false)
                }
                entry["maxWidth"] = maxOf(entry["maxWidth"] as Int, videoCaps.supportedWidths.upper)
                entry["maxHeight"] = maxOf(entry["maxHeight"] as Int, videoCaps.supportedHeights.upper)
                entry["tenBit"] = entry["tenBit"] as Boolean || tenBit
            }
        }
        return mapOf("video" to video.values.toList(), "audio" to audio.toList(), "hdrTypes" to hdrTypes())
    }

    private fun isHardware(info: MediaCodecInfo): Boolean =
        if (Build.VERSION.SDK_INT >= 29) {
            info.isHardwareAccelerated
        } else {
            !info.name.startsWith("OMX.google.") && !info.name.startsWith("c2.android.")
        }

    private fun hdrTypes(): List<String> {
        if (Build.VERSION.SDK_INT < 24) return emptyList() // getHdrCapabilities è API 24
        @Suppress("DEPRECATION")
        val types = activity.windowManager.defaultDisplay.hdrCapabilities?.supportedHdrTypes
        return types?.toList()?.mapNotNull {
            when (it) {
                Display.HdrCapabilities.HDR_TYPE_HDR10 -> "HDR10"
                Display.HdrCapabilities.HDR_TYPE_HLG -> "HLG"
                Display.HdrCapabilities.HDR_TYPE_DOLBY_VISION -> "DOLBY_VISION"
                4 -> "HDR10_PLUS" // Display.HdrCapabilities.HDR_TYPE_HDR10_PLUS, API 29
                else -> null
            }
        } ?: emptyList()
    }
}
