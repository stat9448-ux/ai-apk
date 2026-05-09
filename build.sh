#!/bin/bash
# ДАННЫЕ ТВОЕГО СЕРВЕРА
TARGET_IP="193.32.189.220"
MODEL_NAME="llama3"

# 1. Структура
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

# 3. Модуль (Упрощенные зависимости для стабильности)
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
        versionCode = 12
        versionName = "3.2"
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
    
    // Room - Самая стабильная связка
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
    <application android:label="Ollama Mobile" android:usesCleartextTraffic="true" android:theme="@android:style/Theme.DeviceDefault.NoActionBar">
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
import androidx.room.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import retrofit2.http.*

const val ADDR = "REPLACE_IP"
const val MOD = "REPLACE_MODEL"
@Entity(tableName = "chat")
data class Message(
    @PrimaryKey(autoGenerate = true) val id: Int = 0,
    @ColumnInfo(name = "u") val isU: Boolean,
    @ColumnInfo(name = "t") val txt: String
)

@Dao
interface ChatDao {
    @Query("SELECT * FROM chat ORDER BY id ASC")
    fun get(): Flow<List<Message>>
    @Insert
    suspend fun add(m: Message)
    @Query("DELETE FROM chat")
    suspend fun del()
}

@Database(entities = [Message::class], version = 5, exportSchema = false)
abstract class ChatDatabase : RoomDatabase() { abstract fun dao(): ChatDao }

data class Req(val model: String, val prompt: String, val stream: Boolean = false)
data class Res(val response: String)
interface Api { @POST("api/generate") suspend fun ask(@Body r: Req): Res }

class MainActivity : ComponentActivity() {
    @OptIn(ExperimentalMaterial3Api::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        val db = Room.databaseBuilder(applicationContext, ChatDatabase::class.java, "ai_db_v5")
            .fallbackToDestructiveMigration().build()
        
        val api = Retrofit.Builder()
            .baseUrl("http://$ADDR:11434/")
            .addConverterFactory(GsonConverterFactory.create())
            .build().create(Api::class.java)

        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                val msgs by db.dao().get().collectAsState(initial = emptyList())
                var input by remember { mutableStateOf("") }
                var loading by remember { mutableStateOf(false) }
                val scope = rememberCoroutineScope()
                val listState = rememberLazyListState()

                LaunchedEffect(msgs.size) { if(msgs.isNotEmpty()) listState.animateScrollToItem(msgs.size - 1) }

                Scaffold(
                    topBar = {
                        TopAppBar(
                            title = { Column {
                                Text("Ollama Remote", style = MaterialTheme.typography.titleMedium)
                                Text(ADDR, style = MaterialTheme.typography.labelSmall, color = Color.Cyan)
                            }},
                            actions = {
                                TextButton(onClick = { scope.launch { db.dao().del() } }) {
                                    Icon(Icons.Default.Add, null, tint = Color.Cyan)
                                    Text(" Новый чат", color = Color.Cyan)
                                }
                            }
                        )
                    }
                ) { p ->
                    Column(Modifier.padding(p).fillMaxSize().background(Color(0xFF101010))) {
                        LazyColumn(state = listState, modifier = Modifier.weight(1f).padding(horizontal = 12.dp)) {
                            items(msgs) { m ->
                                Box(Modifier.fillMaxWidth().padding(vertical = 4.dp), contentAlignment = if(m.isU) Alignment.CenterEnd else Alignment.CenterStart) {
                                    Text(m.txt, Modifier.clip(RoundedCornerShape(12.dp))
                                        .background(if(m.isU) Color(0xFF006064) else Color(0xFF212121)).padding(12.dp), color = Color.White)
                                }
                            }
                        }
                        if(loading) LinearProgressIndicator(Modifier.fillMaxWidth(), color = Color.Cyan)
                        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            TextField(
                                value = input, onValueChange = {input = it}, 
                                modifier = Modifier.weight(1f), 
                                shape = RoundedCornerShape(24.dp),
colors = TextFieldDefaults.colors(focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent)
                            )
                            Spacer(Modifier.width(8.dp))
                            FloatingActionButton(
                                onClick = {
                                    if(input.isBlank() || loading) return@FloatingActionButton
                                    val t = input; input = ""; loading = true
                                    scope.launch {
                                        db.dao().add(Message(isU = true, txt = t))
                                        try {
                                            val r = api.ask(Req(MOD, t))
                                            db.dao().add(Message(isU = false, txt = r.response))
                                        } catch(e: Exception) {
                                            db.dao().add(Message(isU = false, txt = "Ошибка: ${e.localizedMessage}"))
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

# Подстановка
sed -i "s/REPLACE_IP/$TARGET_IP/" app/src/main/java/com/localai/chat/MainActivity.kt
sed -i "s/REPLACE_MODEL/$MODEL_NAME/" app/src/main/java/com/localai/chat/MainActivity.kt
