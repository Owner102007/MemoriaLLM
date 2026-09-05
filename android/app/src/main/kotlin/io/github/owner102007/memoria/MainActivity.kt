package io.github.owner102007.memoria

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Закрепление разрешения на выбранный документ.
 *
 * Всё остальное для работы с документами Android умеют готовые пакеты
 * (`fast_file_picker` выбирает файл не читая, `saf_util` отдаёт файловый
 * дескриптор и сведения о документе). Не умеют они ровно одного —
 * `takePersistableUriPermission`, а без него ссылка живёт до конца
 * процесса: закрыл приложение — и книга «пропала».
 *
 * Поэтому здесь ровно один канал и ровно два действия. Своего плагина
 * ради этого не заводится: плагин — это отдельный пакет, свой pubspec,
 * своя сборка и своя жизнь, а работы тут на два вызова системного API.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            val uri = call.argument<String>("uri")
            if (uri == null) {
                result.error("NO_URI", "нужна ссылка на документ", null)
                return@setMethodCallHandler
            }
            when (call.method) {
                "persist" -> result.success(persist(uri))
                "release" -> result.success(release(uri))
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            STORAGE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "granted" -> result.success(hasAllFilesAccess())
                "request" -> result.success(requestAllFilesAccess())
                "roots" -> result.success(storageRoots())
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Выдан ли доступ ко всем файлам.
     *
     * На Android 11 и выше это отдельное состояние приложения, а не
     * обычное разрешение: система отвечает `isExternalStorageManager`.
     * Ниже одиннадцатого доступ даёт обычное `READ_EXTERNAL_STORAGE`,
     * которое запрашивается обычным путём, а здесь остаётся проверить,
     * читается ли внешняя память вообще.
     */
    private fun hasAllFilesAccess(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            checkSelfPermission(READ_STORAGE) == PackageManager.PERMISSION_GRANTED &&
                Environment.getExternalStorageState() == Environment.MEDIA_MOUNTED
        }

    /**
     * Открывает системный экран выдачи доступа ко всем файлам.
     *
     * Сначала пробуется экран **этого** приложения: читателю не придётся
     * искать нас в общем списке из сотни строк. Если производитель такого
     * экрана не сделал — открывается общий список; если и его нет, ответ
     * `false`, и приложение честно скажет, что перейти не удалось.
     */
    private fun requestAllFilesAccess(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            // До Android 11 доступ ко всей памяти даёт обычное разрешение
            // на чтение — вместе с `requestLegacyExternalStorage` в
            // манифесте. Спрашивается оно обычным системным диалогом, и
            // ответ приходит не сюда: состояние перепроверяется, когда
            // приложение снова окажется на переднем плане.
            requestPermissions(arrayOf(READ_STORAGE), STORAGE_REQUEST)
            return true
        }
        val direct = Intent(
            Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
            Uri.parse("package:$packageName"),
        )
        if (startSafely(direct)) {
            return true
        }
        return startSafely(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
    }

    private fun startSafely(intent: Intent): Boolean =
        try {
            startActivity(intent)
            true
        } catch (error: android.content.ActivityNotFoundException) {
            false
        } catch (error: SecurityException) {
            false
        }

    /**
     * Откуда начинать обход: встроенная память и карта, если она есть.
     *
     * Карта памяти узнаётся через `getExternalFilesDirs`: система отдаёт
     * пути к нашим папкам на каждом томе, а корень тома — это путь до
     * `/Android/data`. Способ окольный, зато не требует ни скрытых API,
     * ни разбора `/storage` руками.
     */
    private fun storageRoots(): List<String> {
        val roots = LinkedHashSet<String>()
        Environment.getExternalStorageDirectory()?.absolutePath?.let(roots::add)
        for (dir in getExternalFilesDirs(null)) {
            val path = dir?.absolutePath ?: continue
            val cut = path.indexOf("/Android/data")
            if (cut > 0) {
                val root = path.substring(0, cut)
                if (File(root).canRead()) {
                    roots.add(root)
                }
            }
        }
        return roots.toList()
    }

    /**
     * Закрепляет разрешение на чтение документа.
     *
     * Возвращает `false`, если провайдер закрепить не дал: такое бывает у
     * тех, кто отдаёт документ разово. Книга при этом откроется сейчас и
     * не откроется после перезапуска — это состояние, а не падение, и
     * решать, что с ним делать, будет вызывающая сторона.
     */
    private fun persist(uri: String): Boolean =
        try {
            contentResolver.takePersistableUriPermission(
                Uri.parse(uri),
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
            true
        } catch (error: SecurityException) {
            false
        }

    /**
     * Отпускает закреплённое разрешение: книгу сняли с полки.
     *
     * Android держит закреплённых ссылок ограниченное число на
     * приложение, поэтому отпускать ненужные — не уборка ради порядка,
     * а работа с исчерпаемым ресурсом.
     */
    private fun release(uri: String): Boolean =
        try {
            contentResolver.releasePersistableUriPermission(
                Uri.parse(uri),
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
            true
        } catch (error: SecurityException) {
            false
        }

    private companion object {
        const val CHANNEL = "memoria/uri_permissions"
        const val STORAGE_CHANNEL = "memoria/storage_access"
        const val READ_STORAGE = android.Manifest.permission.READ_EXTERNAL_STORAGE
        const val STORAGE_REQUEST = 4201
    }
}
