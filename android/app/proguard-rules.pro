# حفظ Flutter classes
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# حفظ Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# حفظ ML Kit
-keep class com.google.mlkit.** { *; }

# حفظ TensorFlow Lite
-keep class org.tensorflow.** { *; }

# حفظ CameraX
-keep class androidx.camera.** { *; }

# Room
-keep class * extends androidx.room.RoomDatabase
-keep @androidx.room.Entity class *

# Retrofit/OkHttp
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.squareup.okhttp.** { *; }
-keep class okhttp3.** { *; }
-keep class retrofit2.** { *; }

# Glide
-keep public class * implements com.bumptech.glide.module.GlideModule
-keep class * extends com.bumptech.glide.module.AppGlideModule