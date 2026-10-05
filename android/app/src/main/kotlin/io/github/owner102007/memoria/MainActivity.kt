package io.github.owner102007.memoria

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.os.StatFs
import android.provider.Settings
import android.view.KeyEvent
import android.view.WindowManager
import android.view.accessibility.AccessibilityManager
import androidx.core.content.FileProvider
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
 *
 * По той же причине здесь живут доступ ко всем файлам (S5.4) и перехват
 * кнопок громкости (F-READ-26): Flutter этих кнопок не видит вовсе.
 * И три вопроса записи сессии к устройству (SNO-F-REC-01): заряд,
 * свободное место и «экран не гаснет». И выход архива записи с
 * телефона (SNO-F-REC-06): системное окно «Поделиться».
 */
class MainActivity : FlutterActivity() {
    /** Канал кнопок громкости; `null`, пока движок не поднят. */
    private var volumeChannel: MethodChannel? = null

    /**
     * Перехватывать ли кнопки громкости. Решает Dart: он знает, открыта
     * ли книга и не лежит ли поверх неё шторка или диалог.
     */
    private var volumeKeysActive = false

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

        val volume = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            VOLUME_CHANNEL,
        )
        volume.setMethodCallHandler { call, result ->
            when (call.method) {
                "active" -> {
                    volumeKeysActive =
                        call.argument<Boolean>("active") ?: false
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        volumeChannel = volume

        // SNO-F-REC-01: запись сессии в сборках ветвей СНО2026
        // спрашивает заряд и свободное место перед стартом и держит
        // экран включённым, пока идёт.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEVICE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "battery" -> result.success(batteryPercent())
                "freeBytes" ->
                    result.success(freeBytes(call.arguments as? String))
                "keepScreenOn" -> {
                    keepScreenOn(call.arguments as? Boolean ?: false)
                    result.success(null)
                }
                // SNO-F-REC-10: погашенный кнопкой экран запись отличает
                // от свёрнутого приложения этим ответом.
                "screenOn" -> result.success(screenOn())
                else -> result.notImplemented()
            }
        }

        // SNO-F-REC-06: архив записи сессии уходит с телефона системным
        // окном «Поделиться» — в мессенджер, почту или на диск.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            RECORDS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "share" ->
                    result.success(
                        shareRecords(
                            call.argument<List<String>>("paths")
                                ?: emptyList(),
                        ),
                    )
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Отдаёт архивы записей системному окну «Поделиться»
     * (SNO-ALG-REC-04).
     *
     * Чужое приложение получает не путь, а ссылку `content://` от
     * поставщика файлов сборки ветви ([RecordsFileProvider]) и право
     * прочитать только эти файлы. Отвечает, открылось ли окно: дошёл
     * ли архив до адресата, Android не сообщает.
     *
     * В основном приложении поставщика нет — ссылки не получится, и
     * ответ «нет»: записей там не бывает.
     */
    private fun shareRecords(paths: List<String>): Boolean {
        if (paths.isEmpty()) {
            return false
        }
        return try {
            val authority = "$packageName$RECORDS_AUTHORITY"
            val uris = ArrayList<Uri>()
            for (path in paths) {
                val file = File(path)
                if (!file.isFile || !file.name.endsWith(".zip")) {
                    return false
                }
                uris.add(FileProvider.getUriForFile(this, authority, file))
            }
            val send =
                if (uris.size == 1) {
                    Intent(Intent.ACTION_SEND)
                        .putExtra(Intent.EXTRA_STREAM, uris[0])
                } else {
                    Intent(Intent.ACTION_SEND_MULTIPLE)
                        .putParcelableArrayListExtra(
                            Intent.EXTRA_STREAM,
                            uris,
                        )
                }
            send.type = "application/zip"
            send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            // Право на чтение выдаётся по ссылкам из ClipData: без него
            // окно выбора показало бы приложения, а файл они прочитать
            // не смогли бы.
            val clip = ClipData.newRawUri("", uris[0])
            for (index in 1 until uris.size) {
                clip.addItem(ClipData.Item(uris[index]))
            }
            send.clipData = clip
            startActivity(Intent.createChooser(send, null))
            true
        } catch (error: IllegalArgumentException) {
            // Файл лежит не в папке записей, или поставщика в этой
            // сборке нет.
            false
        } catch (error: ActivityNotFoundException) {
            false
        } catch (error: SecurityException) {
            false
        }
    }

    /** Горит ли экран; `null` — система не ответила. */
    private fun screenOn(): Boolean? {
        val manager =
            getSystemService(Context.POWER_SERVICE) as? PowerManager
                ?: return null
        return manager.isInteractive
    }

    /** Заряд батареи в процентах; `null` — система не ответила. */
    private fun batteryPercent(): Int? {
        val manager =
            getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
                ?: return null
        val percent =
            manager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        return if (percent in 0..100) percent else null
    }

    /** Свободное место на томе, где лежит [path]; `null` — не узнать. */
    private fun freeBytes(path: String?): Long? {
        if (path == null) {
            return null
        }
        return try {
            StatFs(path).availableBytes
        } catch (error: IllegalArgumentException) {
            null
        }
    }

    /**
     * Держит экран включённым, пока идёт запись сессии.
     *
     * Признак окна, а не блокировка пробуждения: разрешения он не
     * требует и снимается сам, когда приложение ушло с экрана.
     */
    private fun keepScreenOn(on: Boolean) {
        if (on) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    /**
     * Перехват кнопок громкости (F-READ-26, ALG-READ-06).
     *
     * Здесь нет ни одного решения, кроме «перехватывать ли»: событие
     * целиком пересылается в Dart, и что с ним делать — листать или
     * менять громкость — отвечает он. Правило написано там, потому что
     * там оно под тестами, а тестов Android в проекте нет.
     *
     * Перехваченное событие система уже не обработает, поэтому громкость
     * по слову Dart меняем сами. Если Dart не ответил вовсе, кнопка
     * ведёт себя как обычная кнопка громкости: молчать она не должна
     * ни при каком сбое.
     *
     * При включённом экранном дикторе перехвата нет: кнопками громкости
     * управляют им самим.
     */
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val channel = volumeChannel
        val code = event.keyCode
        val lower = code == KeyEvent.KEYCODE_VOLUME_DOWN
        val raise = code == KeyEvent.KEYCODE_VOLUME_UP
        val pressed = event.action == KeyEvent.ACTION_DOWN
        val released = event.action == KeyEvent.ACTION_UP
        if (!volumeKeysActive || channel == null || !(lower || raise) ||
            !(pressed || released) || screenReaderOn()
        ) {
            return super.dispatchKeyEvent(event)
        }
        val fallback =
            if (lower) AudioManager.ADJUST_LOWER else AudioManager.ADJUST_RAISE
        val arguments = HashMap<String, Any>()
        arguments["key"] = if (lower) "down" else "up"
        arguments["pressed"] = pressed
        arguments["repeat"] = event.repeatCount
        arguments["canceled"] = event.isCanceled
        channel.invokeMethod(
            "key",
            arguments,
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (result == "raise") {
                        adjustVolume(AudioManager.ADJUST_RAISE)
                    } else if (result == "lower") {
                        adjustVolume(AudioManager.ADJUST_LOWER)
                    }
                }

                override fun error(
                    errorCode: String,
                    errorMessage: String?,
                    errorDetails: Any?,
                ) {
                    if (pressed) {
                        adjustVolume(fallback)
                    }
                }

                override fun notImplemented() {
                    if (pressed) {
                        adjustVolume(fallback)
                    }
                }
            },
        )
        return true
    }

    /** Меняет громкость так, как это сделала бы кнопка: со шкалой. */
    private fun adjustVolume(direction: Int) {
        val audio =
            getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        try {
            audio.adjustSuggestedStreamVolume(
                direction,
                AudioManager.USE_DEFAULT_STREAM_TYPE,
                AudioManager.FLAG_SHOW_UI,
            )
        } catch (error: SecurityException) {
            // Система не дала увести звонок в беззвучный режим: на этой
            // границе кнопка ничего не делает, а падать из-за неё нельзя.
        }
    }

    /** Включён ли экранный диктор (TalkBack). */
    private fun screenReaderOn(): Boolean {
        val service = getSystemService(Context.ACCESSIBILITY_SERVICE)
        val manager = service as? AccessibilityManager
        return manager?.isTouchExplorationEnabled == true
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
        const val VOLUME_CHANNEL = "memoria/volume_keys"
        const val DEVICE_CHANNEL = "memoria/device"
        const val RECORDS_CHANNEL = "memoria/records"

        /** Хвост имени поставщика файлов: за идентификатором сборки. */
        const val RECORDS_AUTHORITY = ".records"
        const val READ_STORAGE = android.Manifest.permission.READ_EXTERNAL_STORAGE
        const val STORAGE_REQUEST = 4201
    }
}
