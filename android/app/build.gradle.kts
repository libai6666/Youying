import java.io.File
import java.security.KeyStore
import java.security.cert.X509Certificate

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingNames = listOf("YOUYING_KEYSTORE", "YOUYING_KEY_ALIAS", "YOUYING_STORE_PASSWORD", "YOUYING_KEY_PASSWORD")
val releaseSigning = signingNames.associateWith { System.getenv(it).orEmpty() }
val signingReady = releaseSigning.values.all { it.isNotBlank() }
val releaseRequested = gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
if (releaseRequested) {
    require(signingReady) { "Release signing missing: " + signingNames.filter { releaseSigning.getValue(it).isBlank() }.joinToString() }
    val store = File(releaseSigning.getValue("YOUYING_KEYSTORE"))
    require(store.isAbsolute && store.isFile) { "YOUYING_KEYSTORE must be an existing absolute path" }
    val alias = releaseSigning.getValue("YOUYING_KEY_ALIAS")
    val keyStore = KeyStore.getInstance(store, releaseSigning.getValue("YOUYING_STORE_PASSWORD").toCharArray())
    require(keyStore.isKeyEntry(alias)) { "Release alias is not a private key" }
    val certificate = keyStore.getCertificate(alias) as X509Certificate
    certificate.checkValidity()
    val isDebugCertificate = javax.naming.ldap.LdapName(certificate.subjectX500Principal.name).rdns.any {
        it.type.equals("CN", ignoreCase = true) && it.value.toString().equals("Android Debug", ignoreCase = true)
    }
    require(!isDebugCertificate) {
        "Android debug certificate is not allowed for a release build"
    }
}

android {
    namespace = "dev.youying.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.youying.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = "柚影"
    }

    signingConfigs {
        if (signingReady) {
            create("youyingRelease") {
                storeFile = File(releaseSigning.getValue("YOUYING_KEYSTORE"))
                storePassword = releaseSigning.getValue("YOUYING_STORE_PASSWORD")
                keyAlias = releaseSigning.getValue("YOUYING_KEY_ALIAS")
                keyPassword = releaseSigning.getValue("YOUYING_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-dev"
            manifestPlaceholders["appLabel"] = "柚影 · 测试"
        }
        release {
            if (signingReady) signingConfig = signingConfigs.getByName("youyingRelease")
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
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.14.1")
    implementation("androidx.media3:media3-database:1.5.1")
    implementation("androidx.media3:media3-datasource-okhttp:1.5.1")
    implementation("androidx.media3:media3-exoplayer:1.5.1")
    implementation("androidx.media3:media3-exoplayer-hls:1.5.1")
    implementation("androidx.media3:media3-exoplayer-dash:1.5.1")
    implementation("androidx.media3:media3-ui:1.5.1")
}
