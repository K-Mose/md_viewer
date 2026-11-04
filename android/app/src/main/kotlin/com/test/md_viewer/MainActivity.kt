package com.test.md_viewer

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileNotFoundException
import java.security.MessageDigest
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var openedFileChannel: MethodChannel? = null
    private var pendingPick: MethodChannel.Result? = null
    private var initialIntentHandled = false

    // content:// 읽기는 클라우드 제공자(드라이브 등)에서 느릴 수 있어 백그라운드에서 한다.
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // 외부 앱의 "연결 프로그램"으로 열린 파일
        openedFileChannel = MethodChannel(messenger, OPENED_FILE_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialFile" -> {
                        if (initialIntentHandled) {
                            result.success(null)
                        } else {
                            initialIntentHandled = true
                            val current = intent
                            runIo(result) { readExternalIntent(current) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // 앱 안의 파일 선택 / 최근 파일 다시 열기
        MethodChannel(messenger, DOCUMENTS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickDocument" -> pickDocument(result)
                "readDocument" -> {
                    val uri = call.argument<String>("value")?.let(Uri::parse)
                    if (uri == null) {
                        result.error("invalid_argument", "uri가 없습니다", null)
                    } else {
                        runIo(result) { readPersistedDocument(uri) }
                    }
                }
                "releaseDocument" -> {
                    call.argument<String>("value")?.let { releaseDocument(Uri.parse(it)) }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        initialIntentHandled = true
        io.execute {
            val file = try {
                readExternalIntent(intent)
            } catch (_: Exception) {
                null
            }
            if (file != null) main.post { openedFileChannel?.invokeMethod("fileOpened", file) }
        }
    }

    override fun onDestroy() {
        io.shutdown()
        super.onDestroy()
    }

    // ───────────────────────── 파일 선택 ─────────────────────────

    private fun pickDocument(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "이미 파일 선택 중입니다", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            // 오래된 기기는 .md를 octet-stream으로 분류하기도 해서 함께 허용하고, 확장자로 다시 거른다.
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("text/*", "application/octet-stream"))
        }
        pendingPick = result
        try {
            startActivityForResult(intent, REQUEST_PICK)
        } catch (e: Exception) {
            pendingPick = null
            result.error("unavailable", e.message, null)
        }
    }

    @Deprecated("FlutterActivity는 ComponentActivity가 아니라 Activity Result API 대신 사용")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST_PICK) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingPick ?: return
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        runIo(result) {
            val name = displayName(uri)
            if (!hasAllowedExtension(name)) {
                throw UnsupportedTypeException(name)
            }
            val persisted = try {
                contentResolver.takePersistableUriPermission(
                    uri, Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
                true
            } catch (_: SecurityException) {
                false
            }
            val bytes = readBytes(uri)
            if (persisted) uriDocument(uri, name, bytes) else copyDocument(uri, name, bytes)
        }
    }

    // ───────────────────────── 읽기 ─────────────────────────

    private fun readPersistedDocument(uri: Uri): Map<String, Any?> {
        val hasPermission = contentResolver.persistedUriPermissions.any {
            it.uri == uri && it.isReadPermission
        }
        if (!hasPermission) throw SecurityException("영구 권한이 없습니다")
        val bytes = readBytes(uri)
        return uriDocument(uri, displayName(uri), bytes)
    }

    /** 외부 앱에서 ACTION_VIEW로 연 파일. 영구 권한을 받을 수 없으면 앱 내부에 사본을 둔다. */
    private fun readExternalIntent(intent: Intent?): Map<String, Any?>? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        val uri = intent.data ?: return null

        if (uri.scheme == "file") {
            val path = uri.path ?: return null
            val file = File(path)
            return mapOf(
                "name" to file.name,
                "bytes" to file.readBytes(),
                "ref" to mapOf("kind" to "path", "value" to path),
                "location" to path,
            )
        }

        val name = displayName(uri)
        val canPersist = (intent.flags and Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION) != 0
        val persisted = canPersist && try {
            contentResolver.takePersistableUriPermission(
                uri, Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
            true
        } catch (_: SecurityException) {
            false
        }
        val bytes = readBytes(uri)
        return if (persisted) uriDocument(uri, name, bytes) else copyDocument(uri, name, bytes)
    }

    private fun readBytes(uri: Uri): ByteArray =
        contentResolver.openInputStream(uri)?.use { it.readBytes() }
            ?: throw FileNotFoundException(uri.toString())

    private fun uriDocument(uri: Uri, name: String, bytes: ByteArray) = mapOf(
        "name" to name,
        "bytes" to bytes,
        "ref" to mapOf("kind" to "uri", "value" to uri.toString()),
        "location" to friendlyLocation(uri, name),
    )

    /** 같은 URI는 같은 사본 파일을 덮어쓰므로 최근 목록에서 중복되지 않는다. */
    private fun copyDocument(uri: Uri, name: String, bytes: ByteArray): Map<String, Any?> {
        val dir = File(filesDir, "opened_copies").apply { mkdirs() }
        val safeName = name.replace(Regex("[\\\\/:*?\"<>|]"), "_")
        val file = File(dir, "${sha1(uri.toString()).take(12)}_$safeName")
        file.writeBytes(bytes)
        return mapOf(
            "name" to name,
            "bytes" to bytes,
            "ref" to mapOf("kind" to "copy", "value" to file.absolutePath),
            "location" to name,
        )
    }

    private fun releaseDocument(uri: Uri) {
        try {
            contentResolver.releasePersistableUriPermission(
                uri, Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        } catch (_: Exception) {
        }
    }

    // ───────────────────────── 도우미 ─────────────────────────

    /** 백그라운드에서 실행하고 결과/오류를 메인 스레드에서 Dart로 돌려준다. */
    private fun runIo(result: MethodChannel.Result, block: () -> Any?) {
        io.execute {
            try {
                val value = block()
                main.post { result.success(value) }
            } catch (e: Exception) {
                val code = when (e) {
                    is FileNotFoundException -> "not_found"
                    is IllegalArgumentException -> "not_found" // 일부 제공자는 사라진 문서에 이 예외를 던짐
                    is SecurityException -> "permission_denied"
                    is UnsupportedTypeException -> "unsupported_type"
                    else -> "io_error"
                }
                main.post { result.error(code, e.message, null) }
            }
        }
    }

    private fun displayName(uri: Uri): String {
        try {
            contentResolver.query(
                uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) cursor.getString(index)?.let { return it }
                }
            }
        } catch (_: Exception) {
        }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "document.md"
    }

    /** "primary:Download/notes.md" 같은 문서 ID에서 사람이 읽을 수 있는 경로를 뽑는다. */
    private fun friendlyLocation(uri: Uri, name: String): String {
        return try {
            if (!DocumentsContract.isDocumentUri(this, uri)) return name
            val id = DocumentsContract.getDocumentId(uri)
            when {
                id.startsWith("raw:") -> id.removePrefix("raw:")
                id.contains(':') && id.substringAfter(':').contains('/') -> id.substringAfter(':')
                else -> name
            }
        } catch (_: Exception) {
            name
        }
    }

    private fun hasAllowedExtension(name: String): Boolean {
        val ext = name.substringAfterLast('.', "").lowercase()
        return ext in ALLOWED_EXTENSIONS
    }

    private fun sha1(text: String): String =
        MessageDigest.getInstance("SHA-1").digest(text.toByteArray())
            .joinToString("") { "%02x".format(it) }

    private class UnsupportedTypeException(name: String) : Exception("지원하지 않는 파일: $name")

    companion object {
        private const val OPENED_FILE_CHANNEL = "md_viewer/opened_file"
        private const val DOCUMENTS_CHANNEL = "md_viewer/documents"
        private const val REQUEST_PICK = 4101
        private val ALLOWED_EXTENSIONS = setOf("md", "markdown", "txt")
    }
}
