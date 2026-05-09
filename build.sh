#!/bin/bash
# ДАННЫЕ ТВОЕГО СЕРВЕРА
TARGET_IP="192.168.0.207"
MODEL_NAME="llama3"

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

# 3. Модуль (Версия 3.4)
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
        versionCode = 14
        versionName = "3.4"
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
    <application android:label="Ollama AI" android:usesCleartextTraffic="true" android:theme="@android:style/Theme.DeviceDefault.NoActionBar">
        <activity android:name=".MainActivity" android:exported="true" android:windowSoftInputMode="adjustResize">
            <intent-filter><action android:name="android.intent.action.MAIN" /><category android:name="android.intent.category.LAUNCHER" /></intent-filter>
        </activity>
    </application>
</manifest>
EOF

# 5. КОД ПРИЛОЖЕНИЯ
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
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import retrofit2.http.*

const val ADDR = "REPLACE_IP"
const val MOD = "REPLACE_MODEL"
@androidx.room.Entity(tableName = "chat_table")
data class ChatEntry(
    @androidx.room.PrimaryKey(autoGenerate = true) val id: Int = 0,
    @androidx.room.ColumnInfo(name = "user_side") val isUser: Boolean,
    @androidx.room.ColumnInfo(name = "content") val text: String
)

@androidx.room.Dao
interface ChatDao {
    @androidx.room.Query("SELECT * FROM chat_table ORDER BY id ASC")
    fun observeAll(): Flow<List<ChatEntry>>
    @androidx.room.Insert
    suspend fun addMessage(entry: ChatEntry)
    @androidx.room.Query("DELETE FROM chat_table")
    suspend fun clearAll()
}

@androidx.room.Database(entities = [ChatEntry::class], version = 7, exportSchema = false)
abstract class AppDb : androidx.room.RoomDatabase() {
    abstract fun chatDao(): ChatDao
}

data class OllamaReq(val model: String, val prompt: String, val stream: Boolean = false)
data class OllamaRes(val response: String)
interface OllamaService { @POST("api/generate") suspend fun generate(@Body r: OllamaReq): OllamaRes }

class MainActivity : ComponentActivity() {
    @OptIn(ExperimentalMaterial3Api::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        val database = androidx.room.Room.databaseBuilder(
            applicationContext, AppDb::class.java, "ollama_v7_db"
        ).fallbackToDestructiveMigration().build()
        
        val retrofit = Retrofit.Builder()
            .baseUrl("http://$ADDR:11434/")
            .addConverterFactory(GsonConverterFactory.create())
            .build().create(OllamaService::class.java)

        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                val chatData by database.chatDao().observeAll().collectAsState(initial = emptyList())
                var inputTxt by remember { mutableStateOf("") }
                var isWait by remember { mutableStateOf(false) }
                val scope = rememberCoroutineScope()
                val scroll = rememberLazyListState()

                LaunchedEffect(chatData.size) { if(chatData.isNotEmpty()) scroll.animateScrollToItem(chatData.size - 1) }

                Scaffold(
                    topBar = {
                        TopAppBar(
                            title = { Column {
                                Text("Ollama Chat", style = MaterialTheme.typography.titleMedium)
                                Text(ADDR, style = MaterialTheme.typography.labelSmall, color = Color.Cyan)
                            }},
                            actions = {
                                TextButton(onClick = { scope.launch { database.chatDao().clearAll() } }) {
                                    Icon(Icons.Default.Refresh, null, tint = Color.Cyan)
                                    Text(" Новый чат", color = Color.Cyan)
                                }
                            }
                        )
                    }
                ) { p ->
                    Column(Modifier.padding(p).fillMaxSize().background(Color(0xFF121212))) {
                        LazyColumn(state = scroll, modifier = Modifier.weight(1f).padding(horizontal = 12.dp)) {
                            items(chatData) { m ->
                                Box(Modifier.fillMaxWidth().padding(vertical = 4.dp), 
                                    contentAlignment = if(m.isUser) Alignment.CenterEnd else Alignment.CenterStart) {
                                    Text(m.text, Modifier.clip(RoundedCornerShape(12.dp))
                                        .background(if(m.isUser) Color(0xFF004D40) else Color(0xFF2C2C2C)).padding(12.dp), color = Color.White)
                                }
                            }
                        }
                        if(isWait) LinearProgressIndicator(Modifier.fillMaxWidth(), color = Color.Cyan)
Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            TextField(
                                value = inputTxt, onValueChange = {inputTxt = it}, 
                                modifier = Modifier.weight(1f), 
                                shape = RoundedCornerShape(24.dp),
                                colors = TextFieldDefaults.colors(focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent)
                            )
                            Spacer(Modifier.width(8.dp))
                            FloatingActionButton(
                                onClick = {
                                    if(inputTxt.isBlank() || isWait) return@FloatingActionButton
                                    val t = inputTxt; inputTxt = ""; isWait = true
                                    scope.launch {
                                        database.chatDao().addMessage(ChatEntry(isUser = true, text = t))
                                        try {
                                            val r = retrofit.generate(OllamaReq(MOD, t))
                                            database.chatDao().addMessage(ChatEntry(isUser = false, text = r.response))
                                        } catch(e: Exception) {
                                            database.chatDao().addMessage(ChatEntry(isUser = false, text = "Error: ${e.message}"))
                                        } finally { isWait = false }
                                    }
                                },
                                containerColor = Color(0xFF009688)
                            ) { Icon(Icons.Default.Send, null, tint = Color.White) }
                        }
                    }
                }
            }
        }
    }
}
EOF

# Подстановка
sed -i "s/REPLACE_IP/$TARGET_IP/" app/src/main/java/com/localai/chat/MainActivity.kt
sed -i "s/REPLACE_MODEL/$MODEL_NAME/" app/src/main/java/com/localai/chat/MainActivity.kt
