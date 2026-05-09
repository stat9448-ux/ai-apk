#!/bin/bash
# ДАННЫЕ ТВОЕГО СЕРВЕРА
TARGET_IP="193.32.189.220"
MODEL_NAME="llama3"

# Создаем структуру
mkdir -p app/src/main/java/com/localai/chat
mkdir -p app/src/main/res/values

# Конфигурация Gradle
cat <<'EOF' > gradle.properties
org.gradle.jvmargs=-Xmx3g
android.useAndroidX=true
android.enableJetifier=true
EOF

# ИСПРАВЛЕННЫЙ settings.gradle.kts (добавили поиск плагинов)
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

cat <<'EOF' > build.gradle.kts
plugins {
    id("com.android.application") version "8.3.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.23" apply false
    id("com.google.devtools.ksp") version "1.9.23-1.0.19" apply false
}
EOF

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
        versionCode = 6
        versionName = "2.6"
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

cat <<'EOF' > app/src/main/res/values/strings.xml
<resources><string name="app_name">Ollama Admin</string></resources>
EOF

cat <<'EOF' > app/src/main/AndroidManifest.xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <application android:label="Ollama Admin" android:usesCleartextTraffic="true" android:theme="@android:style/Theme.DeviceDefault.NoActionBar">
        <activity android:name=".MainActivity" android:exported="true" android:windowSoftInputMode="adjustResize">
            <intent-filter><action android:name="android.intent.action.MAIN" /><category android:name="android.intent.category.LAUNCHER" /></intent-filter>
        </activity>
    </application>
</manifest>
EOF

cat <<EOF > app/src/main/java/com/localai/chat/MainActivity.kt
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
@Entity data class Msg(@PrimaryKey(autoGenerate = true) val id: Int = 0, val isU: Boolean, val t: String)
@Dao interface ChatDao {
    @Query("SELECT * FROM Msg") fun get(): Flow<List<Msg>>
    @Insert suspend fun add(m: Msg)
    @Query("DELETE FROM Msg") suspend fun clear()
}
@Database(entities = [Msg::class], version = 1)
abstract class DB : RoomDatabase() { abstract fun dao(): MsgDao }

data class Req(val model: String = "$MODEL_NAME", val prompt: String, val stream: Boolean = false)
data class Res(val response: String)
interface Api { @POST("/api/generate") suspend fun ask(@Body r: Req): Res }

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val db = Room.databaseBuilder(this, DB::class.java, "ai_final_v2.db").build()
        val api = Retrofit.Builder()
            .baseUrl("http://$TARGET_IP:11434")
            .addConverterFactory(GsonConverterFactory.create())
            .build().create(Api::class.java)

        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                val msgs by db.dao().get().collectAsState(emptyList())
                var txt by remember { mutableStateOf("") }
                var loading by remember { mutableStateOf(false) }
                val scope = rememberCoroutineScope()
                val listState = rememberLazyListState()

                LaunchedEffect(msgs.size) { if(msgs.isNotEmpty()) listState.animateScrollToItem(msgs.size - 1) }

                Scaffold(
                    topBar = {
                        CenterAlignedTopAppBar(
                            title = { Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Text("AI Server Console", style = MaterialTheme.typography.titleMedium)
                                Text("$TARGET_IP", style = MaterialTheme.typography.labelSmall, color = Color.LightGray)
                            }},
                            actions = { IconButton(onClick = { scope.launch { db.dao().clear() } }) { Icon(Icons.Default.DeleteSweep, null) } }
                        )
                    }
                ) { p ->
                    Column(Modifier.padding(p).fillMaxSize().background(Color(0xFF1A1A1A))) {
                        LazyColumn(state = listState, modifier = Modifier.weight(1f).padding(horizontal = 12.dp)) {
                            items(msgs) { m ->
                                Box(Modifier.fillMaxWidth().padding(vertical = 6.dp), contentAlignment = if(m.isU) Alignment.CenterEnd else Alignment.CenterStart) {
                                    Text(m.t, Modifier.clip(RoundedCornerShape(16.dp))
                                        .background(if(m.isU) Color(0xFF4A4A4A) else Color(0xFF2D2D2D)).padding(14.dp), color = Color.White)
                                }
                            }
                        }
                        if(loading) LinearProgressIndicator(Modifier.fillMaxWidth(), color = Color.Cyan)
                        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            TextField(
                                value = txt, onValueChange = {txt = it}, 
                                modifier = Modifier.weight(1f), 
                                placeholder = { Text("Введите запрос...") },
                                shape = RoundedCornerShape(28.dp),
                                colors = TextFieldDefaults.colors(focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent)
                            )
                            Spacer(Modifier.width(8.dp))
                            FloatingActionButton(
                                onClick = {
if(txt.isBlank() || loading) return@FloatingActionButton
                                    val uT = txt; txt = ""; loading = true
                                    scope.launch {
                                        db.dao().add(Msg(isU = true, t = uT))
                                        try {
                                            val res = api.ask(Req(prompt = uT))
                                            db.dao().add(Msg(isU = false, t = res.response))
                                        } catch(e: Exception) {
                                            db.dao().add(Msg(isU = false, t = "Ошибка сети: \${e.localizedMessage}"))
                                        } finally { loading = false }
                                    }
                                },
                                containerColor = Color(0xFF00ADB5),
                                shape = RoundedCornerShape(50)
                            ) { Icon(Icons.Default.Send, null, tint = Color.White) }
                        }
                    }
                }
            }
        }
    }
}
EOF
