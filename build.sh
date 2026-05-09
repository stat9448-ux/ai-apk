#!/bin/bash
# 1. Структура
mkdir -p app/src/main/java/com/localai/chat
mkdir -p app/src/main/res/values

# 2. Настройки
cat <<'EOF' > gradle.properties
org.gradle.jvmargs=-Xmx3g
android.useAndroidX=true
android.enableJetifier=true
EOF

cat <<'EOF' > settings.gradle.kts
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "MyOllamaChat"
include(":app")
EOF

cat <<'EOF' > build.gradle.kts
plugins {
    id("com.android.application") version "8.3.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.23" apply false
    id("com.google.devtools.ksp") version "1.9.23-1.0.19" apply false
}
EOF

# 3. Модуль (v4.4 - Переход на /api/chat)
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
        versionCode = 24
        versionName = "4.4"
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

# 4. Манифест
cat <<'EOF' > app/src/main/AndroidManifest.xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <application android:label="Ollama Chat" android:usesCleartextTraffic="true" android:theme="@android:style/Theme.DeviceDefault.NoActionBar">
        <activity android:name=".MainActivity" android:exported="true" android:windowSoftInputMode="adjustResize">
            <intent-filter><action android:name="android.intent.action.MAIN" /><category android:name="android.intent.category.LAUNCHER" /></intent-filter>
        </activity>
    </application>
</manifest>
EOF

# 5. КОД (v4.4 с поддержкой /api/chat)
cat <<'EOF' > app/src/main/java/com/localai/chat/MainActivity.kt
package com.localai.chat

import android.content.Context
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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

// БД
@Entity(tableName = "chat_log")
data class DbMsg(@PrimaryKey(autoGenerate = true) val id: Int = 0, val role: String, val content: String)
@Dao
interface ChatDao {
    @Query("SELECT * FROM chat_log ORDER BY id ASC")
    fun getAll(): Flow<List<DbMsg>>
    @Insert suspend fun insert(m: DbMsg)
    @Query("DELETE FROM chat_log") suspend fun clear()
}

@Database(entities = [DbMsg::class], version = 14, exportSchema = false)
abstract class AppDb : RoomDatabase() { abstract fun dao(): ChatDao }

// API для /api/chat
data class ChatMessage(val role: String, val content: String)
data class ChatReq(val model: String, val messages: List<ChatMessage>, val stream: Boolean = false)
data class ChatRes(val message: ChatMessage)

interface OllamaApi {
    @POST("api/chat")
    suspend fun chat(@Body r: ChatReq): ChatRes
}

class MainActivity : ComponentActivity() {
    @OptIn(ExperimentalMaterial3Api::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        val db = Room.databaseBuilder(applicationContext, AppDb::class.java, "ollama_v14_db")
            .fallbackToDestructiveMigration().build()
        val prefs = getSharedPreferences("config", Context.MODE_PRIVATE)

        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                var ip by remember { mutableStateOf(prefs.getString("ip", "192.168.0.207") ?: "192.168.0.207") }
                var port by remember { mutableStateOf(prefs.getString("port", "11434") ?: "11434") }
                var model by remember { mutableStateOf(prefs.getString("model", "llama3") ?: "llama3") }
                var showSettings by remember { mutableStateOf(false) }
                
                val messages by db.dao().getAll().collectAsState(initial = emptyList())
                var inputTxt by remember { mutableStateOf("") }
                var loading by remember { mutableStateOf(false) }
                val scope = rememberCoroutineScope()
                val scrollState = rememberLazyListState()

                val api = remember(ip, port) {
                    try {
                        Retrofit.Builder()
                            .baseUrl("http://$ip:$port/")
                            .addConverterFactory(GsonConverterFactory.create())
                            .build().create(OllamaApi::class.java)
                    } catch (e: Exception) { null }
                }

                LaunchedEffect(messages.size) { if(messages.isNotEmpty()) scrollState.animateScrollToItem(messages.size - 1) }

                Scaffold(
                    topBar = {
                        TopAppBar(
                            title = { 
                                Column(Modifier.clickable { showSettings = !showSettings }) {
                                    Text("Ollama Chat v4.4", style = MaterialTheme.typography.titleMedium)
                                    Text("$model @ $ip", style = MaterialTheme.typography.labelSmall, color = Color.Cyan)
                                }
                            },
                            actions = {
                                IconButton(onClick = { scope.launch { db.dao().clear() } }) {
                                    Icon(Icons.Default.DeleteSweep, null, tint = Color.Gray)
                                }
                            }
                        )
                    }
                ) { p ->
                    Column(Modifier.padding(p).fillMaxSize().background(Color(0xFF101010))) {
                        if (showSettings) {
                            Card(Modifier.padding(8.dp), colors = CardDefaults.cardColors(containerColor = Color(0xFF1E1E1E))) {
                                Column(Modifier.padding(12.dp)) {
                                    OutlinedTextField(value = ip, onValueChange = { ip = it; prefs.edit().putString("ip", it).apply() }, label = { Text("IP") }, modifier = Modifier.fillMaxWidth())
OutlinedTextField(value = port, onValueChange = { port = it; prefs.edit().putString("port", it).apply() }, label = { Text("Port") }, modifier = Modifier.fillMaxWidth())
                                    OutlinedTextField(value = model, onValueChange = { model = it; prefs.edit().putString("model", it).apply() }, label = { Text("Model (например: qwen2.5:3b)") }, modifier = Modifier.fillMaxWidth())
                                    Button(onClick = { showSettings = false }, Modifier.align(Alignment.End).padding(top = 8.dp)) { Text("OK") }
                                }
                            }
                        }

                        LazyColumn(state = scrollState, modifier = Modifier.weight(1f).padding(horizontal = 12.dp)) {
                            items(messages) { m ->
                                val isU = m.role == "user"
                                Box(Modifier.fillMaxWidth().padding(vertical = 4.dp), contentAlignment = if(isU) Alignment.CenterEnd else Alignment.CenterStart) {
                                    Text(m.content, Modifier.clip(RoundedCornerShape(12.dp))
                                        .background(if(isU) Color(0xFF006064) else Color(0xFF252525)).padding(12.dp), color = Color.White)
                                }
                            }
                        }

                        if(loading) LinearProgressIndicator(Modifier.fillMaxWidth(), color = Color.Cyan)

                        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            TextField(
                                value = inputTxt, onValueChange = {inputTxt = it}, 
                                modifier = Modifier.weight(1f), 
                                shape = RoundedCornerShape(24.dp),
                                placeholder = { Text("Сообщение...") },
                                colors = TextFieldDefaults.colors(focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent)
                            )
                            Spacer(Modifier.width(8.dp))
                            FloatingActionButton(
                                onClick = {
                                    if(inputTxt.isBlank()  loading  api == null) return@FloatingActionButton
                                    val t = inputTxt; inputTxt = ""; loading = true
                                    scope.launch {
                                        db.dao().insert(DbMsg(role = "user", content = t))
                                        try {
                                            // Отправляем всю историю чата для контекста
                                            val history = messages.map { ChatMessage(it.role, it.content) } + ChatMessage("user", t)
                                            val response = api.chat(ChatReq(model, history))
                                            db.dao().insert(DbMsg(role = "assistant", content = response.message.content))
                                        } catch(e: Exception) {
                                            db.dao().insert(DbMsg(role = "assistant", content = "Error: ${e.localizedMessage}"))
                                        } finally { loading = false }
                                    }
                                },
                                containerColor = Color(0xFF00BCD4)
                            ) { Icon(Icons.Default.Send, null, tint = Color.White) }
                        }
                    }
                }
            }
        }
    }
}
EOF
