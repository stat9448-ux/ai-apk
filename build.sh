# 1. Создаем структуру проекта
mkdir -p app/src/main/java/com/localai/chat/data
mkdir -p app/src/main/java/com/localai/chat/network
mkdir -p app/src/main/java/com/localai/chat/repository
mkdir -p app/src/main/res/values

# 2. Создаем файлы конфигурации (Gradle)
cat <<EOF > settings.gradle.kts
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { 
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() } 
}
rootProject.name = "Local AI Chat"
include(":app")
EOF

cat <<EOF > build.gradle.kts
plugins {
    id("com.android.application") version "8.2.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
    id("kotlin-kapt") version "1.9.22" apply false
}
EOF

cat <<EOF > app/build.gradle.kts
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("kotlin-kapt")
}

android {
    namespace = "com.localai.chat"
    compileSdk = 34
    defaultConfig {
        applicationId = "com.localai.chat"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }
    buildFeatures { compose = true }
    composeOptions { kotlinCompilerExtensionVersion = "1.5.1" }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.activity:activity-compose:1.8.2")
    implementation(platform("androidx.compose:compose-bom:2023.10.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.navigation:navigation-compose:2.7.7")
    implementation("androidx.room:room-runtime:2.6.1")
    implementation("androidx.room:room-ktx:2.6.1")
    kapt("androidx.room:room-compiler:2.6.1")
    implementation("com.squareup.retrofit2:retrofit:2.9.0")
    implementation("com.squareup.retrofit2:converter-gson:2.9.0")
    implementation("io.coil-kt:coil-compose:2.5.0")
}
EOF

# 3. Манифест
cat <<EOF > app/src/main/AndroidManifest.xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <application 
        android:label="Local AI Chat" 
        android:theme="@android:style/Theme.Material.NoActionBar"
        android:usesCleartextTraffic="true">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF

# 4. ВЕСЬ КОД ПРИЛОЖЕНИЯ (ОДНИМ ФАЙЛОМ)
cat <<EOF > app/src/main/java/com/localai/chat/MainActivity.kt
package com.localai.chat

import android.os.Bundle
import android.content.Context
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.navigation.compose.*
import androidx.room.*
import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import retrofit2.http.*
import okhttp3.OkHttpClient
// --- DATA LAYER ---
@Entity data class Chat(@PrimaryKey(autoGenerate = true) val id: Long = 0, val title: String)
@Entity data class Message(@PrimaryKey(autoGenerate = true) val id: Long = 0, val chatId: Long, val role: String, val content: String)
@Dao interface ChatDao {
    @Query("SELECT * FROM chats") fun getChats(): Flow<List<Chat>>
    @Insert suspend fun insertChat(chat: Chat): Long
    @Query("SELECT * FROM messages WHERE chatId = :id") fun getMsgs(id: Long): Flow<List<Message>>
    @Insert suspend fun insertMsg(msg: Message)
}
@Database(entities = [Chat::class, Message::class], version = 1)
abstract class AppDB : RoomDatabase() { abstract fun dao(): ChatDao }

// --- NETWORK ---
data class OllamaReq(val model: String = "qwen3:8b", val messages: List<OllamaMsg>, val stream: Boolean = true)
data class OllamaMsg(val role: String, val content: String)
data class OllamaRes(@SerializedName("message") val msg: OllamaMsg?, @SerializedName("response") val resp: String?, val done: Boolean)
interface Api { @POST("/api/chat") @Streaming fun chat(@Body req: OllamaReq): retrofit2.Call<okhttp3.ResponseBody> }

// --- UI & LOGIC ---
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val db = Room.databaseBuilder(this, AppDB::class.java, "ai.db").build()
        val prefs = getSharedPreferences("set", MODE_PRIVATE)
        
        setContent {
            val nav = rememberNavController()
            NavHost(nav, "list") {
                composable("list") { ChatList(nav, db.dao()) }
                composable("chat/{id}") { ChatScr(it.arguments?.getString("id")?.toLong()!!, db.dao(), prefs) }
            }
        }
    }
}

@Composable
fun ChatList(nav: androidx.navigation.NavController, dao: ChatDao) {
    val chats by dao.getChats().collectAsState(emptyList())
    val scope = rememberCoroutineScope()
    Scaffold(floatingActionButton = {
        FloatingActionButton(onClick = { scope.launch { 
            val id = dao.insertChat(Chat(title = "Новый чат"))
            nav.navigate("chat/\$id") 
        }}) { Icon(Icons.Default.Add, null) }
    }) { p ->
        LazyColumn(Modifier.padding(p).fillMaxSize().background(Color(0xFF121212))) {
            items(chats) { Text(it.title, Modifier.fillMaxWidth().padding(16.dp).background(Color(0xFF1E1E1E)).clickable { nav.navigate("chat/\${it.id}") }, color = Color.White) }
        }
    }
}

@Composable
fun ChatScr(id: Long, dao: ChatDao, prefs: android.content.SharedPreferences) {
    val msgs by dao.getMsgs(id).collectAsState(emptyList())
    var txt by remember { mutableStateOf("") }
    var stream by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()

    Column(Modifier.fillMaxSize().background(Color(0xFF121212))) {
        LazyColumn(Modifier.weight(1f)) {
            items(msgs) { Text("\${it.role}: \${it.content}", Modifier.padding(8.dp), color = Color.White) }
            if(stream.isNotEmpty()) item { Text("AI: \$stream", color = Color.Cyan) }
        }
        Row {
            TextField(txt, {txt = it}, Modifier.weight(1f))
            Button(onClick = {
                val userTxt = txt; txt = ""; scope.launch(Dispatchers.IO) {
                    dao.insertMsg(Message(chatId = id, role = "user", content = userTxt))
                    val api = Retrofit.Builder().baseUrl(prefs.getString("ip", "http://192.168.1.100:11434")!!).addConverterFactory(GsonConverterFactory.create()).build().create(Api::class.java)
                    val res = api.chat(OllamaReq(messages = listOf(OllamaMsg("user", userTxt)))).execute()
                    var full = ""
                    res.body()?.byteStream()?.bufferedReader()?.forEachLine { line ->
                        val part = Gson().fromJson(line, OllamaRes::class.java)
part.msg?.content?.let { full += it; stream = full }
                    }
                    dao.insertMsg(Message(chatId = id, role = "assistant", content = full))
                    stream = ""
                }
            }) { Text("Go") }
        }
    }
}
EOF

echo
