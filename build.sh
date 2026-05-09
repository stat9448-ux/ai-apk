@Dao interface ChatDao {
    @Query("SELECT * FROM chats") fun getChats(): Flow<List<Chat>>
    @Insert suspend fun insertChat(chat: Chat): Long
    @Query("SELECT * FROM messages WHERE chatId = :id") fun getMsgs(id: Long): Flow<List<Message>>
    @Insert suspend fun insertMsg(msg: Message)
}
@Database(entities = [Chat::class, Message::class], version = 1)
abstract class AppDB : RoomDatabase() { abstract fun dao(): ChatDao }

data class OllamaReq(val model: String = "qwen3:8b", val messages: List<OllamaMsg>, val stream: Boolean = true)
data class OllamaMsg(val role: String, val content: String)
interface Api { @POST("/api/chat") @Streaming fun chat(@Body req: OllamaReq): retrofit2.Call<okhttp3.ResponseBody> }

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val db = Room.databaseBuilder(this, AppDB::class.java, "ai.db").build()
        setContent {
            val nav = rememberNavController()
            NavHost(nav, "list") {
                composable("list") { 
                    val chats by db.dao().getChats().collectAsState(emptyList())
                    val scope = rememberCoroutineScope()
                    Scaffold(floatingActionButton = {
                        FloatingActionButton(onClick = { scope.launch { 
                            val nid = db.dao().insertChat(Chat(title = "New Chat"))
                            nav.navigate("chat/\$nid") 
                        }}) { Icon(Icons.Default.Add, null) }
                    }) { p ->
                        LazyColumn(Modifier.padding(p).fillMaxSize()) {
                            items(chats) { c -> Text(c.title, Modifier.clickable { nav.navigate("chat/\${c.id}") }.padding(16.dp)) }
                        }
                    }
                }
                composable("chat/{id}") { 
                    val cid = it.arguments?.getString("id")?.toLong() ?: 0L
                    ChatScr(cid, db.dao()) 
                }
            }
        }
    }
}

@Composable
fun ChatScr(id: Long, dao: ChatDao) {
    val msgs by dao.getMsgs(id).collectAsState(emptyList())
    var stream by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    Column {
        LazyColumn(Modifier.weight(1f)) {
            items(msgs) { Text("\${it.role}: \${it.content}") }
            if(stream.isNotEmpty()) item { Text("AI: \$stream") }
        }
        Button(onClick = { scope.launch {
            dao.insertMsg(Message(chatId = id, role = "user", content = "Hello"))
            // Тут будет логика запроса
        } }) { Text("Send Hello") }
    }
}
EOF
