# Flutter (engine, embedding, plugins)
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# App package (Kotlin / MethodChannel / Platform views)
-keep class com.example.genet_final.** { *; }

# Firebase & Google Play services (reflection / JNI)
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Play Core: optional deferred-component APIs referenced by Flutter embedding (often absent from classpath)
-dontwarn com.google.android.play.core.**

# Kotlin (metadata / common R8 edge cases)
-keep class kotlin.Metadata { *; }
-keepclassmembers class kotlin.Metadata {
    public <methods>;
}
