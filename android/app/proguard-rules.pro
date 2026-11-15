# Sherpa's native JNI code looks up these Kotlin classes, fields, constructors,
# and methods by their original names. Its bundled AAR has no consumer rules;
# R8 otherwise renames/removes model configuration fields in release builds.
# Keep only this native bridge package; other app code remains optimized.
-keep class com.k2fsa.sherpa.onnx.** { *; }

# flutter_local_notifications 18 uses Gson 2.8.9 to persist scheduled alarms.
# R8 must retain TypeToken signatures and the reflected notification model;
# otherwise reading the pending calendar can fail only in release builds.
-keepattributes Signature,*Annotation*
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
