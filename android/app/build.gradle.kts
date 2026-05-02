import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// --- ส่วนโหลดค่าจาก key.properties (ฉบับ Kotlin) ---
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.example.tsl_translate_ai"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.tsl.translate.demo"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // --- ส่วนตั้งค่ากุญแจ (ฉบับ Kotlin) ---
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            // เรียกใช้การเซ็นชื่อที่เราตั้งไว้ข้างบน
            signingConfig = signingConfigs.getByName("release")
            
            // ปิดตัวลดขนาดไฟล์ชั่วคราวเพื่อให้ Build ผ่านง่ายๆ (ท่าไม้ตาย)
            isMinifyEnabled = false
            isShrinkResources = false
            
            proguardFiles(
                getDefaultProguardFile("proguard-android.txt"),
                "proguard-rules.pro"
            )
        }
    }

    dependencies {
        implementation("androidx.window:window:1.3.0")
        implementation("androidx.window:window-java:1.3.0")
        implementation("org.tensorflow:tensorflow-lite:2.13.0")
        implementation("org.tensorflow:tensorflow-lite-select-tf-ops:2.13.0")
    }
}

flutter {
    source = "../.."
}