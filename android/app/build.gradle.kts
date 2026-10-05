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
    flavorDimensions += "app"
    productFlavors {
        create("full") {
            dimension = "app"
            manifestPlaceholders["appLabel"] = "Memoria LLM HB"
        }
        create("sno2026core") {
            dimension = "app"
            applicationIdSuffix = ".sno2026.core"
            manifestPlaceholders["appLabel"] = "Memoria · СНО2026 · I"
        }
        create("sno2026test") {
            dimension = "app"
            applicationIdSuffix = ".sno2026.test"
            manifestPlaceholders["appLabel"] = "Memoria · СНО2026 · II"
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
