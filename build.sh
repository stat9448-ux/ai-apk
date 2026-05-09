#!/bin/bash
# 1. Подготовка структуры
mkdir -p app/src/main/java/com/localai/chat
mkdir -p app/src/main/res/values

# 2. Настройки Gradle
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

# 3. Конфигурация модуля (v4.5)
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
        versionCode = 25
        versionName = "4.5"
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
    
    // Room (фиксируем версию для стабильности KSP)
    val room_version = "2.6.1"
    implementation("androidx.room:room-runtime:$room_version")
    implementation("androidx.room:room-ktx:$room_version")
    ksp("androidx.room:room-compiler:$room_version")
    
    implementation("com.squareup.retrofit2:retrofit:2.9.0")
    implementation("com.squareup.retrofit2:converter-gson:2.9.0")
}
EOF

# 4. Манифест
cat <<'EOF' > app/src/main/AndroidManifest.xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <application android:label="Ollama Master" android:usesCleartextTraffic="true" android:theme="@android:style/Theme.DeviceDefault.NoActionBar">
        <activity android:name=".MainActivity" android:exported="true" android:windowSoftInputMode="adjustResize">
            <intent-filter><action android:name="android.intent.action.MAIN" /><category android:name="android.intent.category.LAUNCHER" /></intent-filter>
        </activity>
    </application>
</manifest>
EOF

# 5. КОД ПРИЛОЖЕНИЯ
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
// 1. Модель данных (Entity)
@Entity(tableName = "chat_v15")
data class MessageEntity(
    @PrimaryKey(autoGenerate = true) val id: Int = 0,
    val role: String,
    val content: String
)

// 2. DAO
@Dao
interface ChatDao {
    @Query("SELECT * FROM chat_v15 ORDER BY id ASC")
    fun getAll(): Flow<List<MessageEntity>>
    @Insert
    suspend fun insert(msg: MessageEntity)
    @Query("DELETE FROM chat_v15")
    suspend fun clearAll()
}

// 3. Database
@Database(entities = [MessageEntity::class], version = 15, exportSchema = false)
abstract class AppDatabase : RoomDatabase() {
    abstract fun chatDao(): ChatDao
}

// 4. API (Ollama /api/chat)
data class ChatMsg(val role: String, val content: String)
data class ChatRequest(val model: String, val messages: List<ChatMsg>, val stream: Boolean = false)
data class ChatResponse(val message: ChatMsg)

interface OllamaApi {
    @POST("api/chat")
    suspend fun sendChat(@Body req: ChatRequest): ChatResponse
}

class MainActivity : ComponentActivity() {
    @OptIn(ExperimentalMaterial3Api::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        val db = Room.databaseBuilder(applicationContext, AppDatabase::class.java, "db_v15").fallbackToDestructiveMigration().build()
        val prefs = getSharedPreferences("settings", Context.MODE_PRIVATE)

        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                var ip by remember { mutableStateOf(prefs.getString("ip", "192.168.0.207") ?: "192.168.0.207") }
                var port by remember { mutableStateOf(prefs.getString("port", "11434") ?: "11434") }
                var modelName by remember { mutableStateOf(prefs.getString("model", "qwen2.5:3b") ?: "qwen2.5:3b") }
                var showSettings by remember { mutableStateOf(false) }
                
                val chatItems by db.chatDao().getAll().collectAsState(initial = emptyList())
                var input by remember { mutableStateOf("") }
                var isBusy by remember { mutableStateOf(false) }
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

                LaunchedEffect(chatItems.size) { if(chatItems.isNotEmpty()) scrollState.animateScrollToItem(chatItems.size - 1) }

                Scaffold(
                    topBar = {
                        TopAppBar(
                            title = { 
                                Column(Modifier.clickable { showSettings = !showSettings }) {
                                    Text("Ollama Master v4.5", style = MaterialTheme.typography.titleMedium)
                                    Text("$modelName @ $ip", style = MaterialTheme.typography.labelSmall, color = Color.Cyan)
                                }
                            },
                            actions = {
                                IconButton(onClick = { scope.launch { db.chatDao().clearAll() } }) {
                                    Icon(Icons.Default.DeleteSweep, null, tint = Color.Gray)
                                }
                            }
                        )
                    }
                ) { p ->
                    Column(Modifier.padding(p).fillMaxSize().background(Color(0xFF0F0F0F))) {
                        if (showSettings) {
                            Card(Modifier.padding(8.dp), colors = CardDefaults.cardColors(containerColor = Color(0xFF1A1A1A))) {
Column(Modifier.padding(12.dp)) {
                                    OutlinedTextField(value = ip, onValueChange = { ip = it; prefs.edit().putString("ip", it).apply() }, label = { Text("Server IP") }, modifier = Modifier.fillMaxWidth())
                                    OutlinedTextField(value = port, onValueChange = { port = it; prefs.edit().putString("port", it).apply() }, label = { Text("Port") }, modifier = Modifier.fillMaxWidth())
                                    OutlinedTextField(value = modelName, onValueChange = { modelName = it; prefs.edit().putString("model", it).apply() }, label = { Text("Model Name") }, modifier = Modifier.fillMaxWidth())
                                    Button(onClick = { showSettings = false }, Modifier.align(Alignment.End).padding(top = 8.dp)) { Text("Save") }
                                }
                            }
                        }

                        LazyColumn(state = scrollState, modifier = Modifier.weight(1f).padding(horizontal = 12.dp)) {
                            items(chatItems) { m ->
                                val isMe = m.role == "user"
                                Box(Modifier.fillMaxWidth().padding(vertical = 4.dp), contentAlignment = if(isMe) Alignment.CenterEnd else Alignment.CenterStart) {
                                    Text(m.content, Modifier.clip(RoundedCornerShape(12.dp))
                                        .background(if(isMe) Color(0xFF004D40) else Color(0xFF212121)).padding(12.dp), color = Color.White)
                                }
                            }
                        }

                        if(isBusy) LinearProgressIndicator(Modifier.fillMaxWidth(), color = Color.Cyan)

                        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            TextField(
                                value = input, onValueChange = {input = it}, 
                                modifier = Modifier.weight(1f), 
                                shape = RoundedCornerShape(24.dp),
                                placeholder = { Text("Type a message...") },
                                colors = TextFieldDefaults.colors(focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent)
                            )
                            Spacer(Modifier.width(8.dp))
                            FloatingActionButton(
                                onClick = {
                                    if(input.isBlank()  isBusy  api == null) return@FloatingActionButton
                                    val t = input; input = ""; isBusy = true
                                    scope.launch {
                                        db.chatDao().insert(MessageEntity(role = "user", content = t))
                                        try {
                                            val history = chatItems.map { ChatMsg(it.role, it.content) } + ChatMsg("user", t)
                                            val response = api.sendChat(ChatRequest(modelName, history))
                                            db.chatDao().insert(MessageEntity(role = "assistant", content = response.message.content))
                                        } catch(e: Exception) {
                                            db.chatDao().insert(MessageEntity(role = "assistant", content = "Error: ${e.localizedMessage}"))
                                        } finally { isBusy = false }
                                    }
                                },
                                containerColor = Color(0xFF00897B)
                            ) { Icon(Icons.Default.Send, null, tint = Color.White) }
                        }
                    }
                }
            }
        }
    }
}
EOF
