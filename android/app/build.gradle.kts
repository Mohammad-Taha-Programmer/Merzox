import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android Gradle plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")

if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use {
        keystoreProperties.load(it)
    }
}

val releaseTaskRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

val requiredReleaseSigningProperties = listOf(
    "storeFile",
    "storePassword",
    "keyAlias",
    "keyPassword",
)

if (releaseTaskRequested) {
    require(keystorePropertiesFile.isFile) {
        "Merzox release signing requires android/key.properties."
    }

    val missingReleaseSigningProperties =
        requiredReleaseSigningProperties.filter {
            keystoreProperties.getProperty(it).isNullOrBlank()
        }

    require(missingReleaseSigningProperties.isEmpty()) {
        "Merzox release signing is missing required properties: " +
            missingReleaseSigningProperties.joinToString(",")
    }

    val configuredReleaseStoreFile =
        rootProject.file(keystoreProperties.getProperty("storeFile"))

    require(configuredReleaseStoreFile.isFile) {
        "Merzox release signing keystore file does not exist."
    }
}

android {
    namespace = "com.example.merzox"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.merzox"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.isFile) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file(
                    keystoreProperties.getProperty("storeFile")
                )
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}
