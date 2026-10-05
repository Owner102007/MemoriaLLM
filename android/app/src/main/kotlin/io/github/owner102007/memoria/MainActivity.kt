package io.github.owner102007.memoria

import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ComponentName
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.StatFs
import android.provider.MediaStore
import android.provider.Settings
import android.view.KeyEvent
import android.view.WindowManager
import android.view.accessibility.AccessibilityManager
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.core.content.IntentCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.security.MessageDigest

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
 * телефона (SNO-F-REC-06): системное окно «Поделиться». И то, чем
 * запись защищена от потери (SNO-F-REC-13): служба переднего плана на
 * время записи, вторая копия архива в общих «Загрузках», паспорт
 * устройства.
 */
class MainActivity : FlutterActivity() {
    /** Канал кнопок громкости; `null`, пока движок не поднят. */
    private var volumeChannel: MethodChannel? = null

    /**
     * Перехватывать ли кнопки громкости. Решает Dart: он знает, открыта
     * ли книга и не лежит ли поверх неё шторка или диалог.
     */
    private var volumeKeysActive = false

    private val handler = Handler(Looper.getMainLooper())

    /** На экране ли приложение прямо сейчас. */
    private var resumed = false

    /**
     * Ответ, которого ждёт Dart от окна «Поделиться» (SNO-F-REC-14);
     * `null` — окно не открыто.
     */
    private var pendingShare: MethodChannel.Result? = null

    /** Приёмник выбора в окне «Поделиться»; живёт, пока окно открыто. */
    private var shareReceiver: BroadcastReceiver? = null

    /** Номер открытого окна: ответ прежнему окну не принимается. */
    private var shareToken = 0

    /** Уходило ли приложение с экрана с тех пор, как окно открыли. */
    private var shareLeft = false

    /**
     * Скрывалось ли приложение целиком, пока окно было открыто: само
     * окно выбора его только заслоняет, а целиком его скрывает
     * приложение, в которое ушли.
     */
    private var shareHidden = false

    /** Ответ, которого ждёт Dart от вопроса об уведомлениях. */
    private var pendingNotifications: MethodChannel.Result? = null

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
                // SNO-F-REC-13: на чём записана сессия.
                "passport" -> result.success(passport())
                else -> result.notImplemented()
            }
        }

        // SNO-F-REC-13: пока идёт запись сессии, приложение держит
        // службу переднего плана — свёрнутое, оно не выгружается.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            GUARD_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "notifications" -> result.success(notificationsAllowed())
                "askNotifications" -> askNotifications(result)
                "hold" ->
                    holdRecording(
                        call.argument<String>("title"),
                        call.argument<String>("text"),
                        result,
                    )
                "release" -> {
                    releaseRecording()
                    result.success(null)
                }
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
                    shareRecords(
                        call.argument<List<String>>("paths") ?: emptyList(),
                        result,
                    )
                // SNO-F-REC-13: вторая копия архива — в общих
                // «Загрузках», которые переживают удаление приложения.
                "canBackup" ->
                    result.success(
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q,
                    )
                "backup" ->
                    backupRecord(
                        call.argument<String>("path"),
                        call.argument<String>("sha256"),
                        call.argument<String>("folder"),
                        result,
                    )
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        resumed = true
        // SNO-F-REC-14: вернулись из окна «Поделиться», а о выборе
        // система не сообщила. Ответ даётся не сразу: сообщение о
        // выборе может прийти чуть позже возвращения.
        if (pendingShare != null && shareLeft) {
            val token = shareToken
            handler.postDelayed(
                {
                    if (resumed) {
                        answerShare(
                            token,
                            if (shareHidden) SHARE_UNTOLD else SHARE_DISMISSED,
                        )
                    }
                },
                SHARE_SETTLE_MS,
            )
        }
    }

    override fun onPause() {
        resumed = false
        if (pendingShare != null) {
            shareLeft = true
        }
        super.onPause()
    }

    override fun onStop() {
        if (pendingShare != null) {
            shareHidden = true
        }
        super.onStop()
    }

    override fun onDestroy() {
        dropShareReceiver()
        handler.removeCallbacksAndMessages(null)
        // SNO-F-REC-13: движок Flutter уходит вместе с экраном, и
        // запись вместе с ним — уведомление «Идёт запись» пережить её
        // не должно.
        releaseRecording()
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != NOTIFY_REQUEST) {
            return
        }
        val pending = pendingNotifications ?: return
        pendingNotifications = null
        answer(
            pending,
            grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED,
        )
    }

    /**
     * Отвечает Dart; ответ, который уже некому принять (движок
     * остановлен), не роняет приложение.
     */
    private fun answer(result: MethodChannel.Result, value: Any?) {
        try {
            result.success(value)
        } catch (error: RuntimeException) {
            // Движка уже нет.
        }
    }

    /** Разрешены ли приложению уведомления (SNO-F-REC-13). */
    private fun notificationsAllowed(): Boolean =
        NotificationManagerCompat.from(this).areNotificationsEnabled()

    /**
     * Просит разрешение на уведомления системным окном (Android 13 и
     * новее; раньше оно не спрашивалось). Отвечает, когда окно
     * закрыто.
     */
    private fun askNotifications(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(notificationsAllowed())
            return
        }
        if (checkSelfPermission(POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (pendingNotifications != null) {
            result.success(null)
            return
        }
        pendingNotifications = result
        try {
            requestPermissions(arrayOf(POST_NOTIFICATIONS), NOTIFY_REQUEST)
        } catch (error: RuntimeException) {
            pendingNotifications = null
            result.success(null)
        }
    }

    /**
     * Заводит службу переднего плана записи (SNO-F-REC-13).
     *
     * Службой переднего плана она становится в своём `onStartCommand`,
     * чуть позже этого вызова, поэтому ответ даётся с задержкой — по
     * тому, что вышло на самом деле. В основном приложении службы в
     * манифесте нет: `startService` вернёт `null`, ответ — «нет».
     */
    private fun holdRecording(
        title: String?,
        text: String?,
        result: MethodChannel.Result,
    ) {
        val started =
            try {
                startService(
                    Intent(this, RecordingService::class.java)
                        .putExtra(RecordingService.EXTRA_TITLE, title)
                        .putExtra(RecordingService.EXTRA_TEXT, text),
                ) != null
            } catch (error: RuntimeException) {
                // Приложение уже не на экране, или система запретила.
                false
            }
        if (!started) {
            result.success(false)
            return
        }
        handler.postDelayed(
            { answer(result, RecordingService.foreground) },
            GUARD_SETTLE_MS,
        )
    }

    /** Снимает службу переднего плана записи и её уведомление. */
    private fun releaseRecording() {
        try {
            stopService(Intent(this, RecordingService::class.java))
        } catch (error: RuntimeException) {
            // Службы нет или система не дала её остановить.
        }
    }

    /**
     * Паспорт устройства для сведений о записи (SNO-F-REC-13):
     * производитель, модель, версия системы. Серийных номеров и
     * идентификаторов здесь нет.
     */
    private fun passport(): Map<String, Any> {
        val told = HashMap<String, Any>()
        told["os"] = "Android"
        told["os_version"] = Build.VERSION.RELEASE ?: ""
        told["sdk"] = Build.VERSION.SDK_INT
        told["manufacturer"] = Build.MANUFACTURER ?: ""
        told["brand"] = Build.BRAND ?: ""
        told["model"] = Build.MODEL ?: ""
        return told
    }

    /**
     * Отдаёт архивы записей системному окну «Поделиться» и отвечает,
     * чем оно кончилось (SNO-ALG-REC-04, SNO-F-REC-14).
     *
     * Чужое приложение получает не путь, а ссылку `content://` от
     * поставщика файлов сборки ветви ([RecordsFileProvider]) и право
     * прочитать только эти файлы.
     *
     * Ответ — одно из четырёх слов: `chosen` — в окне выбрано
     * приложение (система сообщает об этом приёмнику выбора);
     * `dismissed` — окно закрыто без выбора; `untold` — система о
     * выборе не сообщила (пункт окна без приложения, окно
     * производителя, старый Android); `failed` — окно не открылось.
     * Дошёл ли архив до адресата, Android не сообщает никогда.
     *
     * В основном приложении поставщика нет — ссылки не получится, и
     * ответ `failed`: записей там не бывает.
     */
    private fun shareRecords(
        paths: List<String>,
        result: MethodChannel.Result,
    ) {
        if (paths.isEmpty() || pendingShare != null) {
            result.success(SHARE_FAILED)
            return
        }
        try {
            val authority = "$packageName$RECORDS_AUTHORITY"
            val uris = ArrayList<Uri>()
            for (path in paths) {
                val file = File(path)
                if (!file.isFile || !file.name.endsWith(".zip")) {
                    result.success(SHARE_FAILED)
                    return
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
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP_MR1) {
                // О выборе в окне система здесь не сообщает вовсе.
                startActivity(Intent.createChooser(send, null))
                result.success(SHARE_UNTOLD)
                return
            }
            val token = ++shareToken
            val action = "$packageName$SHARE_ACTION"
            val receiver =
                object : BroadcastReceiver() {
                    override fun onReceive(context: Context, intent: Intent) {
                        val chosen =
                            IntentCompat.getParcelableExtra(
                                intent,
                                Intent.EXTRA_CHOSEN_COMPONENT,
                                ComponentName::class.java,
                            )
                        answerShare(
                            token,
                            if (chosen != null) SHARE_CHOSEN else SHARE_UNTOLD,
                        )
                    }
                }
            // Приёмник не выставлен наружу: сообщение о выборе система
            // шлёт от имени самого приложения.
            ContextCompat.registerReceiver(
                this,
                receiver,
                IntentFilter(action),
                ContextCompat.RECEIVER_NOT_EXPORTED,
            )
            shareReceiver = receiver
            // Сообщение изменяемое: система вписывает в него выбранное
            // приложение. Адресовано оно своему же пакету.
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                flags = flags or PendingIntent.FLAG_MUTABLE
            }
            val callback =
                PendingIntent.getBroadcast(
                    this,
                    token,
                    Intent(action).setPackage(packageName),
                    flags,
                )
            pendingShare = result
            shareLeft = false
            shareHidden = false
            startActivity(
                Intent.createChooser(send, null, callback.intentSender),
            )
        } catch (error: IllegalArgumentException) {
            // Файл лежит не в папке записей, или поставщика в этой
            // сборке нет.
            failShare(result)
        } catch (error: ActivityNotFoundException) {
            failShare(result)
        } catch (error: SecurityException) {
            failShare(result)
        }
    }

    /** Окно «Поделиться» не открылось. */
    private fun failShare(result: MethodChannel.Result) {
        pendingShare = null
        dropShareReceiver()
        answer(result, SHARE_FAILED)
    }

    /**
     * Отвечает Dart, чем кончилось окно «Поделиться» номер [token].
     * Отвечает один раз: первое слово — сообщение о выборе или
     * возвращение без него — последнее.
     */
    private fun answerShare(token: Int, outcome: String) {
        if (token != shareToken) {
            return
        }
        val pending = pendingShare ?: return
        pendingShare = null
        dropShareReceiver()
        answer(pending, outcome)
    }

    private fun dropShareReceiver() {
        val receiver = shareReceiver ?: return
        shareReceiver = null
        try {
            unregisterReceiver(receiver)
        } catch (error: IllegalArgumentException) {
            // Приёмник уже снят.
        }
    }

    /**
     * Кладёт вторую копию архива записи в общие «Загрузки»
     * (SNO-F-REC-13) и отвечает, лежит ли там теперь сверенная копия.
     *
     * Копирование идёт не в главном потоке: архив с потоком взгляда
     * будет большим, а экран в это время стоять не должен.
     */
    private fun backupRecord(
        path: String?,
        expected: String?,
        folder: String?,
        result: MethodChannel.Result,
    ) {
        if (path == null || expected == null || folder.isNullOrEmpty() ||
            Build.VERSION.SDK_INT < Build.VERSION_CODES.Q
        ) {
            result.success(false)
            return
        }
        Thread {
            val there =
                try {
                    copyToDownloads(File(path), expected, folder)
                } catch (error: Exception) {
                    false
                }
            handler.post { answer(result, there) }
        }.start()
    }

    /**
     * Копия файла [file] в папке [folder] общих «Загрузок», сверенная
     * с суммой [expected].
     *
     * Пишется через системное хранилище загрузок: разрешений для
     * этого не нужно, а файл остаётся на телефоне и после удаления
     * приложения. Копия, уже лежащая там с той же суммой, второй раз
     * не кладётся; копия, не сошедшаяся с суммой, убирается.
     */
    @RequiresApi(Build.VERSION_CODES.Q)
    private fun copyToDownloads(
        file: File,
        expected: String,
        folder: String,
    ): Boolean {
        if (!file.isFile) {
            return false
        }
        val resolver = contentResolver
        val collection =
            MediaStore.Downloads.getContentUri(
                MediaStore.VOLUME_EXTERNAL_PRIMARY,
            )
        val relative = Environment.DIRECTORY_DOWNLOADS + "/" + folder + "/"
        resolver.query(
            collection,
            arrayOf(MediaStore.MediaColumns._ID),
            MediaStore.MediaColumns.DISPLAY_NAME + " = ? AND " +
                MediaStore.MediaColumns.RELATIVE_PATH + " = ?",
            arrayOf(file.name, relative),
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val known =
                    ContentUris.withAppendedId(collection, cursor.getLong(0))
                if (sha256Of(known) == expected) {
                    return true
                }
            }
        }
        val values = ContentValues()
        values.put(MediaStore.MediaColumns.DISPLAY_NAME, file.name)
        values.put(MediaStore.MediaColumns.MIME_TYPE, "application/zip")
        values.put(MediaStore.MediaColumns.RELATIVE_PATH, relative)
        values.put(MediaStore.MediaColumns.IS_PENDING, 1)
        val uri = resolver.insert(collection, values) ?: return false
        try {
            val out =
                resolver.openOutputStream(uri)
                    ?: throw IOException("общая папка не дала потока")
            out.use { target ->
                file.inputStream().use { source -> source.copyTo(target) }
            }
            val done = ContentValues()
            done.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, done, null, null)
            if (sha256Of(uri) == expected) {
                return true
            }
        } catch (error: IOException) {
            // Места нет или том отключили: обрывок убирается ниже.
        } catch (error: RuntimeException) {
            // Хранилище отказало: обрывок убирается ниже.
        }
        try {
            resolver.delete(uri, null, null)
        } catch (error: RuntimeException) {
            // Обрывок остался в «Загрузках»: убрать его нечем.
        }
        return false
    }

    /** SHA-256 содержимого [uri] строчными шестнадцатеричными знаками. */
    private fun sha256Of(uri: Uri): String? =
        try {
            val digest = MessageDigest.getInstance("SHA-256")
            val input = contentResolver.openInputStream(uri)
            if (input == null) {
                null
            } else {
                input.use { stream ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val read = stream.read(buffer)
                        if (read < 0) {
                            break
                        }
                        digest.update(buffer, 0, read)
                    }
                }
                digest.digest().joinToString("") { byte ->
                    "%02x".format(byte)
                }
            }
        } catch (error: IOException) {
            null
        } catch (error: RuntimeException) {
            null
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
        const val GUARD_CHANNEL = "memoria/guard"

        /** Слова ответа окна «Поделиться» (SNO-F-REC-14). */
        const val SHARE_CHOSEN = "chosen"
        const val SHARE_DISMISSED = "dismissed"
        const val SHARE_UNTOLD = "untold"
        const val SHARE_FAILED = "failed"

        /** Хвост имени сообщения о выборе: за идентификатором сборки. */
        const val SHARE_ACTION = ".SHARE_CHOSEN"

        /**
         * Сколько ждать сообщения о выборе после возвращения из окна
         * «Поделиться», прежде чем считать окно закрытым без выбора.
         */
        const val SHARE_SETTLE_MS = 1000L

        /** Через сколько служба записи успевает стать службой. */
        const val GUARD_SETTLE_MS = 800L

        const val POST_NOTIFICATIONS =
            "android.permission.POST_NOTIFICATIONS"
        const val NOTIFY_REQUEST = 4202

        /** Хвост имени поставщика файлов: за идентификатором сборки. */
        const val RECORDS_AUTHORITY = ".records"
        const val READ_STORAGE = android.Manifest.permission.READ_EXTERNAL_STORAGE
        const val STORAGE_REQUEST = 4201
    }
}
