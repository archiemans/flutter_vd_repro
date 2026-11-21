package dev.repro.vd_stale_frames_repro

import android.content.Context
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/** Creates [CounterPlatformView]s for the Dart `AndroidView('repro/counter')`. */
class CounterViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        CounterPlatformView(context)
}

class CounterPlatformView(context: Context) : PlatformView {
    private val view = CounterSurfaceView(context)
    override fun getView(): View = view
    override fun dispose() = view.stop()
}

/**
 * A SurfaceView (so Flutter hosts it in a virtual display) that draws about
 * 60 frames a second: an ever-increasing frame number, the surface size and
 * a background colour that changes every frame.
 *
 * The frame number only goes up. If the screen ever shows it going down, or
 * the size flipping between old values, Flutter is presenting stale frames.
 * If it stops changing while the app is in front, the view is frozen.
 */
class CounterSurfaceView(context: Context) : SurfaceView(context), SurfaceHolder.Callback {
    @Volatile private var running = false
    private var thread: Thread? = null
    private var frame = 0L

    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = 72f
        typeface = Typeface.MONOSPACE
    }

    init {
        holder.addCallback(this)
    }

    override fun surfaceCreated(holder: SurfaceHolder) = start()

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {}

    override fun surfaceDestroyed(holder: SurfaceHolder) = stop()

    private fun start() {
        if (running) return
        running = true
        thread = Thread({ loop() }, "counter-render").also { it.start() }
    }

    fun stop() {
        running = false
        thread?.join(500)
        thread = null
    }

    private fun loop() {
        while (running) {
            val canvas = try {
                holder.lockHardwareCanvas()
            } catch (e: Exception) {
                null
            }
            if (canvas != null) {
                frame++
                val hue = (frame * 3 % 360).toFloat()
                canvas.drawColor(Color.HSVToColor(floatArrayOf(hue, 0.6f, 0.45f)))
                canvas.drawText("frame $frame", 48f, 160f, text)
                canvas.drawText("${canvas.width} x ${canvas.height}", 48f, 260f, text)
                try {
                    holder.unlockCanvasAndPost(canvas)
                } catch (e: Exception) {
                    // Surface went away mid-frame; the next loop finds out.
                }
            }
            Thread.sleep(16)
        }
    }
}
