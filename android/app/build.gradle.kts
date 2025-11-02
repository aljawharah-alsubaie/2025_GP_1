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
        versionCode = flutter.versionCode.toInt()
        versionName = flutter.versionName
        multiDexEnabled = true
        
        // 🔧 إضافة هذه الإعدادات الإضافية
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        
        // 🎯 إعدادات TensorFlow Lite
        ndk {
            abiFilters.addAll(listOf("armeabi-v7a", "arm64-v8a", "x86", "x86_64"))
        }
    }

    buildTypes {
        getByName("debug") {
            isDebuggable = true
            // إضافة لعملية التصحيح
            extra["enableCrashlytics"] = false
        }
        
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // 🎯 إضافة هذا القسم لتعطيل التحقق من Google Play Services
    packaging {
        resources {
            excludes += setOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/license.txt",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt",
                "META-INF/notice.txt",
                "META-INF/ASL2.0",
                "META-INF/*.kotlin_module",
                "META-INF/proguard/coroutines.pro",
                "/META-INF/{AL2.0,LGPL2.1}",
                "**/libflutter.so"
            )
            pickFirsts += setOf(
                "META-INF/kotlinx_coroutines_core.version",
                "META-INF/common.kotlin_module",
                "META-INF/androidx.*",
                "META-INF/proguard/coroutines.pro"
            )
        }
    }

    // 🎯 إعدادات البناء
    buildFeatures {
        viewBinding = true
        buildConfig = true
    }

    // 🎯 إعدادات lint
    lint {
        abortOnError = false
        checkReleaseBuilds = false
        disable.addAll(setOf("GradleDependency", "OldTargetApi"))
    }

    // 🎯 دعم Java 8 features
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ---------------------------
    // ✅ Firebase (BoM) - محدث
    // ---------------------------
    implementation(platform("com.google.firebase:firebase-bom:33.16.0"))
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-firestore")
    implementation("com.google.firebase:firebase-storage")
    
    // ---------------------------
    // ✅ Google Play Services - محدث
    // ---------------------------
    implementation("com.google.android.gms:play-services-auth:21.0.0")
    implementation("com.google.android.gms:play-services-vision:20.1.3")
    
    // ---------------------------
    // ✅ CameraX - محدث
    // ---------------------------
    val camerax_version = "1.3.1"
    implementation("androidx.camera:camera-core:$camerax_version")
    implementation("androidx.camera:camera-camera2:$camerax_version")
    implementation("androidx.camera:camera-lifecycle:$camerax_version")
    implementation("androidx.camera:camera-view:$camerax_version")
    implementation("androidx.camera:camera-extensions:$camerax_version")
    implementation("androidx.camera:camera-video:$camerax_version")

    // ---------------------------
    // ✅ ML Kit Face Detection - محدث
    // ---------------------------
    implementation("com.google.mlkit:face-detection:16.1.6")
    implementation("com.google.mlkit:vision-common:17.3.0")

    // ---------------------------
    // ✅ TensorFlow Lite - محدث
    // ---------------------------
    implementation("org.tensorflow:tensorflow-lite:2.14.0")
    implementation("org.tensorflow:tensorflow-lite-support:0.4.4")
    implementation("org.tensorflow:tensorflow-lite-metadata:0.4.4")
    implementation("org.tensorflow:tensorflow-lite-gpu:2.14.0")
    implementation("org.tensorflow:tensorflow-lite-task-vision:0.4.4")

    // ---------------------------
    // ✅ Room (SQLite ORM) - محدث
    // ---------------------------
    implementation("androidx.room:room-runtime:2.6.1")
    kapt("androidx.room:room-compiler:2.6.1")
    implementation("androidx.room:room-ktx:2.6.1")

    // ---------------------------
    // ✅ Multidex - محدث
    // ---------------------------
    implementation("androidx.multidex:multidex:2.0.1")

    // ---------------------------
    // ✅ AndroidX Libraries - إضافات مهمة
    // ---------------------------
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.7.0")
    implementation("androidx.lifecycle:lifecycle-livedata-ktx:2.7.0")
    implementation("androidx.activity:activity-ktx:1.8.2")
    implementation("androidx.fragment:fragment-ktx:1.6.2")
    
    // ---------------------------
    // ✅ Material Design - محدث
    // ---------------------------
    implementation("com.google.android.material:material:1.11.0")

    // ---------------------------
    // ✅ Networking - إضافات للاتصال بالإنترنت
    // ---------------------------
    implementation("com.squareup.retrofit2:retrofit:2.9.0")
    implementation("com.squareup.retrofit2:converter-gson:2.9.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.okhttp3:logging-interceptor:4.12.0")

    // ---------------------------
    // ✅ Image Processing - معالجة الصور
    // ---------------------------
    implementation("com.github.bumptech.glide:glide:4.16.0")

    // ---------------------------
    // ✅ Audio/Video - للصوت والفيديو
    // ---------------------------
    implementation("androidx.media:media:1.7.0")

    // ---------------------------
    // ✅ Java 8+ API Desugaring - مهم للتطبيقات الحديثة
    // ---------------------------
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

    // ---------------------------
    // ✅ Testing Dependencies - للاختبارات
    // ---------------------------
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.1.5")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.5.1")
    androidTestImplementation("androidx.test:runner:1.5.2")
    androidTestImplementation("androidx.test:rules:1.5.2")
}

// 🎯 إضافة هذا القسم لتعطيل التحقق من metadata
configurations.all {
    resolutionStrategy {
        // حل تعارضات المكتبات
        force("androidx.core:core-ktx:1.12.0")
        force("androidx.appcompat:appcompat:1.6.1")
        force("com.google.android.material:material:1.11.0")
        
        // تجاهل بعض المكتبات المسببة للمشاكل
        exclude(group = "com.google.android.gms", module = "play-services-measurement")
        exclude(group = "com.google.android.gms", module = "play-services-measurement-sdk")
        exclude(group = "com.google.android.gms", module = "play-services-measurement-impl")
        exclude(group = "com.google.android.gms", module = "play-services-measurement-sdk-api")
        exclude(group = "com.google.android.gms", module = "play-services-measurement-api")
    }
}

// 🎯 إعدادات Firebase
apply(plugin = "com.google.gms.google-services")