#!/bin/bash
# 1. Создаем структуру папок
mkdir -p app/src/main/java/com/localai/chat
mkdir -p app/src/main/res/values
mkdir -p app/src/main/res/layout

# 2. Файл свойств (важен для стабильности)
cat <<'EOF' > gradle.properties
android.useAndroidX=true
android.enableJetifier=true
kotlin.code.style=official
EOF

# 3. Упрощенный settings.gradle.kts (без блокировки)
cat <<'EOF' > settings.gradle.kts
rootProject.name = "Local AI Chat"
include(":app")
EOF

# 4. Корневой build.gradle.kts
cat <<'EOF' > build.gradle.kts
plugins {
    id("com.android.application") version "8.4.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
}
EOF

# 5. Модуль приложения (репозитории теперь внутри, так надежнее для Gradle 9)
cat <<'EOF' > app/build.gradle.kts
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.localai.chat"
    compileSdk = 34
    defaultConfig {
        applicationId = "com.localai.chat"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }
    buildFeatures { compose = true }
    composeOptions { kotlinCompilerExtensionVersion = "1.5.1" }
    compileOptions { 
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17 
    }
    kotlinOptions { jvmTarget = "17" }
}

repositories {
    google()
    mavenCentral()
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.activity:activity-compose:1.8.2")
    implementation(platform("androidx.compose:compose-bom:2023.10.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
}
EOF

# 6. Базовые ресурсы (чтобы сборщик ресурсов не падал)
cat <<'EOF' > app/src/main/res/values/strings.xml
<resources>
    <string name="app_name">Local AI Chat</string>
</resources>
EOF

cat <<'EOF' > app/src/main/res/values/themes.xml
<resources>
    <style name="Theme.LocalAIChat" parent="android:Theme.Material.Light.NoActionBar" />
</resources>
EOF

# 7. Манифест
cat <<'EOF' > app/src/main/AndroidManifest.xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="@string/app_name"
        android:theme="@style/Theme.LocalAIChat"
        android:usesCleartextTraffic="true">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF

# 8. MainActivity
cat <<'EOF' > app/src/main/java/com/localai/chat/MainActivity.kt
package com.localai.chat

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.Text

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            Text("Победа! Приложение запустилось.")
        }
    }
}
EOF
