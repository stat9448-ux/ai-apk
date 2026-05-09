#!/bin/bash
# 1. Создаем структуру
mkdir -p app/src/main/java/com/localai/chat
mkdir -p app/src/main/res/values

# 2. ВАЖНО: Выделяем память (лечит Java heap space)
cat <<'EOF' > gradle.properties
org.gradle.jvmargs=-Xmx3g -XX:MaxMetaspaceSize=512m
android.useAndroidX=true
android.enableJetifier=true
kotlin.code.style=official
EOF

# 3. Настройки репозиториев
cat <<'EOF' > settings.gradle.kts
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "Local AI Chat"
include(":app")
EOF

# 4. Корневой build.gradle.kts
cat <<'EOF' > build.gradle.kts
plugins {
    id("com.android.application") version "8.3.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.23" apply false
    id("com.google.devtools.ksp") version "1.9.23-1.0.19" apply false
}
EOF

# 5. Модуль приложения (теперь с базой данных и чатом)
cat <<'EOF' > app/build.gradle.kts
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.devtools.ksp")
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
    composeOptions { kotlinCompilerExtensionVersion = "1.5.11" }
    compileOptions { 
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17 
    }
    kotlinOptions { jvmTarget = "17" }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")
    implementation("androidx.activity:activity-compose:1.8.2")
    implementation(platform("androidx.compose:compose-bom:2024.02.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    
    // База данных
    implementation("androidx.room:room-runtime:2.6.1")
    implementation("androidx.room:room-ktx:2.6.1")
    ksp("androidx.room:room-compiler:2.6.1")
}
EOF

# 6. Ресурсы
cat <<'EOF' > app/src/main/res/values/strings.xml
<resources>
    <string name="app_name">Ollama AI</string>
</resources>
EOF

# 7. Манифест
cat <<'EOF' > app/src/main/AndroidManifest.xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <application
        android:label="@string/app_name"
        android:usesCleartextTraffic="true"
        android:theme="@android:style/Theme.DeviceDefault.NoActionBar">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF

# 8. Код приложения (UI + База данных)
cat <<'EOF' > app/src/main/java/com/localai/chat/MainActivity.kt
package com.localai.chat

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Send
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.room.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
@Entity data class Msg(@PrimaryKey(autoGenerate = true) val id: Int = 0, val r: String, val c: String)
@Dao interface MsgDao {
    @Query("SELECT * FROM Msg") fun get(): Flow<List<Msg>>
    @Insert suspend fun add(m: Msg)
}
@Database(entities = [Msg::class], version = 1)
abstract class DB : RoomDatabase() { abstract fun dao(): MsgDao }

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val db = Room.databaseBuilder(this, DB::class.java, "ai.db").build()
        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                val msgs by db.dao().get().collectAsState(emptyList())
                var txt by remember { mutableStateOf("") }
                val scope = rememberCoroutineScope()

                Scaffold { p ->
                    Column(Modifier.padding(p).fillMaxSize()) {
                        LazyColumn(Modifier.weight(1f).padding(8.dp)) {
                            items(msgs) { m ->
                                Text(m.c, Modifier.padding(8.dp).clip(RoundedCornerShape(8.dp))
                                    .background(if(m.r == "u") Color.DarkGray else Color.Blue).padding(8.dp))
                            }
                        }
                        Row(Modifier.padding(8.dp)) {
                            TextField(txt, {txt = it}, Modifier.weight(1f))
                            IconButton(onClick = { 
                                val content = txt
                                txt = ""
                                scope.launch { 
                                    db.dao().add(Msg(r = "u", c = content))
                                    db.dao().add(Msg(r = "a", c = "Принял! Скоро настроим Ollama."))
                                }
                            }) { Icon(Icons.Default.Send, null) }
                        }
                    }
                }
            }
        }
    }
}
EOF
