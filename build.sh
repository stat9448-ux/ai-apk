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
        versionCode = 23
        versionName = "4.3"
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
    
    // Room - фиксированные версии для KSP
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
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import retrofit2.http.*
// 1. Сущность (максимально просто)
@androidx.room.Entity(tableName = "messages_v13")
data class DbMsg(
    @androidx.room.PrimaryKey(autoGenerate = true) val id: Int = 0,
    @androidx.room.ColumnInfo(name = "is_u") val isU: Boolean,
    @androidx.room.ColumnInfo(name = "txt") val txt: String
)

// 2. DAO
@androidx.room.Dao
interface ChatDao {
    @androidx.room.Query("SELECT * FROM messages_v13 ORDER BY id ASC")
    fun getStream(): Flow<List<DbMsg>>
    
    @androidx.room.Insert
    suspend fun add(msg: DbMsg)
    
    @androidx.room.Query("DELETE FROM messages_v13")
    suspend fun clear()
}

// 3. Database
@androidx.room.Database(entities = [DbMsg::class], version = 13, exportSchema = false)
abstract class AppDb : androidx.room.RoomDatabase() {
    abstract fun dao(): ChatDao
}

// API
data class OReq(val model: String, val prompt: String, val stream: Boolean = false)
data class ORes(val response: String)
interface OllamaApi { @POST("api/generate") suspend fun ask(@Body r: OReq): ORes }

class MainActivity : ComponentActivity() {
    @OptIn(ExperimentalMaterial3Api::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        val database = androidx.room.Room.databaseBuilder(
            applicationContext, AppDb::class.java, "ollama_v13_db"
        ).fallbackToDestructiveMigration().build()
        
        val prefs = getSharedPreferences("config", Context.MODE_PRIVATE)

        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                var ip by remember { mutableStateOf(prefs.getString("ip", "192.168.0.207") ?: "192.168.0.207") }
                var port by remember { mutableStateOf(prefs.getString("port", "11434") ?: "11434") }
                var settingsOpen by remember { mutableStateOf(false) }
                
                val chatItems by database.dao().getStream().collectAsState(initial = emptyList())
                var input by remember { mutableStateOf("") }
                var busy by remember { mutableStateOf(false) }
                val scope = rememberCoroutineScope()
                val scroll = rememberLazyListState()

                val api = remember(ip, port) {
                    try {
                        Retrofit.Builder()
                            .baseUrl("http://$ip:$port/")
                            .addConverterFactory(GsonConverterFactory.create())
                            .build().create(OllamaApi::class.java)
                    } catch (e: Exception) { null }
                }

                LaunchedEffect(chatItems.size) { if(chatItems.isNotEmpty()) scroll.animateScrollToItem(chatItems.size - 1) }

                Scaffold(
                    topBar = {
                        TopAppBar(
                            title = { 
                                Column(Modifier.clickable { settingsOpen = !settingsOpen }) {
                                    Text("Ollama Master v4.3", style = MaterialTheme.typography.titleMedium)
                                    Text("$ip:$port (нажми для смены)", style = MaterialTheme.typography.labelSmall, color = Color.Cyan)
                                }
                            },
                            actions = {
                                IconButton(onClick = { scope.launch { database.dao().clear() } }) {
                                    Icon(Icons.Default.DeleteSweep, null, tint = Color.Gray)
                                }
                            }
                        )
                    }
                ) { p ->
                    Column(Modifier.padding(p).fillMaxSize().background(Color(0xFF121212))) {
                        
                        if (settingsOpen) {
                            Card(Modifier.padding(8.dp), colors = CardDefaults.cardColors(containerColor = Color(0xFF1E1E1E))) {
Column(Modifier.padding(12.dp)) {
                                    OutlinedTextField(value = ip, onValueChange = { ip = it; prefs.edit().putString("ip", it).apply() }, label = { Text("IP адрес") }, modifier = Modifier.fillMaxWidth())
                                    OutlinedTextField(value = port, onValueChange = { port = it; prefs.edit().putString("port", it).apply() }, label = { Text("Порт") }, modifier = Modifier.fillMaxWidth())
                                    Button(onClick = { settingsOpen = false }, Modifier.align(Alignment.End).padding(top = 8.dp)) { Text("Применить") }
                                }
                            }
                        }

                        LazyColumn(state = scroll, modifier = Modifier.weight(1f).padding(horizontal = 12.dp)) {
                            items(chatItems) { m ->
                                Box(Modifier.fillMaxWidth().padding(vertical = 4.dp), contentAlignment = if(m.isU) Alignment.CenterEnd else Alignment.CenterStart) {
                                    Text(m.txt, Modifier.clip(RoundedCornerShape(12.dp))
                                        .background(if(m.isU) Color(0xFF006064) else Color(0xFF252525)).padding(12.dp), color = Color.White)
                                }
                            }
                        }

                        if(busy) LinearProgressIndicator(Modifier.fillMaxWidth(), color = Color.Cyan)

                        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            TextField(
                                value = input, onValueChange = {input = it}, 
                                modifier = Modifier.weight(1f), 
                                shape = RoundedCornerShape(24.dp),
                                placeholder = { Text("Задать вопрос...") },
                                colors = TextFieldDefaults.colors(focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent)
                            )
                            Spacer(Modifier.width(8.dp))
                            FloatingActionButton(
                                onClick = {
                                    if(input.isBlank()  busy  api == null) return@FloatingActionButton
                                    val t = input; input = ""; busy = true
                                    scope.launch {
                                        database.dao().add(DbMsg(isU = true, txt = t))
                                        try {
                                            val res = api.ask(OReq("llama3", t))
                                            database.dao().add(DbMsg(isU = false, txt = res.response))
                                        } catch(e: Exception) {
                                            database.dao().add(DbMsg(isU = false, txt = "Ошибка связи: ${e.localizedMessage}"))
                                        } finally { busy = false }
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
