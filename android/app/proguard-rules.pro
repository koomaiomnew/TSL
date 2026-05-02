# TensorFlow Lite rules
-keep class org.tensorflow.lite.** { *; }
-keep class org.tensorflow.lite.gpu.** { *; }

# Google ML Kit rules
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }

# บอก R8 ว่าไม่ต้องเตือนเรื่องคลาสที่หายไป (ตัวที่ทำให้ Error เมื่อกี้)
-dontwarn org.tensorflow.lite.gpu.**
-dontwarn javax.annotation.**