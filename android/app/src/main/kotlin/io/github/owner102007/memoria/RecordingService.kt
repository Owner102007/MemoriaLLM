package io.github.owner102007.memoria

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

/**
 * Служба переднего плана на время записи сессии (SNO-F-REC-13).
 *
 * Свёрнутое приложение Android вправе выгрузить в любой миг, и запись
 * сессии оборвалась бы. Приложение со службой переднего плана система
 * ненужным не считает; разрешает она такую службу только с постоянным
 * уведомлением в шторке — участник его видит.
 *
 * Сама служба не делает ничего: запись ведёт Dart, а служба только
 * держит процесс. Заводит и снимает её `MainActivity` по слову Dart
 * (канал `memoria/guard`): заводит старт записи, снимает остановка.
 *
 * Заводится обычным `startService`, а не `startForegroundService`:
 * приложение в этот миг на экране, а второй вызов обязал бы стать
 * службой переднего плана за несколько секунд под страхом падения
 * приложения. Не вышло — служба тихо останавливается, и запись идёт,
 * как шла без неё.
 *
 * После гибели процесса служба не поднимается ([START_NOT_STICKY]):
 * запись, которую застал перезапуск, не продолжается, и держать
 * нечего. С задачей приложения она уходит тоже (`stopWithTask` в
 * манифесте): уведомление «Идёт запись» не должно пережить запись.
 *
 * Объявлена только в манифестах сборок ветвей СНО2026 вместе со своими
 * разрешениями; в основном приложении её нет, и завести её там нельзя.
 */
class RecordingService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: DEFAULT_TITLE
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: ""
        try {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification(title, text),
                foregroundType(),
            )
            foreground = true
        } catch (error: RuntimeException) {
            // Система не дала стать службой переднего плана (приложение
            // успело уйти в фон, производитель запретил): запись идёт
            // без неё.
            foreground = false
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        foreground = false
        super.onDestroy()
    }

    /**
     * Вид службы — тот, что назван в манифесте («особое назначение»):
     * с Android 14 без вида служба переднего плана не заводится.
     */
    private fun foregroundType(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MANIFEST
        } else {
            0
        }

    /**
     * Уведомление записи: заголовок и строка под ним приходят из Dart.
     *
     * Ни времени, ни кода участника в нём нет. Тихое: без звука и без
     * всплывающей плашки поверх страницы. Нажатие возвращает в
     * приложение.
     */
    private fun notification(title: String, text: String): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager =
                getSystemService(Context.NOTIFICATION_SERVICE)
                    as NotificationManager
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    title,
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        val builder =
            NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_recording)
                .setContentTitle(title)
                .setContentText(text)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setShowWhen(false)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setForegroundServiceBehavior(
                    NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE,
                )
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        if (launch != null) {
            builder.setContentIntent(
                PendingIntent.getActivity(
                    this,
                    0,
                    launch,
                    PendingIntent.FLAG_UPDATE_CURRENT or
                        PendingIntent.FLAG_IMMUTABLE,
                ),
            )
        }
        return builder.build()
    }

    companion object {
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"

        private const val DEFAULT_TITLE = "Идёт запись"
        private const val CHANNEL_ID = "recording"
        private const val NOTIFICATION_ID = 4301

        /**
         * Стала ли служба службой переднего плана. Процесс один, и
         * `MainActivity` читает ответ отсюда: своего канала у службы
         * нет.
         */
        @Volatile
        var foreground = false
            private set
    }
}
