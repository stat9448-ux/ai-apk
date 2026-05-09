#!/bin/bash
# ДАННЫЕ ТВОЕГО СЕРВЕРА
TARGET_IP="193.32.189.220"
MODEL_NAME="llama3"

# 1. Подготовка папок
mkdir -p app/src/main/java/com/localai/chat
mkdir -p app/src/main/res/values

# 2. Системные настройки Gradle
cat <<'EOF' > gradle.properties
org.gradle.jvmargs=-Xmx3g
android.useAndroidX=true
android.enableJetifier=true
EOF

# 3. Настройка репозиториев
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

# 4. Плагины
cat <<'EOF' > build.gradle.kts
plugins {
    id("com.android.application") version "8.3.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.23" apply false
    id("com.google.devtools.ksp") version "1.9.23-1.0.19" apply false
}
EOF

# 5. Зависимости (Room + Retrofit)
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
        versionCode = 10
        versionName = "3.0"
    }
    buildFeatures { compose = true }
    composeOptions { kotlinCompilerExtensionVersion = "1.5.11" }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
}
dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.activity:activity-compose:1.8.2")
    implementation(platform("androidx.compose:compose-bom:2024.02.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.room:room-runtime:2.6.1")
    implementation("androidx.room:room-ktx:2.6.1")
    ksp("androidx.room:room-compiler:2.6.1")
    implementation("com.squareup.retrofit2:retrofit:2.9.0")
    implementation("com.squareup.retrofit2:converter-gson:2.9.0")
}
EOF

# 6. Манифест
cat <<'EOF' > app/src/main/AndroidManifest.xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <application android:label="AI Chat Private" android:usesCleartextTraffic="true" android:theme="@android:style/Theme.DeviceDefault.NoActionBar">
        <activity android:name=".MainActivity" android:exported="true" android:windowSoftInputMode="adjustResize">
            <intent-filter><action android:name="android.intent.action.MAIN" /><category android:name="android.intent.category.LAUNCHER" /></intent-filter>
        </activity>
    </application>
</manifest>
EOF

# 7. КОД ПРИЛОЖЕНИЯ (С ПАМЯТЬЮ И НОВЫМ ЧАТОМ)
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
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import retrofit2.http.*

const val SERVER_IP = "REPLACE_IP"
const val SERVER_MODEL = "REPLACE_MODEL"
@Entity(tableName = "chat_history")
data class Message(@PrimaryKey(autoGenerate = true) val id: Int = 0, val isUser: Boolean, val text: String)

@Dao
interface ChatDao {
    @Query("SELECT * FROM chat_history ORDER BY id ASC")
    fun loadHistory(): Flow<List<Message>>
    @Insert
    suspend fun saveMessage(msg: Message)
    @Query("DELETE FROM chat_history")
    suspend fun deleteHistory()
}

@Database(entities = [Message::class], version = 2, exportSchema = false)
abstract class AppDatabase : RoomDatabase() { abstract fun dao(): ChatDao }

data class OllamaReq(val model: String, val prompt: String, val stream: Boolean = false)
data class OllamaRes(val response: String)
interface OllamaApi { 
    @POST("api/generate") 
    suspend fun generate(@Body req: OllamaReq): OllamaRes 
}

class MainActivity : ComponentActivity() {
    @OptIn(ExperimentalMaterial3Api::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Создаем БД с миграцией, чтобы память не стиралась при обновах
        val db = Room.databaseBuilder(applicationContext, AppDatabase::class.java, "ollama_chat_v3")
            .fallbackToDestructiveMigration().build()
        
        val api = Retrofit.Builder()
            .baseUrl("http://$SERVER_IP:11434/")
            .addConverterFactory(GsonConverterFactory.create())
            .build().create(OllamaApi::class.java)

        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                val history by db.dao().loadHistory().collectAsState(initial = emptyList())
                var input by remember { mutableStateOf("") }
                var loading by remember { mutableStateOf(false) }
                val scope = rememberCoroutineScope()
                val listState = rememberLazyListState()

                LaunchedEffect(history.size) { if(history.isNotEmpty()) listState.animateScrollToItem(history.size - 1) }

                Scaffold(
                    topBar = {
                        TopAppBar(
                            title = { Text("AI: $SERVER_MODEL", style = MaterialTheme.typography.titleMedium) },
                            actions = {
                                // КНОПКА "НОВЫЙ ЧАТ"
                                TextButton(onClick = { scope.launch { db.dao().deleteHistory() } }) {
                                    Icon(Icons.Default.Add, contentDescription = null, tint = Color.Cyan)
                                    Text(" Новый чат", color = Color.Cyan)
                                }
                            }
                        )
                    }
                ) { p ->
                    Column(Modifier.padding(p).fillMaxSize().background(Color(0xFF0F0F0F))) {
                        LazyColumn(state = listState, modifier = Modifier.weight(1f).padding(horizontal = 12.dp)) {
                            items(history) { m ->
                                Box(Modifier.fillMaxWidth().padding(vertical = 4.dp), contentAlignment = if(m.isUser) Alignment.CenterEnd else Alignment.CenterStart) {
                                    Text(m.text, Modifier.clip(RoundedCornerShape(16.dp))
                                        .background(if(m.isUser) Color(0xFF005A5F) else Color(0xFF262626)).padding(14.dp), color = Color.White)
                                }
                            }
                        }
                        
                        if(loading) LinearProgressIndicator(Modifier.fillMaxWidth(), color = Color.Cyan)

                        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            TextField(
                                value = input, onValueChange = {input = it}, 
                                modifier = Modifier.weight(1f),
placeholder = { Text("Написать...") },
                                shape = RoundedCornerShape(24.dp),
                                colors = TextFieldDefaults.colors(focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent)
                            )
                            Spacer(Modifier.width(8.dp))
                            FloatingActionButton(
                                onClick = {
                                    if(input.isBlank() || loading) return@FloatingActionButton
                                    val userMsg = input; input = ""; loading = true
                                    scope.launch {
                                        db.dao().saveMessage(Message(isUser = true, text = userMsg))
                                        try {
                                            val res = api.generate(OllamaReq(model = SERVER_MODEL, prompt = userMsg))
                                            db.dao().saveMessage(Message(isUser = false, text = res.response))
                                        } catch(e: Exception) {
                                            db.dao().saveMessage(Message(isUser = false, text = "Ошибка связи: ${e.message}"))
                                        } finally { loading = false }
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

# ФИНАЛЬНАЯ ПОДСТАНОВКА
sed -i "s/REPLACE_IP/$TARGET_IP/" app/src/main/java/com/localai/chat/MainActivity.kt
sed -i "s/REPLACE_MODEL/$MODEL_NAME/" app/src/main/java/com/localai/chat/MainActivity.kt
