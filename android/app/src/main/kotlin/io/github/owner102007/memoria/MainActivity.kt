package io.github.owner102007.memoria

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

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
    }
}
