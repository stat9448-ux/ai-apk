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

# 3. Модуль (Версия 4.0 - Полная динамика)
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
        versionCode = 20
        versionName = "4.0"
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
    <application android:label="Ollama Master" android:usesCleartextTraffic="true" android:theme="@android:style/Theme.DeviceDefault.NoActionBar">
        <activity android:name=".MainActivity" android:exported="true" android:windowSoftInputMode="adjustResize">
            <intent-filter><action android:name="android.intent.action.MAIN" /><category android:name="android.intent.category.LAUNCHER" /></intent-filter>
        </activity>
    </application>
</manifest>
EOF

# 5. КОД ПРИЛОЖЕНИЯ (С МЕНЯЕМЫМ IP И ПОРТОМ)
cat <<'EOF' > app/src/main/java/com/localai/chat/MainActivity.kt
package com.localai.chat

import android.content.Context
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

// БД
@Entity(tableName = "messages")
data class Msg(@PrimaryKey(autoGenerate = true) val id: Int = 0, val isUser: Boolean, val text: String)
@Dao
interface ChatDao {
    @Query("SELECT * FROM messages ORDER BY id ASC")
    fun getAll(): Flow<List<Msg>>
    @Insert suspend fun insert(m: Msg)
    @Query("DELETE FROM messages") suspend fun clear()
}

@Database(entities = [Msg::class], version = 10, exportSchema = false)
abstract class AppDb : RoomDatabase() { abstract fun dao(): ChatDao }

// API
data class Req(val model: String, val prompt: String, val stream: Boolean = false)
data class Res(val response: String)
interface OllamaApi { @POST("api/generate") suspend fun ask(@Body r: Req): Res }

class MainActivity : ComponentActivity() {
    @OptIn(ExperimentalMaterial3Api::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        val db = Room.databaseBuilder(applicationContext, AppDb::class.java, "ollama_final_db")
            .fallbackToDestructiveMigration().build()
        
        val prefs = getSharedPreferences("config", Context.MODE_PRIVATE)

        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                // Состояния для настроек
                var serverIp by remember { mutableStateOf(prefs.getString("ip", "192.168.0.207") ?: "") }
                var serverPort by remember { mutableStateOf(prefs.getString("port", "11434") ?: "") }
                var showSettings by remember { mutableStateOf(false) }
                
                val msgs by db.dao().getAll().collectAsState(initial = emptyList())
                var inputTxt by remember { mutableStateOf("") }
                var loading by remember { mutableStateOf(false) }
                val scope = rememberCoroutineScope()
                val listState = rememberLazyListState()

                // Динамическое создание API при изменении IP/Порта
                val api = remember(serverIp, serverPort) {
                    try {
                        Retrofit.Builder()
                            .baseUrl("http://$serverIp:$serverPort/")
                            .addConverterFactory(GsonConverterFactory.create())
                            .build().create(OllamaApi::class.java)
                    } catch (e: Exception) { null }
                }

                LaunchedEffect(msgs.size) { if(msgs.isNotEmpty()) listState.animateScrollToItem(msgs.size - 1) }

                Scaffold(
                    topBar = {
                        TopAppBar(
                            title = { 
                                Column(Modifier.clickable { showSettings = !showSettings }) {
                                    Text("Ollama Connect", style = MaterialTheme.typography.titleMedium)
                                    Text("$serverIp:$serverPort (нажми для смены)", style = MaterialTheme.typography.labelSmall, color = Color.Cyan)
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
                    Column(Modifier.padding(p).fillMaxSize().background(Color(0xFF121212))) {
                        
                        // ПАНЕЛЬ НАСТРОЕК
                        if (showSettings) {
                            Card(Modifier.padding(8.dp), colors = CardDefaults.cardColors(containerColor = Color(0xFF1E1E1E))) {
                                Column(Modifier.padding(12.dp)) {
                                    OutlinedTextField(
                                        value = serverIp, onValueChange = { serverIp = it; prefs.edit().putString("ip", it).apply() },
label = { Text("Server IP") }, modifier = Modifier.fillMaxWidth()
                                    )
                                    OutlinedTextField(
                                        value = serverPort, onValueChange = { serverPort = it; prefs.edit().putString("port", it).apply() },
                                        label = { Text("Port") }, modifier = Modifier.fillMaxWidth()
                                    )
                                    Button(onClick = { showSettings = false }, Modifier.padding(top = 8.dp).align(Alignment.End)) {
                                        Text("Готово")
                                    }
                                }
                            }
                        }

                        LazyColumn(state = listState, modifier = Modifier.weight(1f).padding(horizontal = 12.dp)) {
                            items(msgs) { m ->
                                Box(Modifier.fillMaxWidth().padding(vertical = 4.dp), 
                                    contentAlignment = if(m.isUser) Alignment.CenterEnd else Alignment.CenterStart) {
                                    Text(m.text, Modifier.clip(RoundedCornerShape(12.dp))
                                        .background(if(m.isUser) Color(0xFF006064) else Color(0xFF252525)).padding(12.dp), color = Color.White)
                                }
                            }
                        }

                        if(loading) LinearProgressIndicator(Modifier.fillMaxWidth(), color = Color.Cyan)

                        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            TextField(
                                value = inputTxt, onValueChange = {inputTxt = it}, 
                                modifier = Modifier.weight(1f), 
                                shape = RoundedCornerShape(24.dp),
                                placeholder = { Text("Спросить AI...") },
                                colors = TextFieldDefaults.colors(focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent)
                            )
                            Spacer(Modifier.width(8.dp))
                            FloatingActionButton(
                                onClick = {
                                    if(inputTxt.isBlank()  loading  api == null) return@FloatingActionButton
                                    val t = inputTxt; inputTxt = ""; loading = true
                                    scope.launch {
                                        db.dao().insert(Msg(isUser = true, text = t))
                                        try {
                                            val r = api.ask(Req("llama3", t))
                                            db.dao().insert(Msg(isUser = false, text = r.response))
                                        } catch(e: Exception) {
                                            db.dao().insert(Msg(isUser = false, text = "Ошибка подключения к $serverIp:$serverPort\n${e.localizedMessage}"))
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
import androidx.compose.foundation.clickable
EOF
