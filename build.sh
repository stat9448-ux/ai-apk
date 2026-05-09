#!/bin/bash
# 1. Структура проекта
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

# 3. Модуль
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
        versionCode = 22
        versionName = "4.2"
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
    
    // Room
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
// 1. Сначала определяем сущность
@Entity(tableName = "chat_messages")
data class ChatMessage(
    @PrimaryKey(autoGenerate = true) val id: Int = 0,
    @ColumnInfo(name = "is_user") val isUser: Boolean,
    @ColumnInfo(name = "text_content") val text: String
)

// 2. Затем DAO (используя полный путь к ChatMessage для KSP)
@Dao
interface ChatDao {
    @Query("SELECT * FROM chat_messages ORDER BY id ASC")
    fun getAllMessages(): Flow<List<ChatMessage>>
    
    @Insert
    suspend fun insertMessage(msg: ChatMessage)
    
    @Query("DELETE FROM chat_messages")
    suspend fun deleteAll()
}

// 3. Затем БД
@Database(entities = [ChatMessage::class], version = 12, exportSchema = false)
abstract class AppDb : RoomDatabase() {
    abstract fun dao(): ChatDao
}

// API структуры
data class OllamaRequest(val model: String, val prompt: String, val stream: Boolean = false)
data class OllamaResponse(val response: String)
interface OllamaApi { 
    @POST("api/generate") 
    suspend fun ask(@Body request: OllamaRequest): OllamaResponse 
}

class MainActivity : ComponentActivity() {
    @OptIn(ExperimentalMaterial3Api::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        val db = Room.databaseBuilder(applicationContext, AppDb::class.java, "ollama_final_v12")
            .fallbackToDestructiveMigration().build()
        
        val prefs = getSharedPreferences("config", Context.MODE_PRIVATE)

        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                var serverIp by remember { mutableStateOf(prefs.getString("ip", "192.168.0.207") ?: "192.168.0.207") }
                var serverPort by remember { mutableStateOf(prefs.getString("port", "11434") ?: "11434") }
                var showSettings by remember { mutableStateOf(false) }
                
                val messages by db.dao().getAllMessages().collectAsState(initial = emptyList())
                var inputText by remember { mutableStateOf("") }
                var isLoading by remember { mutableStateOf(false) }
                val scope = rememberCoroutineScope()
                val listState = rememberLazyListState()

                val api = remember(serverIp, serverPort) {
                    try {
                        Retrofit.Builder()
                            .baseUrl("http://$serverIp:$serverPort/")
                            .addConverterFactory(GsonConverterFactory.create())
                            .build().create(OllamaApi::class.java)
                    } catch (e: Exception) { null }
                }

                LaunchedEffect(messages.size) { if(messages.isNotEmpty()) listState.animateScrollToItem(messages.size - 1) }

                Scaffold(
                    topBar = {
                        TopAppBar(
                            title = { 
                                Column(Modifier.clickable { showSettings = !showSettings }) {
                                    Text("Ollama Master", style = MaterialTheme.typography.titleMedium)
                                    Text("$serverIp:$serverPort", style = MaterialTheme.typography.labelSmall, color = Color.Cyan)
                                }
                            },
                            actions = {
                                IconButton(onClick = { scope.launch { db.dao().deleteAll() } }) {
                                    Icon(Icons.Default.DeleteSweep, null, tint = Color.Gray)
                                }
                            }
                        )
                    }
                ) { padding ->
                    Column(Modifier.padding(padding).fillMaxSize().background(Color(0xFF121212))) {
                        
                        if (showSettings) {
Card(Modifier.padding(8.dp), colors = CardDefaults.cardColors(containerColor = Color(0xFF1E1E1E))) {
                                Column(Modifier.padding(12.dp)) {
                                    OutlinedTextField(
                                        value = serverIp, onValueChange = { serverIp = it; prefs.edit().putString("ip", it).apply() },
                                        label = { Text("IP адрес") }, modifier = Modifier.fillMaxWidth()
                                    )
                                    OutlinedTextField(
                                        value = serverPort, onValueChange = { serverPort = it; prefs.edit().putString("port", it).apply() },
                                        label = { Text("Порт") }, modifier = Modifier.fillMaxWidth()
                                    )
                                    Button(onClick = { showSettings = false }, Modifier.align(Alignment.End).padding(top = 8.dp)) {
                                        Text("Готово")
                                    }
                                }
                            }
                        }

                        LazyColumn(state = listState, modifier = Modifier.weight(1f).padding(horizontal = 12.dp)) {
                            items(messages) { m ->
                                Box(Modifier.fillMaxWidth().padding(vertical = 4.dp), 
                                    contentAlignment = if(m.isUser) Alignment.CenterEnd else Alignment.CenterStart) {
                                    Text(m.text, Modifier.clip(RoundedCornerShape(12.dp))
                                        .background(if(m.isUser) Color(0xFF006064) else Color(0xFF252525)).padding(12.dp), color = Color.White)
                                }
                            }
                        }

                        if(isLoading) LinearProgressIndicator(Modifier.fillMaxWidth(), color = Color.Cyan)

                        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            TextField(
                                value = inputText, onValueChange = {inputText = it}, 
                                modifier = Modifier.weight(1f), 
                                shape = RoundedCornerShape(24.dp),
                                placeholder = { Text("Задать вопрос...") },
                                colors = TextFieldDefaults.colors(focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent)
                            )
                            Spacer(Modifier.width(8.dp))
                            FloatingActionButton(
                                onClick = {
                                    if(inputText.isBlank()  isLoading  api == null) return@FloatingActionButton
                                    val text = inputText; inputText = ""; isLoading = true
                                    scope.launch {
                                        db.dao().insertMessage(ChatMessage(isUser = true, text = text))
                                        try {
                                            val response = api.ask(OllamaRequest("llama3", text))
                                            db.dao().insertMessage(ChatMessage(isUser = false, text = response.response))
                                        } catch(e: Exception) {
                                            db.dao().insertMessage(ChatMessage(isUser = false, text = "Ошибка: ${e.localizedMessage}"))
                                        } finally { isLoading = false }
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
