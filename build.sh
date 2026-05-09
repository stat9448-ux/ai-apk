#!/bin/bash
# ДАННЫЕ ТВОЕГО СЕРВЕРА
TARGET_IP="193.32.189.220"
MODEL_NAME="llama3"

# 1. Структура проекта
mkdir -p app/src/main/java/com/localai/chat
mkdir -p app/src/main/res/values

# 2. Настройки памяти
cat <<'EOF' > gradle.properties
org.gradle.jvmargs=-Xmx3g
android.useAndroidX=true
android.enableJetifier=true
EOF

# 3. Репозитории
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
rootProject.name = "MyOllamaChat"
include(":app")
EOF

# 4. Корневой билд
cat <<'EOF' > build.gradle.kts
plugins {
    id("com.android.application") version "8.3.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.23" apply false
    id("com.google.devtools.ksp") version "1.9.23-1.0.19" apply false
}
EOF

# 5. Билд приложения (Исправлены зависимости Room и KSP)
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
        versionCode = 8
        versionName = "2.8"
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
    implementation("androidx.activity:activity-compose:1.8.2")
    implementation(platform("androidx.compose:compose-bom:2024.02.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    
    // Room - база данных (исправлено)
    val room_version = "2.6.1"
    implementation("androidx.room:room-runtime:$room_version")
    implementation("androidx.room:room-ktx:$room_version")
    ksp("androidx.room:room-compiler:$room_version")
    
    // Сеть
    implementation("com.squareup.retrofit2:retrofit:2.9.0")
    implementation("com.squareup.retrofit2:converter-gson:2.9.0")
}
EOF

# 6. Манифест
cat <<'EOF' > app/src/main/AndroidManifest.xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <application android:label="Ollama Mobile" android:usesCleartextTraffic="true" android:theme="@android:style/Theme.DeviceDefault.NoActionBar">
        <activity android:name=".MainActivity" android:exported="true" android:windowSoftInputMode="adjustResize">
            <intent-filter><action android:name="android.intent.action.MAIN" /><category android:name="android.intent.category.LAUNCHER" /></intent-filter>
        </activity>
    </application>
</manifest>
EOF

# 7. Генерируем MainActivity (Добавлены пропущенные импорты типов для Room)
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
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.room.*
import androidx.room.Entity
import androidx.room.PrimaryKey
import androidx.room.Dao
import androidx.room.Query
import androidx.room.Insert
import androidx.room.Database
import androidx.room.RoomDatabase
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import retrofit2.http.*

// Константы (будут заменены через sed)
const val API_IP = "REPLACE_IP"
const val API_MODEL = "REPLACE_MODEL"

@Entity(tableName = "messages")
data class Msg(
    @PrimaryKey(autoGenerate = true) val id: Int = 0,
    val isUser: Boolean,
    val text: String
)

@Dao
interface ChatDao {
    @Query("SELECT * FROM messages ORDER BY id ASC")
    fun getAll(): Flow<List<Msg>>
    @Insert
    suspend fun insert(msg: Msg)
    @Query("DELETE FROM messages")
    suspend fun clearAll()
}

@Database(entities = [Msg::class], version = 1, exportSchema = false)
abstract class AppDatabase : RoomDatabase() {
    abstract fun chatDao(): ChatDao
}

data class OllamaRequest(val model: String, val prompt: String, val stream: Boolean = false)
data class OllamaResponse(val response: String)
interface OllamaApi { @POST("/api/generate") suspend fun ask(@Body req: OllamaRequest): OllamaResponse }

class MainActivity : ComponentActivity() {
    @OptIn(ExperimentalMaterial3Api::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        val db = androidx.room.Room.databaseBuilder(
            applicationContext,
            AppDatabase::class.java, "chat_db_final"
        ).fallbackToDestructiveMigration().build()
        
        val api = Retrofit.Builder()
            .baseUrl("http://$API_IP:11434")
            .addConverterFactory(GsonConverterFactory.create())
            .build().create(OllamaApi::class.java)

        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                val msgs by db.chatDao().getAll().collectAsState(initial = emptyList())
                var inputText by remember { mutableStateOf("") }
                var isTyping by remember { mutableStateOf(false) }
                val scope = rememberCoroutineScope()
                val scrollState = rememberLazyListState()

                LaunchedEffect(msgs.size) { 
                    if (msgs.isNotEmpty()) scrollState.animateScrollToItem(msgs.size - 1) 
                }

                Scaffold(
                    topBar = {
                        CenterAlignedTopAppBar(
                            title = { Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Text("Ollama Remote", style = MaterialTheme.typography.titleMedium)
                                Text(API_IP, style = MaterialTheme.typography.labelSmall, color = Color.Cyan)
                            }},
                            actions = { IconButton(onClick = { scope.launch { db.chatDao().clearAll() } }) { Icon(Icons.Default.DeleteSweep, null) } }
                        )
                    }
                ) { padding ->
                    Column(Modifier.padding(padding).fillMaxSize().background(Color(0xFF121212))) {
                        LazyColumn(state = scrollState, modifier = Modifier.weight(1f).padding(horizontal = 12.dp)) {
                            items(msgs) { m ->
                                Box(Modifier.fillMaxWidth().padding(vertical = 4.dp), contentAlignment = if(m.isUser) Alignment.CenterEnd else Alignment.CenterStart) {
                                    Text(m.text, Modifier.clip(RoundedCornerShape(16.dp))
                                        .background(if(m.isUser) Color(0xFF00ADB5) else Color(0xFF252525)).padding(14.dp), color = Color.White)
}
                            }
                        }
                        if(isTyping) LinearProgressIndicator(Modifier.fillMaxWidth(), color = Color.Cyan)
                        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            TextField(
                                value = inputText, onValueChange = {inputText = it}, 
                                modifier = Modifier.weight(1f), 
                                placeholder = { Text("Задайте вопрос...") },
                                shape = RoundedCornerShape(28.dp),
                                colors = TextFieldDefaults.colors(focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent)
                            )
                            Spacer(Modifier.width(8.dp))
                            FloatingActionButton(
                                onClick = {
                                    if(inputText.isBlank() || isTyping) return@FloatingActionButton
                                    val promptText = inputText; inputText = ""; isTyping = true
                                    scope.launch {
                                        db.chatDao().insert(Msg(isUser = true, text = promptText))
                                        try {
                                            val res = api.ask(OllamaRequest(model = API_MODEL, prompt = promptText))
                                            db.chatDao().insert(Msg(isUser = false, text = res.response))
                                        } catch(e: Exception) {
                                            db.chatDao().insert(Msg(isUser = false, text = "Ошибка: ${e.localizedMessage}"))
                                        } finally { isTyping = false }
                                    }
                                },
                                containerColor = Color(0xFF00ADB5)
                            ) { Icon(Icons.Default.Send, null, tint = Color.White) }
                        }
                    }
                }
            }
        }
    }
}
EOF

# Вставляем IP и модель
sed -i "s/REPLACE_IP/$TARGET_IP/" app/src/main/java/com/localai/chat/MainActivity.kt
sed -i "s/REPLACE_MODEL/$MODEL_NAME/" app/src/main/java/com/localai/chat/MainActivity.kt
