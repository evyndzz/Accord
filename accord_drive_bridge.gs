/**
 * ACCORD MUSIC VAULT - Google Apps Script Bridge
 * 
 * Petunjuk Pemasangan Cepat (1 Menit):
 * 1. Buka Google Drive (drive.google.com).
 * 2. Klik tombol "Baru" (+) di kiri atas -> pilih "Lainnya" -> "Google Apps Script".
 * 3. Hapus semua kode default dan tempel (paste) seluruh kode ini.
 * 4. Beri nama proyek di kiri atas: "Accord Vault Bridge".
 * 5. Klik tombol biru "Terapkan" (Deploy) di kanan atas -> Pilih "Penerapan baru" (New deployment).
 * 6. Klik ikon gerigi (Pilih jenis) -> Pilih "Aplikasi Web" (Web app).
 * 7. Isi konfigurasi:
 *    - Deskripsi: Accord Music Bridge
 *    - Jalankan sebagai: Saya (email akun Anda)
 *    - Yang memiliki akses (Who has access): "Siapa saja" (Anyone)
 * 8. Klik tombol "Terapkan" (Deploy) -> Klik "Beri Akses" (Authorize) -> Pilih akun Google Anda.
 * 9. Salin "URL Aplikasi Web" (Web app URL yang berakhiran /exec).
 * 10. Buka Accord di HP -> Masuk tab Google Drive Music -> Klik "Hubungkan Cloud Vault" -> Tempelkan URL tersebut!
 */

const FOLDER_NAME = "Accord Music";
const AUDIO_FOLDER_NAME = "audio";
const CHORDS_FOLDER_NAME = "chords";
const COVERS_FOLDER_NAME = "covers";

function doGet(e) {
  try {
    const params = e ? e.parameter : {};
    const action = params.action || "ping";

    if (action === "ping") {
      return jsonResponse({
        status: "ok",
        app: "Accord Music Vault",
        timestamp: new Date().getTime()
      });
    }

    if (action === "sync") {
      return jsonResponse(syncVault());
    }

    if (action === "get_chord") {
      const trackId = params.id;
      if (!trackId) return jsonResponse({ error: "Missing song ID" });
      return jsonResponse(getChord(trackId, params.title));
    }

    if (action === "save_chord") {
      // Mendukung simpan chord lewat GET base64 untuk menghindari kendala redirect HTTP POST di perangkat mobile
      const dataStr = params.data;
      if (!dataStr) return jsonResponse({ error: "Missing data payload" });
      const decodedJson = Utilities.newBlob(Utilities.base64Decode(dataStr)).getDataAsString();
      const payload = JSON.parse(decodedJson);
      return jsonResponse(saveChord(payload));
    }

    if (action === "delete_song") {
      const trackId = params.id;
      if (!trackId) return jsonResponse({ error: "Missing song ID" });
      return jsonResponse(deleteSong(trackId));
    }

    if (action === "delete_chord") {
      const trackId = params.id;
      if (!trackId) return jsonResponse({ error: "Missing song ID" });
      return jsonResponse(deleteChord(trackId));
    }

    return jsonResponse({ error: "Unknown action: " + action });
  } catch (err) {
    return jsonResponse({ error: err.toString() });
  }
}

function doPost(e) {
  try {
    let payload;
    if (e.postData && e.postData.contents) {
      payload = JSON.parse(e.postData.contents);
    } else if (e.parameter && e.parameter.data) {
      payload = JSON.parse(e.parameter.data);
    } else {
      return jsonResponse({ error: "No post data received" });
    }

    const action = payload.action || (e.parameter ? e.parameter.action : "save_chord");

    if (action === "save_chord") {
      return jsonResponse(saveChord(payload));
    }

    if (action === "upload_audio") {
      return jsonResponse(uploadAudio(payload));
    }

    if (action === "upload_cover") {
      return jsonResponse(uploadCover(payload));
    }

    if (action === "delete_song") {
      const trackId = payload.id || (e.parameter ? e.parameter.id : null);
      if (!trackId) return jsonResponse({ error: "Missing song ID" });
      return jsonResponse(deleteSong(trackId));
    }

    if (action === "delete_chord") {
      const trackId = payload.id || (e.parameter ? e.parameter.id : null);
      if (!trackId) return jsonResponse({ error: "Missing song ID" });
      return jsonResponse(deleteChord(trackId));
    }

    return jsonResponse({ error: "Unknown post action: " + action });
  } catch (err) {
    return jsonResponse({ error: err.toString() });
  }
}

function getOrCreateVault() {
  let rootFolder;
  const folders = DriveApp.getFoldersByName(FOLDER_NAME);
  if (folders.hasNext()) {
    rootFolder = folders.next();
  } else {
    rootFolder = DriveApp.createFolder(FOLDER_NAME);
    try {
      rootFolder.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
    } catch (_) {}
  }

  let audioFolder;
  const audioFolders = rootFolder.getFoldersByName(AUDIO_FOLDER_NAME);
  if (audioFolders.hasNext()) {
    audioFolder = audioFolders.next();
  } else {
    audioFolder = rootFolder.createFolder(AUDIO_FOLDER_NAME);
    try {
      audioFolder.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
    } catch (_) {}
  }

  let chordsFolder;
  const chordFolders = rootFolder.getFoldersByName(CHORDS_FOLDER_NAME);
  if (chordFolders.hasNext()) {
    chordsFolder = chordFolders.next();
  } else {
    chordsFolder = rootFolder.createFolder(CHORDS_FOLDER_NAME);
    try {
      chordsFolder.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
    } catch (_) {}
  }

  let coversFolder;
  const coverFolders = rootFolder.getFoldersByName(COVERS_FOLDER_NAME);
  if (coverFolders.hasNext()) {
    coversFolder = coverFolders.next();
  } else {
    coversFolder = rootFolder.createFolder(COVERS_FOLDER_NAME);
    try {
      coversFolder.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
    } catch (_) {}
  }

  return { root: rootFolder, audio: audioFolder, chords: chordsFolder, covers: coversFolder };
}

function syncVault() {
  const vault = getOrCreateVault();
  const songs = [];
  const seenIds = {};

  // 1. Scan and index all images for automatic thumbnail association
  const imageMapByName = {};
  const imageMapByArtist = {};
  let defaultCoverId = null;

  function scanImages(folder) {
    if (!folder) return;
    const files = folder.getFiles();
    while (files.hasNext()) {
      const f = files.next();
      const name = f.getName().toLowerCase();
      const mime = f.getMimeType();
      const isImg = mime.indexOf("image") !== -1 ||
                    name.endsWith(".jpg") || name.endsWith(".jpeg") ||
                    name.endsWith(".png") || name.endsWith(".webp");
      if (isImg) {
        try {
          f.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
        } catch (_) {}
        const fId = f.getId();
        const baseName = name.replace(/\.[^/.]+$/, "").trim().toLowerCase();

        if (baseName === "cover" || baseName === "folder" || baseName === "default" || baseName === "albumart") {
          defaultCoverId = fId;
        }

        imageMapByName[baseName] = fId;

        // If named "Artist - Title"
        if (baseName.indexOf(" - ") !== -1) {
          const parts = baseName.split(" - ");
          const art = parts[0].trim().toLowerCase();
          const tit = parts.slice(1).join(" - ").trim().toLowerCase();
          imageMapByArtist[art] = fId;
          imageMapByName[tit] = fId;
        } else {
          imageMapByArtist[baseName] = fId;
        }
      }
    }
  }

  scanImages(vault.covers);
  scanImages(vault.audio);
  scanImages(vault.root);

  // 2. Scan audio files and auto-match with thumbnails
  function scanFiles(folder) {
    if (!folder) return;
    const files = folder.getFiles();
    while (files.hasNext()) {
      const file = files.next();
      const name = file.getName();
      const mime = file.getMimeType();
      const id = file.getId();

      const isAudio = mime.indexOf("audio") !== -1 || 
                      name.toLowerCase().endsWith(".mp3") || 
                      name.toLowerCase().endsWith(".m4a") || 
                      name.toLowerCase().endsWith(".wav") || 
                      name.toLowerCase().endsWith(".ogg") || 
                      name.toLowerCase().endsWith(".flac");

      if (isAudio && !seenIds[id]) {
        seenIds[id] = true;
        try {
          file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
        } catch (_) {}

        let cleanName = name.replace(/\.[^/.]+$/, "");
        let artist = "Tidak Diketahui";
        // Selalu gunakan nama lengkap file sebagai title agar tidak terpotong (misal: "Di Badai Topan Dunia - Pop Rohani KK 497 (Live)")
        let title = cleanName;

        // Auto-match thumbnail from images (baik dengan nama lengkap maupun bagian depan sebelum hyphen)
        const cleanLower = cleanName.toLowerCase();
        let matchedImageId = imageMapByName[cleanLower] || defaultCoverId;
        if (!matchedImageId && cleanName.indexOf(" - ") !== -1) {
          const firstPart = cleanName.split(" - ")[0].trim().toLowerCase();
          matchedImageId = imageMapByName[firstPart] || defaultCoverId;
        }

        let albumArtUrl = null;
        if (matchedImageId) {
          albumArtUrl = "https://lh3.googleusercontent.com/d/" + matchedImageId;
        }

        songs.push({
          id: "drive_" + id,
          fileId: id,
          title: title,
          artist: artist,
          albumArtUrl: albumArtUrl,
          size: file.getSize(),
          streamUrl: "https://drive.usercontent.google.com/download?id=" + id + "&export=download",
          updatedAt: file.getLastUpdated().getTime()
        });
      }
    }
  }

  scanFiles(vault.audio);
  scanFiles(vault.root);

  const chordFiles = [];
  const cFiles = vault.chords.getFiles();
  while (cFiles.hasNext()) {
    const cf = cFiles.next();
    const cName = cf.getName();
    if (cName.endsWith(".json")) {
      chordFiles.push(cName.replace(".json", ""));
    }
  }

  return {
    status: "ok",
    folderName: FOLDER_NAME,
    totalSongs: songs.length,
    totalChords: chordFiles.length,
    songs: songs,
    availableChords: chordFiles
  };
}

function sanitizeId(id) {
  return id.replace(/[^a-zA-Z0-9_-]/g, "_");
}

function getChord(trackId, title) {
  const vault = getOrCreateVault();
  const idFilename = sanitizeId(trackId) + ".json";
  
  let files = vault.chords.getFilesByName(idFilename);

  // Search by readable song title if not found by ID
  if (!files.hasNext() && title) {
    const cleanTitle = title.replace(/[/\\?%*:|"<>]/g, "_") + ".json";
    files = vault.chords.getFilesByName(cleanTitle);
  }

  // Also support .lrc timed lyric files in chords or audio folder
  if (!files.hasNext() && title) {
    const lrcName = title.replace(/[/\\?%*:|"<>]/g, "_") + ".lrc";
    let lrcFiles = vault.chords.getFilesByName(lrcName);
    if (!lrcFiles.hasNext()) {
      lrcFiles = vault.audio.getFilesByName(lrcName);
    }
    if (lrcFiles.hasNext()) {
      const lrcContent = lrcFiles.next().getBlob().getDataAsString();
      const parsedLines = parseLrc(lrcContent);
      if (parsedLines.length > 0) {
        return {
          found: true,
          id: trackId,
          chordData: {
            id: trackId,
            title: title,
            lines: parsedLines
          }
        };
      }
    }
  }

  if (!files.hasNext()) {
    return { found: false, id: trackId };
  }

  const file = files.next();
  const content = file.getBlob().getDataAsString();
  try {
    const data = JSON.parse(content);
    return { found: true, id: trackId, chordData: data };
  } catch (e) {
    return { found: false, error: "Invalid JSON in chord file" };
  }
}

// Converts [mm:ss.xx] LRC timed lyric format into Accord SongLine objects
function parseLrc(content) {
  const lines = content.split(/\r?\n/);
  const result = [];
  let index = 0;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    const match = line.match(/^\[(\d{2}):(\d{2})(?:\.(\d{2,3}))?\](.*)$/);
    if (match) {
      const min = parseInt(match[1], 10);
      const sec = parseInt(match[2], 10);
      const ms = match[3] ? parseInt(match[3].padEnd(3, '0').substring(0, 3), 10) : 0;
      const startTimeMs = (min * 60 + sec) * 1000 + ms;
      const rawText = match[4].trim();
      result.push({
        lineIndex: index++,
        startTimeMs: startTimeMs,
        rawLine: rawText
      });
    }
  }
  return result;
}

function saveChord(payload) {
  const vault = getOrCreateVault();
  const trackId = payload.id;
  if (!trackId) throw new Error("Track ID required");

  const idFilename = sanitizeId(trackId) + ".json";
  const jsonString = JSON.stringify(payload, null, 2);

  function writeJsonFile(folder, name, content) {
    const existing = folder.getFilesByName(name);
    let f;
    if (existing.hasNext()) {
      f = existing.next();
      f.setContent(content);
    } else {
      f = folder.createFile(name, content, "application/json");
    }
    try {
      f.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
    } catch (_) {}
    return f;
  }

  // 1. Save by Track ID
  const file = writeJsonFile(vault.chords, idFilename, jsonString);

  // 2. Also save by human-readable filename (e.g. "Pamungkas - To The Bone.json")
  if (payload.title && payload.title !== "Untitled") {
    let friendlyName = payload.title;
    if (payload.artist && payload.artist !== "Google Drive" && !friendlyName.toLowerCase().includes(payload.artist.toLowerCase())) {
      friendlyName = payload.artist + " - " + friendlyName;
    }
    const cleanFriendly = friendlyName.replace(/[/\\?%*:|"<>]/g, "_") + ".json";
    writeJsonFile(vault.chords, cleanFriendly, jsonString);
  }

  return {
    status: "success",
    id: trackId,
    fileId: file.getId(),
    filename: idFilename,
    updatedAt: new Date().getTime()
  };
}

function uploadAudio(payload) {
  const vault = getOrCreateVault();
  const filename = payload.filename || ("song_" + new Date().getTime() + ".mp3");
  const base64Data = payload.data;
  if (!base64Data) throw new Error("Missing audio base64 data");

  const bytes = Utilities.base64Decode(base64Data);
  const mimeType = payload.mimeType || "audio/mpeg";
  const blob = Utilities.newBlob(bytes, mimeType, filename);
  const file = vault.audio.createFile(blob);

  try {
    file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
  } catch (_) {}

  const fileId = file.getId();
  return {
    status: "success",
    fileId: fileId,
    filename: filename,
    streamUrl: "https://drive.usercontent.google.com/download?id=" + fileId + "&export=download",
    directUrl: "https://drive.google.com/uc?export=download&id=" + fileId
  };
}

function uploadCover(payload) {
  const vault = getOrCreateVault();
  const filename = payload.filename || ("cover_" + new Date().getTime() + ".jpg");
  const base64Data = payload.data;
  if (!base64Data) throw new Error("Missing cover base64 data");

  const bytes = Utilities.base64Decode(base64Data);
  const mimeType = payload.mimeType || "image/jpeg";
  const blob = Utilities.newBlob(bytes, mimeType, filename);
  const file = vault.covers.createFile(blob);

  try {
    file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
  } catch (_) {}

  const fileId = file.getId();
  return {
    status: "success",
    fileId: fileId,
    filename: filename,
    imageUrl: "https://lh3.googleusercontent.com/d/" + fileId
  };
}

function deleteSong(trackId) {
  const vault = getOrCreateVault();
  const fileId = trackId.startsWith("drive_") ? trackId.substring(6) : trackId;
  let audioDeleted = false;
  let chordDeleted = false;

  // 1. Move audio file to Google Drive Trash
  try {
    const audioFile = DriveApp.getFileById(fileId);
    if (audioFile && !audioFile.isTrashed()) {
      audioFile.setTrashed(true);
      audioDeleted = true;
    }
  } catch (err) {
    // If not found by direct ID, search in audio folder
    try {
      const files = vault.audio.getFiles();
      while (files.hasNext()) {
        const f = files.next();
        if (f.getId() === fileId) {
          f.setTrashed(true);
          audioDeleted = true;
          break;
        }
      }
    } catch (_) {}
  }

  // 2. Move chord file to Google Drive Trash if exists
  const filename = sanitizeId(trackId) + ".json";
  const chordFiles = vault.chords.getFilesByName(filename);
  while (chordFiles.hasNext()) {
    const cf = chordFiles.next();
    cf.setTrashed(true);
    chordDeleted = true;
  }

  return {
    status: "success",
    action: "delete_song",
    id: trackId,
    audioDeleted: audioDeleted,
    chordDeleted: chordDeleted
  };
}

function deleteChord(trackId) {
  const vault = getOrCreateVault();
  const filename = sanitizeId(trackId) + ".json";
  const chordFiles = vault.chords.getFilesByName(filename);
  let deleted = false;
  while (chordFiles.hasNext()) {
    const cf = chordFiles.next();
    cf.setTrashed(true);
    deleted = true;
  }

  return {
    status: "success",
    action: "delete_chord",
    id: trackId,
    deleted: deleted
  };
}

function jsonResponse(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
