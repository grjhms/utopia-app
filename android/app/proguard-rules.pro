# Flutter Proguard Rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Firebase Messaging
-keep class io.flutter.plugins.firebase.messaging.** { *; }
-keepclassmembers class io.flutter.plugins.firebase.messaging.** { *; }
-keep class com.google.firebase.messaging.** { *; }
-keepclassmembers class com.google.firebase.messaging.** { *; }
-dontwarn com.google.firebase.messaging.**

# Play Core rules to fix R8 errors
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# ── flutter_local_notifications ──
# Keep ALL classes, members, constructors, and field names.
# The plugin uses Gson reflection to serialize/deserialize notification
# details into AlarmManager intents. R8 stripping field names or
# constructors causes zonedSchedule to silently fail in release builds.
-keep class com.dexterous.** { *; }
-keepclassmembers class com.dexterous.** { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keepclassmembers class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.**

# Keep all enum values (ScheduleMode, Importance, Priority, etc.)
-keepclassmembers enum com.dexterous.flutterlocalnotifications.** {
    **[] $VALUES;
    public *;
}

# ── Gson (critical for flutter_local_notifications serialization) ──
-keep class com.google.gson.** { *; }
-keepclassmembers class com.google.gson.** { *; }
-dontwarn com.google.gson.**
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

# Keep generic type information for Gson TypeToken
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

# Keep fields that Gson accesses via reflection
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# ── just_audio, audio_session, & ExoPlayer/Media3 ──
# Keep ExoPlayer/Media3 classes to prevent R8 from stripping them in release builds
-keep class com.google.android.exoplayer2.** { *; }
-keep class androidx.media3.** { *; }

# Keep just_audio and audio_session native bindings
-keep class com.ryanheise.just_audio.** { *; }
-keepclassmembers class com.ryanheise.just_audio.** { *; }
-keep class com.ryanheise.audio_session.** { *; }
-keepclassmembers class com.ryanheise.audio_session.** { *; }
-dontwarn com.ryanheise.just_audio.**
-dontwarn com.ryanheise.audio_session.**

