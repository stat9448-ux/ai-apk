[2026-05-09 5:31 PM] Данчик КВН: #!/bin/bash
# 1. Структура проекта
mkdir -p app/src/main/java/com/localai/chat
mkdir -p app/src/main/res/values
mkdir -p gradle/wrapper

# 2. Gradle Настройки
cat <<'EOF' > gradle/wrapper/gradle-wrapper.properties
distributionBase=PROJECT
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.7-bin.zip
networkTimeout=10000
validateDistributionUrl=true
zipStoreBase=PROJECT
zipStorePath=wrapper/dists
EOF

cat <<'EOF' > gradle.properties
org.gradle.jvmargs=-Xmx2g
android.useAndroidX=true
android.enableJetifier=true
EOF

cat <<'EOF' > settings.gradle.kts
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "OllamaMaster"
include(":app")
EOF

cat <<'EOF' > build.gradle.kts
plugins {
    id("com.android.application") version "8.2.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
    id("com.google.devtools.ksp") version "1.9.22-1.0.17" apply false
}
EOF

# 3. Модуль (v5.1)
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
        versionCode = 31
        versionName = "5.1"
    }
    buildFeatures { compose = true }
    composeOptions { kotlinCompilerExtensionVersion = "1.5.10" }
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
    
    val roomVersion = "2.6.1"
    implementation("androidx.room:room-runtime:$roomVersion")
    implementation("androidx.room:room-ktx:$roomVersion")
    ksp("androidx.room:room-compiler:$roomVersion")
    
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

// --- ROOM DATA LAYER ---
@Entity(tableName = "messages")
data class ChatMsg(
    @PrimaryKey(autoGenerate = true) val id: Int = 0,
    val role: String,
    val content: String
)

@Dao
interface ChatDao {
    @Query("SELECT * FROM messages ORDER BY id ASC")
    fun getAll(): Flow<List<ChatMsg>>
    @Insert
    suspend fun insert(msg: ChatMsg)
    @Query("DELETE FROM messages")
    suspend fun clear()
}

@Database(entities = [ChatMsg::class], version = 51, exportSchema = false)
abstract class AppDb : RoomDatabase() {
    abstract fun dao(): ChatDao
}

// --- API LAYER ---
data class OllamaMsg(val role: String, val content: String)
data class OllamaReq(val model: String, val messages: List<OllamaMsg>, val stream: Boolean = false)
data class OllamaRes(val message: OllamaMsg)

interface OllamaApi {
    @POST("api/chat")
    suspend fun chat(@Body req: OllamaReq): OllamaRes
}

// --- UI LAYER ---
class MainActivity : ComponentActivity() {
    @OptIn(ExperimentalMaterial3Api::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        val db = Room.databaseBuilder(applicationContext, AppDb::class.java, "ollama_db_51")
            .fallbackToDestructiveMigration().build()
        val prefs = getSharedPreferences("settings", Context.MODE_PRIVATE)

        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                var ip by remember { mutableStateOf(prefs.getString("ip", "192.168.0.207") ?: "192.168.0.207") }
                var port by remember { mutableStateOf(prefs.getString("port", "11434") ?: "11434") }
                var model by remember { mutableStateOf(prefs.getString("model", "qwen2.5:3b") ?: "qwen2.5:3b") }
                var showSet by remember { mutableStateOf(false) }
                
                val msgs by db.dao().getAll().collectAsState(initial = emptyList())
                var input by remember { mutableStateOf("") }
                var loading by remember { mutableStateOf(false) }
                val scope = rememberCoroutineScope()
                val listState = rememberLazyListState()

                val api = remember(ip, port) {
                    try {
                        Retrofit.Builder()
                            .baseUrl("http://$ip:$port/")
                            .addConverterFactory(GsonConverterFactory.create())
                            .build().create(OllamaApi::class.java)
                    } catch (e: Exception) { null }
                }

                LaunchedEffect(msgs.size) { if(msgs.isNotEmpty()) listState.animateScrollToItem(msgs.size - 1) }

                Scaffold(
                    topBar = {
                        TopAppBar(
                            title = { 
                                Column {
                                    Text("Ollama v5.1", style = MaterialTheme.typography.titleMedium)
                                    Text("$model @ $ip:$port", style = MaterialTheme.typography.labelSmall, color = Color.Cyan)
                                }
                            },
                            actions = {
                                IconButton(onClick = { showSet = !showSet }) {
                                    Icon(Icons.Default.Settings, contentDescription = "Settings", tint = if (showSet) Color.Cyan else Color.Gray)
                                }
                                IconButton(onClick = { scope.launch { db.dao().clear() } }) {
                                    Icon(Icons.Default.DeleteSweep, contentDescription = "Clear Chat", tint = Color.Gray)
                                }
                            }
                        )
                    }
                ) { p ->
                    Column(Modifier.padding(p).fillMaxSize().background(Color(0xFF121212))) {
                        if (showSet) {
                            Card(Modifier.padding(8.dp), colors = CardDefaults.cardColors(containerColor = Color(0xFF1E1E1E))) {
                                Column(Modifier.padding(12.dp)) {
                                    Text("Настройки подключения", color = Color.White, style = MaterialTheme.typography.titleMedium)
                                    Spacer(Modifier.height(8.dp))
                                    OutlinedTextField(value = ip, onValueChange = { ip = it; prefs.edit().putString("ip", it).apply() }, label = { Text("IP адрес") }, modifier = Modifier.fillMaxWidth())
                                    OutlinedTextField(value = port, onValueChange = { port = it; prefs.edit().putString("port", it).apply() }, label = { Text("Порт") }, modifier = Modifier.fillMaxWidth())
                                    OutlinedTextField(value = model, onValueChange = { model = it; prefs.edit().putString("model", it).apply() }, label = { Text("Модель") }, modifier = Modifier.fillMaxWidth())
                                    Button(onClick = { showSet = false }, Modifier.align(Alignment.End).padding(top = 8.dp)) { Text("Сохранить") }
                                }
                            }
                        }

                        LazyColumn(state = listState, modifier = Modifier.weight(1f).padding(horizontal = 12.dp)) {
                            items(msgs) { m ->
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
                                value = input, onValueChange = {input = it}, 
                                modifier = Modifier.weight(1f), 
                                shape = RoundedCornerShape(24.dp),
                                placeholder = { Text("Ask Ollama...") },
                                colors = TextFieldDefaults.colors(focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent)
                            )
                            Spacer(Modifier.width(8.dp))
                            FloatingActionButton(
                                onClick = {
                                    if(input.isBlank() || loading || api == null) return@FloatingActionButton
                                    val t = input; input = ""; loading = true
                                    scope.launch {
                                        db.dao().insert(ChatMsg(role = "user", content = t))
                                        try {
                                            val hist = msgs.map { OllamaMsg(it.role, it.content) } + OllamaMsg("user", t)
                                            val res = api.chat(OllamaReq(model, hist))
                                            db.dao().insert(ChatMsg(role = "assistant", content = res.message.content))
                                        } catch(e: Exception) {
                                            db.dao().insert(ChatMsg(role = "assistant", content = "Error: ${e.localizedMessage}"))
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
