package com.example.pdf_watermark_remover

import android.os.Handler
import android.os.Looper
import com.chaquo.python.PyObject
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Hosts the PDF engine, which is Python code embedded in this app (Chaquopy).
 *
 * Dart talks to it over the "pdfwm/engine" channel. Every call runs on one background thread, so
 * documents are processed one at a time and the UI thread never waits for Python. Files are
 * exchanged on disk inside the app's private cache folder; only small JSON strings cross the
 * channel. Nothing here uses the network.
 */
class MainActivity : FlutterActivity() {
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val jobsRoot: File by lazy { File(cacheDir, "pdfwm/jobs").also { it.mkdirs() } }
    private var pythonReady = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result -> handle(call, result) }
    }

    override fun onDestroy() {
        super.onDestroy()
        executor.shutdown()
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "paths" -> result.success(mapOf("jobsRoot" to jobsRoot.absolutePath))
            "info" -> runPython(result) { module().callAttr("info").toString() }
            "selfTest" -> runPython(result) {
                module().callAttr("self_test", File(cacheDir, "pdfwm").absolutePath).toString()
            }
            "newJob" -> {
                // Dart copies the chosen PDF into <dir>/original.pdf, then calls "analyze".
                val id = UUID.randomUUID().toString()
                val dir = File(jobsRoot, id)
                if (!dir.mkdirs()) return result.error("disk_error", "cannot create job folder", null)
                result.success("{\"job_id\":\"$id\",\"dir\":${jsonString(dir.absolutePath)}}")
            }
            "analyze" -> {
                val job = jobDir(call.argument<String>("jobId"))
                    ?: return result.error("bad_arguments", "unknown job", null)
                val filename = call.argument<String>("filename") ?: "document.pdf"
                runPython(result) {
                    module().callAttr("analyze", job.absolutePath, filename).toString()
                }
            }
            "remove" -> {
                val job = jobDir(call.argument<String>("jobId"))
                    ?: return result.error("bad_arguments", "unknown job", null)
                val mode = call.argument<String>("mode") ?: "auto"
                val area = call.argument<String>("area") ?: "{}"
                val applyTo = call.argument<String>("applyTo") ?: "all_pages"
                runPython(result) {
                    module().callAttr("remove", job.absolutePath, mode, area, applyTo).toString()
                }
            }
            "delete" -> {
                val job = jobDir(call.argument<String>("jobId"))
                    ?: return result.error("bad_arguments", "unknown job", null)
                // Runs after any removal that is still using the folder.
                executor.execute { job.deleteRecursively() }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Only folders that this class created (UUID names) are ever touched. */
    private fun jobDir(id: String?): File? {
        if (id == null || !UUID_PATTERN.matches(id)) return null
        return File(jobsRoot, id)
    }

    private fun jsonString(value: String): String =
        "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""

    private fun module(): PyObject = Python.getInstance().getModule("pdfwm_mobile")

    private fun ensurePython() {
        if (pythonReady) return
        if (!Python.isStarted()) Python.start(AndroidPlatform(applicationContext))
        // Folders left by an earlier run (crash, killed app) are removed after an hour.
        module().callAttr("purge", jobsRoot.absolutePath, 3600.0)
        pythonReady = true
    }

    private fun runPython(result: MethodChannel.Result, block: () -> String) {
        executor.execute {
            try {
                ensurePython()
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (error: Throwable) {
                // The message names the failing Python step, never document content.
                val message = "${error.javaClass.simpleName}: ${error.message?.take(300) ?: ""}"
                mainHandler.post { result.error("engine_error", message, null) }
            }
        }
    }

    companion object {
        private const val CHANNEL = "pdfwm/engine"
        private val UUID_PATTERN =
            Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
    }
}
