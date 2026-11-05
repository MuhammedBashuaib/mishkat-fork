import java.io.FileInputStream
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.util.Properties
import org.gradle.api.DefaultTask
import org.gradle.api.file.ConfigurableFileCollection
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.tasks.CacheableTask
import org.gradle.api.tasks.InputFiles
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.PathSensitive
import org.gradle.api.tasks.PathSensitivity
import org.gradle.api.tasks.TaskAction

plugins {
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.0"
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

@CacheableTask
abstract class AssembleOfflineRecitationModel : DefaultTask() {
    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val modelParts: ConfigurableFileCollection

    @get:OutputDirectory
    abstract val outputDirectory: DirectoryProperty

    @TaskAction
    fun assemble() {
        val partNames = listOf(
            "model.int8.onnx.part00",
            "model.int8.onnx.part01",
            "model.int8.onnx.part02",
        )
        val inputFiles = modelParts.files
        check(inputFiles.size == partNames.size) {
            "The offline recitation model requires exactly three parts."
        }
        val orderedParts = partNames.map { name ->
            inputFiles.singleOrNull { it.name == name }
                ?: throw GradleException("Missing offline recitation model part: $name")
        }
        val expectedSize = 131652502L
        val expectedSha256 =
            "0067900797b4ef012fe5da8476e71253366af945b876da614ae356c37392a6f7"
        val output = outputDirectory.file("asr/model.int8.onnx").get().asFile
        Files.createDirectories(output.parentFile.toPath())
        val temporary = Files.createTempFile(output.parentFile.toPath(), "model-", ".tmp")

        try {
            val digest = MessageDigest.getInstance("SHA-256")
            var size = 0L
            Files.newOutputStream(temporary).buffered().use { destination ->
                val buffer = ByteArray(1024 * 1024)
                orderedParts.forEach { part ->
                    part.inputStream().buffered().use { source ->
                        while (true) {
                            val count = source.read(buffer)
                            if (count == -1) break
                            size += count
                            check(size <= expectedSize) {
                                "Offline recitation model exceeds its expected size."
                            }
                            digest.update(buffer, 0, count)
                            destination.write(buffer, 0, count)
                        }
                    }
                }
            }
            val sha256 = digest.digest().joinToString("") {
                (it.toInt() and 0xff).toString(16).padStart(2, '0')
            }
            check(size == expectedSize && sha256 == expectedSha256) {
                "Offline recitation model verification failed: size=$size, SHA-256=$sha256"
            }
            try {
                Files.move(
                    temporary,
                    output.toPath(),
                    StandardCopyOption.ATOMIC_MOVE,
                    StandardCopyOption.REPLACE_EXISTING,
                )
            } catch (_: AtomicMoveNotSupportedException) {
                Files.move(temporary, output.toPath(), StandardCopyOption.REPLACE_EXISTING)
            }
        } finally {
            Files.deleteIfExists(temporary)
        }
    }
}

// Keep each source part below GitHub's file size limit; only the verified,
// reconstructed model is packaged as an Android asset.
val assembleOfflineRecitationModel = tasks.register<AssembleOfflineRecitationModel>(
    "assembleOfflineRecitationModel",
) {
    modelParts.from(
        "model/asr/model.int8.onnx.part00",
        "model/asr/model.int8.onnx.part01",
        "model/asr/model.int8.onnx.part02",
    )
    outputDirectory.set(layout.buildDirectory.dir("generated/offlineRecitationAssets"))
}

androidComponents {
    onVariants { variant ->
        variant.sources.assets?.addGeneratedSourceDirectory(assembleOfflineRecitationModel) {
            it.outputDirectory
        }
    }
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(FileInputStream(keystorePropertiesFile))
    }
}
val isReleaseBuild = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
val useTestSigningForRelease = providers.gradleProperty("useTestSigningForRelease")
    .orNull
    .equals("true", ignoreCase = true)

if (isReleaseBuild && !keystorePropertiesFile.exists() && !useTestSigningForRelease) {
    throw GradleException(
        "Release signing requires android/key.properties and a private upload keystore. " +
            "For local test builds only, explicitly set -PuseTestSigningForRelease=true."
    )
}

android {
    namespace = "com.dakomn.mishkatapp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.dakomn.mishkatapp"
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
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (useTestSigningForRelease) {
                signingConfigs.getByName("debug")
            } else {
                signingConfigs.getByName("release")
            }
        }
    }
    buildFeatures {
        compose = true
    }

    androidResources {
        // Sherpa reads the bundled model directly from the APK, without a
        // duplicate 126 MB extraction or a first-run network download.
        noCompress += listOf("onnx")
    }

}

dependencies {
    implementation(files("libs/sherpa-onnx-static-link-onnxruntime-1.13.8.aar"))
    implementation("androidx.glance:glance-appwidget:1.2.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
