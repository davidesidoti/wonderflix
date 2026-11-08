import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firma di rilascio: key.properties (gitignored, lo crea create_release_key.sh o la CI dai
// Secrets). Senza, la release si firma con la chiave di debug (solo sviluppo): un APK firmato
// con una chiave diversa non può aggiornare quello installato.
val keyProperties = rootProject.file("key.properties").takeIf { it.exists() }?.let { file ->
    Properties().apply { file.inputStream().use { load(it) } }
}

// versionCode = major * 1_000_000 + minor * 1_000 + patch (0.33.0 -> 33000), così ogni
// release supera la precedente e l'installer di Android accetta l'aggiornamento.
fun versionCodeOf(versionName: String): Int {
    val match = Regex("""^(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$""").matchEntire(versionName)
        ?: throw GradleException("versionName '$versionName' non è X.Y.Z: impossibile calcolare il versionCode")
    val (major, minor, patch) = match.destructured
    return major.toInt() * 1_000_000 + minor.toInt() * 1_000 + patch.toInt()
}

android {
    namespace = "it.wonderflix.tv"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "it.wonderflix.tv"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = versionCodeOf(flutter.versionName)
        versionName = flutter.versionName
        // Solo ARM (Fire TV). Con --split-per-abi Gradle rifiuta abiFilters (le ABI le sceglie lo split).
        if (!project.hasProperty("split-per-abi")) {
            ndk { abiFilters += listOf("armeabi-v7a", "arm64-v8a") }
        }
    }

    signingConfigs {
        if (keyProperties != null) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (keyProperties != null) "release" else "debug")
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
    implementation("androidx.media3:media3-exoplayer:1.11.1")
    implementation("androidx.media3:media3-exoplayer-hls:1.11.1")
    implementation("androidx.media3:media3-ui:1.11.1")
    implementation("io.github.peerless2012:ass-media:0.5.1")
    // AssRender (scala dei caratteri ASS): ass-media lo dichiara solo a runtime.
    implementation("io.github.peerless2012:ass-kt:0.5.1")
}
