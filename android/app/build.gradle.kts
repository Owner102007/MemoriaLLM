plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.github.owner102007.memoria"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.github.owner102007.memoria"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Три приложения из одного кода (SNO-F-CFG-01, SNO-ALG-CFG-01).
    //
    // `full` — основное приложение: идентификатор прежний, обновляется
    // поверх установленного. `sno2026core` и `sno2026test` — ветви I и II
    // для тестировщиков исследования СНО2026: свой идентификатор, своё
    // имя и своя иконка с плашкой, поэтому ставятся рядом с основным и
    // данных его не видят.
    //
    // Флейвор отвечает только за то, что знает сам Android: идентификатор,
    // имя, иконку и разрешения (см. `src/full/AndroidManifest.xml`). Всё
    // поведение приложения решает `--dart-define=SNO_BRANCH=I` или `II`
    // (`lib/sno/flags.dart`) — флейвор и это значение задаются сборке
    // вместе.
    //
    // Основной флейвор не назван `main`: это имя у Gradle занято общим
    // набором исходников.
    //
    // Подпись (SNO-F-REC-13, решение владельца Ч2 от 05.10.2026).
    // Сборки ветвей подписываются постоянным ключом: тогда новая сборка
    // встаёт поверх прежней и записи сессий, накопленные на телефоне,
    // остаются на месте. Отладочный ключ у каждого прогона CI свой, и
    // сборка, подписанная им, ставится только после удаления прежней —
    // вместе со всеми записями.
    //
    // Ключа в репозитории нет и быть не может: он лежит у владельца, а
    // сборке приходит переменными окружения — в CI из секретов
    // репозитория (`ci.yml`, шаг «Собрать APK»). Переменных нет —
    // сборка ветви подписывается отладочным ключом, как раньше: чужой
    // форк и локальная сборка от этого не ломаются.
    //
    // Основное приложение пока подписывается отладочным ключом: его
    // релизная подпись — отдельное решение (F-REL-08).
    //
    // Подпись названа у флейвора, а не у вида сборки `release`: у вида
    // сборки она одна на все три приложения и сильнее названной у
    // флейвора.
    val branchKeystore: String? = System.getenv("SNO_KEYSTORE_FILE")
    signingConfigs {
        if (!branchKeystore.isNullOrEmpty()) {
            create("sno") {
                storeFile = file(branchKeystore)
                storePassword = System.getenv("SNO_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("SNO_KEY_ALIAS")
                keyPassword = System.getenv("SNO_KEY_PASSWORD")
            }
        }
    }
    val debugSigning = signingConfigs.getByName("debug")
    val branchSigning = signingConfigs.findByName("sno") ?: debugSigning

    flavorDimensions += "app"
    productFlavors {
        create("full") {
            dimension = "app"
            manifestPlaceholders["appLabel"] = "Memoria LLM HB"
            signingConfig = debugSigning
        }
        create("sno2026core") {
            dimension = "app"
            applicationIdSuffix = ".sno2026.core"
            manifestPlaceholders["appLabel"] = "Memoria · СНО2026 · I"
            signingConfig = branchSigning
        }
        create("sno2026test") {
            dimension = "app"
            applicationIdSuffix = ".sno2026.test"
            manifestPlaceholders["appLabel"] = "Memoria · СНО2026 · II"
            signingConfig = branchSigning
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Поставщик файлов для архивов записей (SNO-F-REC-06,
    // `RecordsFileProvider`). Библиотека и так приходит с движком
    // Flutter; здесь она названа, потому что ею пользуется наш код.
    implementation("androidx.core:core:1.13.1")
}
