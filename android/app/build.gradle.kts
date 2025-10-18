plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter plugin
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase services
    id("com.google.gms.google-services")
    // Room (لو تبي تستخدم kapt مع Room ORM)
    kotlin("kapt")
}

android {
    namespace = "com.example.munir_app"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

     
    defaultConfig {
        applicationId = "com.example.munir_app"
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ---------------------------
    // ✅ Firebase (BoM)
    // ---------------------------
    implementation(platform("com.google.firebase:firebase-bom:33.16.0"))
    implementation("com.google.firebase:firebase-analytics")

    // ---------------------------
    // ✅ CameraX
    // ---------------------------
    val camerax_version = "1.3.1"
    implementation("androidx.camera:camera-core:$camerax_version")
    implementation("androidx.camera:camera-camera2:$camerax_version")
    implementation("androidx.camera:camera-lifecycle:$camerax_version")
    implementation("androidx.camera:camera-view:$camerax_version")
    implementation("androidx.camera:camera-extensions:$camerax_version")

    // ---------------------------
    // ✅ ML Kit Face Detection
    // ---------------------------
    implementation("com.google.mlkit:face-detection:16.1.6")

    // ---------------------------
    // ✅ TensorFlow Lite
    // ---------------------------
    implementation("org.tensorflow:tensorflow-lite:2.14.0")
    implementation("org.tensorflow:tensorflow-lite-support:0.4.4")
    implementation("org.tensorflow:tensorflow-lite-metadata:0.4.4")

    // ---------------------------
    // ✅ Room (SQLite ORM)
    // ---------------------------
    implementation("androidx.room:room-runtime:2.6.1")
    kapt("androidx.room:room-compiler:2.6.1")
    implementation("androidx.room:room-ktx:2.6.1")

    // ---------------------------
    // ✅ Multidex (لأن minSdk 23 + Firebase)
    // ---------------------------
    implementation("androidx.multidex:multidex:2.0.1")
}
