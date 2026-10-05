# Chord & Lyrics App — Architecture, Schema & Implementation

Stack: **Android (Kotlin, Fragments + RecyclerView, ViewBinding)** frontend, **Laravel REST API + MySQL** backend.

---

## 1. Tech Stack & Architecture

### Backend (Laravel)
| Concern | Choice |
|---|---|
| Auth | Laravel Sanctum (token-based, mobile-friendly) |
| DB | MySQL 8 |
| External metadata | Spotify Web API (Client Credentials flow for search/track lookup) |
| Storage | S3/Spaces for any self-hosted chord-sheet assets |
| Queue | Laravel Queue (sync Spotify metadata in background jobs) |

### Android
| Concern | Library |
|---|---|
| Networking | Retrofit2 + OkHttp (logging + auth interceptor) |
| JSON | Moshi (or Gson) |
| Images | Coil (lighter than Glide, coroutine-native) |
| Local DB / offline cache | Room |
| Background sync | WorkManager |
| Audio playback | ExoPlayer (Media3) — gives you waveform-friendly PCM access and background playback |
| DI | Hilt |
| Async | Kotlin Coroutines + Flow |
| Chord diagrams | Custom `View` drawing on `Canvas` (fastest, no SVG parsing overhead, easy to theme) |

### High-level flow

```
[Android App]
   ├─ Fragments (DashboardFragment, PlayerFragment) + RecyclerView adapters
   ├─ ViewModel (per screen) — exposes StateFlow
   ├─ Repository layer — decides Room cache vs Retrofit network (offline-first)
   ├─ Room DB — cached songs, chord/lyric lines, user prefs, favorites
   └─ WorkManager — syncs favorites/transpose prefs to backend when connectivity returns

[Laravel API]
   ├─ AuthController (Sanctum) — register/login/me
   ├─ SongController — CRUD + search, proxies/caches Spotify metadata
   ├─ ChordSheetController — serves lyrics+chord raw text & timed lines
   ├─ FavoriteController — like/unlike
   └─ UserPreferenceController — persists per-user transpose offset per song

[Spotify Web API] ← fetched server-side, cached in `songs` table, refreshed via queued job
```

**Why offline-first matters here:** the chord sheet (raw lyrics+chord text) is small text data — cheap to cache fully in Room. Audio itself can either stream via ExoPlayer with its own disk cache, or you let users explicitly "download" a track (store the preview/audio URL locally + mark `is_downloaded=1`).

---

## 2. Database Schema (Laravel Migrations)

```php
// database/migrations/xxxx_xx_xx_create_users_table.php
Schema::create('users', function (Blueprint $table) {
    $table->id();
    $table->string('name');
    $table->string('email')->unique();
    $table->string('password');
    $table->string('avatar_url')->nullable();
    $table->timestamp('email_verified_at')->nullable();
    $table->rememberToken();
    $table->timestamps();
});
```

```php
// database/migrations/xxxx_xx_xx_create_songs_table.php
Schema::create('songs', function (Blueprint $table) {
    $table->id();
    $table->string('spotify_track_id')->unique()->nullable(); // null if not from Spotify
    $table->string('title');
    $table->string('artist');
    $table->string('album_art_url')->nullable();
    $table->unsignedInteger('duration_ms')->default(0);
    $table->string('preview_url')->nullable();      // audio preview / stream URL
    $table->string('original_key', 8)->nullable();   // e.g. "C", "Bm"
    $table->timestamps();

    $table->index(['title', 'artist']);
});
```

```php
// database/migrations/xxxx_xx_xx_create_song_lines_table.php
// Timed, chord-annotated lyric lines — this is what drives sync + the chord strip.
Schema::create('song_lines', function (Blueprint $table) {
    $table->id();
    $table->foreignId('song_id')->constrained()->cascadeOnDelete();
    $table->unsignedInteger('line_index');           // ordering
    $table->unsignedInteger('start_time_ms');         // for auto-scroll sync
    $table->text('raw_line');                          // e.g. "Baby, I [Bm]love your [Em]wants"
    $table->timestamps();

    $table->index(['song_id', 'line_index']);
});
```

```php
// database/migrations/xxxx_xx_xx_create_user_favorites_table.php
Schema::create('user_favorites', function (Blueprint $table) {
    $table->id();
    $table->foreignId('user_id')->constrained()->cascadeOnDelete();
    $table->foreignId('song_id')->constrained()->cascadeOnDelete();
    $table->timestamps();

    $table->unique(['user_id', 'song_id']);
});
```

```php
// database/migrations/xxxx_xx_xx_create_user_song_preferences_table.php
// Per-user, per-song transpose offset (and any other saved playback prefs).
Schema::create('user_song_preferences', function (Blueprint $table) {
    $table->id();
    $table->foreignId('user_id')->constrained()->cascadeOnDelete();
    $table->foreignId('song_id')->constrained()->cascadeOnDelete();
    $table->integer('transpose_offset')->default(0);   // semitones, -11..+11
    $table->boolean('is_downloaded')->default(false);
    $table->timestamps();

    $table->unique(['user_id', 'song_id']);
});
```

Eloquent relationships (sketch):

```php
class Song extends Model {
    public function lines() { return $this->hasMany(SongLine::class)->orderBy('line_index'); }
    public function favoritedBy() { return $this->belongsToMany(User::class, 'user_favorites'); }
}

class User extends Model {
    public function favorites() { return $this->belongsToMany(Song::class, 'user_favorites'); }
    public function preferences() { return $this->hasMany(UserSongPreference::class); }
}
```

Key endpoint for the Player screen (`GET /api/songs/{id}`):

```php
Route::get('/songs/{song}', function (Song $song) {
    return [
        'id' => $song->id,
        'title' => $song->title,
        'artist' => $song->artist,
        'album_art_url' => $song->album_art_url,
        'duration_ms' => $song->duration_ms,
        'preview_url' => $song->preview_url,
        'original_key' => $song->original_key,
        'lines' => $song->lines->map(fn ($l) => [
            'start_time_ms' => $l->start_time_ms,
            'raw_line' => $l->raw_line, // "[Bm]love your [Em]wants" — client parses & transposes
        ]),
    ];
});
```

Note the API always returns the **original, untransposed** raw line. Transposition is purely a client-side render step (see §4) — this keeps the payload cacheable and independent of per-user state.

---

## 3. Android UI

### 3a. Floating glassmorphism bottom nav

`res/layout/layout_bottom_nav.xml` — a rounded `CardView`/`ConstraintLayout` overlaying the screen bottom, semi-transparent blurred background, three icons, active one gets a glowing purple pill.

```xml
<!-- res/layout/layout_bottom_nav.xml -->
<androidx.cardview.widget.CardView
    android:layout_width="wrap_content"
    android:layout_height="64dp"
    android:layout_gravity="bottom|center_horizontal"
    android:layout_marginBottom="24dp"
    app:cardCornerRadius="32dp"
    app:cardElevation="12dp"
    app:cardBackgroundColor="#1AFFFFFF"> <!-- translucent white over blurred bg for glass look -->

    <LinearLayout
        android:layout_width="wrap_content"
        android:layout_height="match_parent"
        android:orientation="horizontal"
        android:gravity="center_vertical"
        android:paddingHorizontal="16dp">

        <FrameLayout
            android:id="@+id/navHome"
            android:layout_width="48dp"
            android:layout_height="48dp"
            android:background="@drawable/bg_nav_active_glow"> <!-- purple radial glow, toggled -->
            <ImageView
                android:layout_width="24dp"
                android:layout_height="24dp"
                android:layout_gravity="center"
                android:src="@drawable/ic_home"
                app:tint="@color/white" />
        </FrameLayout>

        <FrameLayout
            android:id="@+id/navMusic"
            android:layout_width="48dp"
            android:layout_height="48dp"
            android:layout_marginStart="12dp">
            <ImageView
                android:layout_width="24dp"
                android:layout_height="24dp"
                android:layout_gravity="center"
                android:src="@drawable/ic_music_note"
                app:tint="@color/nav_icon_inactive" />
        </FrameLayout>

        <FrameLayout
            android:id="@+id/navSettings"
            android:layout_width="48dp"
            android:layout_height="48dp"
            android:layout_marginStart="12dp">
            <ImageView
                android:layout_width="24dp"
                android:layout_height="24dp"
                android:layout_gravity="center"
                android:src="@drawable/ic_settings"
                app:tint="@color/nav_icon_inactive" />
        </FrameLayout>
    </LinearLayout>
</androidx.cardview.widget.CardView>
```

`res/drawable/bg_nav_active_glow.xml`:

```xml
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="oval">
    <gradient
        android:type="radial"
        android:gradientRadius="24dp"
        android:centerColor="#8B5CF6"
        android:endColor="#4C1D95" />
</shape>
```

For real glassmorphism blur behind the CardView, either render it over a `RenderEffect` blur (API 31+) on the content beneath, or fake it with a semi-transparent dark scrim — true backdrop blur on older APIs needs a library like `BlurView`.

Wire up tab switching in the hosting Activity:

```kotlin
class MainActivity : AppCompatActivity() {
    private lateinit var binding: ActivityMainBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.navHome.setOnClickListener { switchTab(Tab.HOME) }
        binding.navMusic.setOnClickListener { switchTab(Tab.LIBRARY) }
        binding.navSettings.setOnClickListener { switchTab(Tab.SETTINGS) }
    }

    private fun switchTab(tab: Tab) {
        val fragment = when (tab) {
            Tab.HOME -> DashboardFragment()
            Tab.LIBRARY -> LibraryFragment()
            Tab.SETTINGS -> SettingsFragment()
        }
        supportFragmentManager.commit {
            replace(R.id.fragmentContainer, fragment)
        }
        updateActiveGlow(tab)
    }
}
```

### 3b. Player screen — chord diagram strip

Chord diagrams are drawn on a custom `View` (not bitmaps), so re-theming/resizing is free and there's no asset bloat.

`ChordDiagramView.kt`:

```kotlin
data class ChordShape(
    val name: String,
    // 6 strings, low E to high E. -1 = muted, 0 = open, N = fret
    val frets: IntArray,
    // finger number per string, 0 = none/open
    val fingers: IntArray,
    val baseFret: Int = 1
)

class ChordDiagramView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null
) : View(context, attrs) {

    var shape: ChordShape? = null
        set(value) { field = value; invalidate() }

    private val stringPaint = Paint().apply { strokeWidth = 3f; color = Color.DKGRAY }
    private val fretPaint = Paint().apply { strokeWidth = 3f; color = Color.DKGRAY }
    private val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.BLACK; style = Paint.Style.FILL }
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE; textAlign = Paint.Align.CENTER; textSize = 24f
    }
    private val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.BLACK; textAlign = Paint.Align.CENTER; textSize = 40f; isFakeBoldText = true
    }

    private val frettsToShow = 4

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val s = shape ?: return
        val padding = 40f
        val gridW = width - padding * 2
        val gridH = height - padding * 2 - 60f // reserve top space for label
        val stringGap = gridW / 5
        val fretGap = gridH / frettsToShow
        val top = padding + 60f

        // chord name
        canvas.drawText(s.name, width / 2f, 50f, labelPaint)

        // 6 vertical strings
        for (i in 0..5) {
            val x = padding + i * stringGap
            canvas.drawLine(x, top, x, top + gridH, stringPaint)
        }
        // 5 horizontal frets
        for (i in 0..frettsToShow) {
            val y = top + i * fretGap
            canvas.drawLine(padding, y, padding + gridW, y, fretPaint)
        }

        // finger dots / open / muted markers
        for (stringIdx in 0..5) {
            val fret = s.frets[stringIdx]
            val x = padding + stringIdx * stringGap
            when {
                fret == -1 -> canvas.drawText("×", x, top - 15f, textPaint.apply { color = Color.DKGRAY })
                fret == 0 -> canvas.drawCircle(x, top - 20f, 10f, Paint(dotPaint).apply { style = Paint.Style.STROKE; strokeWidth = 3f })
                else -> {
                    val relativeFret = fret - s.baseFret + 1
                    val y = top + (relativeFret - 0.5f) * fretGap
                    canvas.drawCircle(x, y, 22f, dotPaint)
                    val finger = s.fingers.getOrElse(stringIdx) { 0 }
                    if (finger > 0) canvas.drawText(finger.toString(), x, y + 8f, textPaint)
                }
            }
        }
    }
}
```

### 3c. Fingering dictionary

```kotlin
object ChordDictionary {
    private val shapes = mapOf(
        "Em" to ChordShape("Em", frets = intArrayOf(0, 2, 2, 0, 0, 0), fingers = intArrayOf(0, 2, 1, 0, 0, 0)),
        "Bm" to ChordShape("Bm", frets = intArrayOf(-1, 2, 4, 4, 3, 2), fingers = intArrayOf(0, 1, 3, 4, 2, 1), baseFret = 2),
        "Am" to ChordShape("Am", frets = intArrayOf(-1, 0, 2, 2, 1, 0), fingers = intArrayOf(0, 0, 2, 3, 1, 0)),
        "C"  to ChordShape("C",  frets = intArrayOf(-1, 3, 2, 0, 1, 0), fingers = intArrayOf(0, 3, 2, 0, 1, 0)),
        "D"  to ChordShape("D",  frets = intArrayOf(-1, -1, 0, 2, 3, 2), fingers = intArrayOf(0, 0, 0, 1, 3, 2)),
        "G"  to ChordShape("G",  frets = intArrayOf(3, 2, 0, 0, 0, 3), fingers = intArrayOf(2, 1, 0, 0, 0, 3))
        // extend with the full 12-root × {maj,min,7,maj7,min7,sus2,sus4} matrix as needed
    )

    fun get(chordName: String): ChordShape? = shapes[chordName]
}
```

Bind the RecyclerView (`LinearLayoutManager(HORIZONTAL)`) with a simple adapter whose `onBindViewHolder` sets `chordDiagramView.shape = ChordDictionary.get(name)`.

### 3d. Lyrics sync + highlight

```kotlin
class LyricsAdapter(
    private val lines: List<ParsedLine>
) : RecyclerView.Adapter<LyricsAdapter.VH>() {

    var activeIndex = -1
        set(value) {
            val old = field
            field = value
            notifyItemChanged(old)
            notifyItemChanged(value)
        }

    inner class VH(val binding: ItemLyricLineBinding) : RecyclerView.ViewHolder(binding.root)

    override fun onBindViewHolder(holder: VH, position: Int) {
        val line = lines[position]
        holder.binding.tvLyric.text = line.plainText
        val isActive = position == activeIndex
        holder.binding.tvLyric.setTextColor(
            if (isActive) Color.parseColor("#8B5CF6") else Color.parseColor("#BBBBBB")
        )
        holder.binding.tvLyric.setTypeface(null, if (isActive) Typeface.BOLD else Typeface.NORMAL)
    }
    // onCreateViewHolder / getItemCount omitted for brevity
}
```

Driven from the player's position callback (ExoPlayer `Player.Listener.onPositionDiscontinuity` or a periodic handler):

```kotlin
player.addListener(object : Player.Listener {
    override fun onEvents(player: Player, events: Player.Events) {
        val pos = player.currentPosition
        val idx = lines.indexOfLast { it.startTimeMs <= pos }
        if (idx != adapter.activeIndex) {
            adapter.activeIndex = idx
            recyclerView.smoothScrollToPosition(idx)
        }
    }
})
```

---

## 4. Transpose Engine

Parses raw text like `"Baby, I [Bm]love your [Em]wants"` and shifts every bracketed chord by N semitones, leaving lyric text untouched. Handles slash chords (`G/B`) and simple qualities (`m`, `7`, `maj7`, `sus4`, etc.) by transposing only the root (and bass note if present).

```kotlin
object TransposeEngine {

    private val SHARP_SCALE = listOf("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")
    private val FLAT_SCALE  = listOf("C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B")

    // Matches a chord root (A-G, optional # or b) followed by any quality suffix,
    // optionally followed by a "/bassNote" slash chord.
    private val CHORD_REGEX = Regex("""^([A-G](?:#|b)?)([^/]*)(?:/([A-G](?:#|b)?))?$""")

    /**
     * Shifts a single chord symbol (e.g. "Bm", "G#7", "D/F#") by [semitones].
     * Preserves quality suffix and sharp/flat spelling style of the original root.
     */
    fun transposeChord(chord: String, semitones: Int): String {
        val match = CHORD_REGEX.find(chord.trim()) ?: return chord // not a recognizable chord, leave as-is
        val (root, quality, bass) = match.destructured

        val useFlats = root.endsWith("b")
        val newRoot = shiftNote(root, semitones, useFlats)
        val newBass = if (bass.isNotEmpty()) shiftNote(bass, semitones, useFlats) else null

        return buildString {
            append(newRoot)
            append(quality)
            if (newBass != null) { append("/"); append(newBass) }
        }
    }

    private fun shiftNote(note: String, semitones: Int, useFlats: Boolean): String {
        val scale = if (useFlats) FLAT_SCALE else SHARP_SCALE
        val altScale = if (useFlats) SHARP_SCALE else FLAT_SCALE
        val index = scale.indexOf(note).takeIf { it >= 0 } ?: altScale.indexOf(note)
        if (index < 0) return note // unknown note name, don't crash
        val newIndex = ((index + semitones) % 12 + 12) % 12
        return scale[newIndex]
    }

    /**
     * Transposes every [Chord] token inside a raw lyric line, e.g.
     * "Baby, I [Bm]love your [Em]wants" with semitones=2
     * -> "Baby, I [C#m]love your [F#m]wants"
     * Lyric text outside brackets is never touched.
     */
    fun transposeLine(rawLine: String, semitones: Int): String {
        if (semitones == 0) return rawLine
        val bracketRegex = Regex("""\[([^\]]+)]""")
        return bracketRegex.replace(rawLine) { m ->
            "[${transposeChord(m.groupValues[1], semitones)}]"
        }
    }

    /** Convenience: parse "[C]Hello [Am]World" into plain text + chord/position pairs for rendering. */
    data class ChordToken(val chord: String, val charIndex: Int)
    data class ParsedLine(val plainText: String, val chords: List<ChordToken>, val startTimeMs: Long = 0)

    fun parse(rawLine: String, semitones: Int = 0): ParsedLine {
        val bracketRegex = Regex("""\[([^\]]+)]""")
        val plain = StringBuilder()
        val tokens = mutableListOf<ChordToken>()
        var lastEnd = 0

        for (match in bracketRegex.findAll(rawLine)) {
            plain.append(rawLine, lastEnd, match.range.first)
            val chord = transposeChord(match.groupValues[1], semitones)
            tokens += ChordToken(chord, plain.length)
            lastEnd = match.range.last + 1
        }
        plain.append(rawLine, lastEnd, rawLine.length)

        return ParsedLine(plain.toString(), tokens)
    }
}
```

Wiring the +/- transpose buttons in the Player fragment:

```kotlin
class PlayerViewModel : ViewModel() {
    private val _transposeOffset = MutableStateFlow(0)
    val transposeOffset: StateFlow<Int> = _transposeOffset

    fun transposeUp() { _transposeOffset.value = (_transposeOffset.value + 1).coerceAtMost(11) }
    fun transposeDown() { _transposeOffset.value = (_transposeOffset.value - 1).coerceAtLeast(-11) }
}
```

```kotlin
binding.btnTransposeUp.setOnClickListener { viewModel.transposeUp() }
binding.btnTransposeDown.setOnClickListener { viewModel.transposeDown() }

viewModel.transposeOffset.onEach { offset ->
    val reparsed = rawLines.map { TransposeEngine.parse(it.rawLine, offset) }
    lyricsAdapter.submitList(reparsed)
    binding.tvTransposeValue.text = if (offset >= 0) "+$offset" else "$offset"
}.launchIn(lifecycleScope)
```

On save, `PATCH /api/user-preferences/{song_id}` persists `transpose_offset` for that user+song, and Room caches it locally so the offset survives offline restarts.

---

## 5. Offline-first sketch (Room)

```kotlin
@Entity(tableName = "cached_songs")
data class CachedSong(
    @PrimaryKey val id: Long,
    val title: String, val artist: String, val albumArtUrl: String?,
    val previewUrl: String?, val originalKey: String?, val isDownloaded: Boolean
)

@Entity(tableName = "cached_lines")
data class CachedLine(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val songId: Long, val lineIndex: Int, val startTimeMs: Long, val rawLine: String
)

@Dao
interface SongDao {
    @Query("SELECT * FROM cached_songs WHERE id = :id")
    suspend fun getSong(id: Long): CachedSong?

    @Query("SELECT * FROM cached_lines WHERE songId = :songId ORDER BY lineIndex")
    suspend fun getLines(songId: Long): List<CachedLine>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertSong(song: CachedSong)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertLines(lines: List<CachedLine>)
}
```

Repository decides source:

```kotlin
class SongRepository(private val api: SongApi, private val dao: SongDao) {
    suspend fun getSong(id: Long): SongDetail {
        val cached = dao.getSong(id)
        return if (cached != null) {
            cached.toDomain(dao.getLines(id))
        } else {
            val remote = api.getSong(id)
            dao.upsertSong(remote.toCachedSong())
            dao.upsertLines(remote.toCachedLines())
            remote.toDomain()
        }
    }
}
```

Favorites and transpose-offset writes go through a similar "write locally, enqueue WorkManager sync job" pattern so they work offline and flush when connectivity returns.

---

## Suggested build order
1. Laravel migrations + Sanctum auth + Song/Line/Favorite/Preference endpoints
2. Spotify metadata sync job (populate `songs`)
3. Android networking layer (Retrofit + Room repository, offline-first read path)
4. Dashboard screen (RecyclerView + floating nav)
5. Player screen: chord diagram strip → lyric sync/highlight → transpose engine wiring → ExoPlayer waveform
6. Favorites + transpose-offset sync via WorkManager
