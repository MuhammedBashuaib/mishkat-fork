# Sherpa's native JNI code looks up these Kotlin classes, fields, constructors,
# and methods by their original names. Its bundled AAR has no consumer rules;
# R8 otherwise renames/removes model configuration fields in release builds.
# Keep only this native bridge package; other app code remains optimized.
-keep class com.k2fsa.sherpa.onnx.** { *; }
