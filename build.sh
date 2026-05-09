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

/* ---------------- DB ---------------- */

@Entity(tableName = "messages")
data class Msg(
    @PrimaryKey(autoGenerate = true) val id: Int = 0,
    val isUser: Boolean,
    val text: String
)

@Dao
interface ChatDao {
    @Query("SELECT * FROM messages ORDER BY id ASC")
    fun getAll(): Flow<List<Msg>>

    @Insert
    suspend fun insert(m: Msg)

    @Query("DELETE FROM messages")
    suspend fun clear()
}

@Database(entities = [Msg::class], version = 1, exportSchema = false)
abstract class AppDb : RoomDatabase() {
    abstract fun dao(): ChatDao
}

/* ---------------- API (FIXED) ---------------- */

data class Message(
    val role: String,
    val content: String
)

data class ChatReq(
    val model: String,
    val messages: List<Message>
)

data class ChatRes(
    val message: Message
)

interface OllamaApi {
    @POST("api/chat")
    suspend fun chat(@Body req: ChatReq): ChatRes
}

/* ---------------- UI ---------------- */

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val db = Room.databaseBuilder(
            applicationContext,
            AppDb::class.java,
            "chat_db"
        ).fallbackToDestructiveMigration().build()

        val prefs = getSharedPreferences("cfg", Context.MODE_PRIVATE)

        setContent {

            MaterialTheme(colorScheme = darkColorScheme()) {

                var ip by remember { mutableStateOf(prefs.getString("ip", "192.168.0.207")!!) }
                var port by remember { mutableStateOf(prefs.getString("port", "11434")!!) }

                val msgs by db.dao().getAll().collectAsState(initial = emptyList())
                val scope = rememberCoroutineScope()

                var input by remember { mutableStateOf("") }
                var loading by remember { mutableStateOf(false) }

                val api = remember(ip, port) {
                    Retrofit.Builder()
                        .baseUrl("http://$ip:$port/")
                        .addConverterFactory(GsonConverterFactory.create())
                        .build()
                        .create(OllamaApi::class.java)
                }

                Scaffold(
                    topBar = {
                        TopAppBar(
                            title = { Text("Local AI Chat") },
                            actions = {
                                IconButton(onClick = { scope.launch { db.dao().clear() } }) {
                                    Icon(Icons.Default.Delete, null)
                                }
                            }
                        )
                    }
                ) { padding ->

                    Column(
                        Modifier.padding(padding).fillMaxSize()
                    ) {

                        LazyColumn(
                            modifier = Modifier.weight(1f).padding(8.dp)
                        ) {
items(msgs) { m ->
                                Box(
                                    Modifier.fillMaxWidth(),
                                    contentAlignment = if (m.isUser)
                                        Alignment.CenterEnd else Alignment.CenterStart
                                ) {
                                    Text(
                                        m.text,
                                        Modifier
                                            .padding(4.dp)
                                            .clip(RoundedCornerShape(12.dp))
                                            .background(
                                                if (m.isUser) Color(0xFF1565C0)
                                                else Color(0xFF333333)
                                            )
                                            .padding(10.dp),
                                        color = Color.White
                                    )
                                }
                            }
                        }

                        Row(Modifier.padding(8.dp)) {

                            TextField(
                                value = input,
                                onValueChange = { input = it },
                                modifier = Modifier.weight(1f),
                                placeholder = { Text("Сообщение...") }
                            )

                            Spacer(Modifier.width(8.dp))

                            Button(onClick = {
                                if (input.isBlank() || loading) return@Button

                                val text = input
                                input = ""
                                loading = true

                                scope.launch {

                                    db.dao().insert(Msg(isUser = true, text = text))

                                    try {
                                        val response = api.chat(
                                            ChatReq(
                                                model = "qwen3:8b",
                                                messages = listOf(
                                                    Message("user", text)
                                                )
                                            )
                                        )

                                        db.dao().insert(
                                            Msg(false, response.message.content)
                                        )

                                    } catch (e: Exception) {
                                        db.dao().insert(
                                            Msg(false, "Ошибка: ${e.message}")
                                        )
                                    }

                                    loading = false
                                }

                            }) {
                                Icon(Icons.Default.Send, null)
                            }
                        }
                    }
                }
            }
        }
    }
}
