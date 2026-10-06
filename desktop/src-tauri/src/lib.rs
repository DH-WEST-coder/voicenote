mod assets;
mod audio;
mod chatgpt;
mod engine;
mod storage;
mod updates;
use serde_json::{json, Value};
use std::{
    fs,
    io::{BufRead, BufReader},
    sync::Mutex,
};
use storage::*;
use tauri::{AppHandle, Emitter, Manager};
pub struct Runtime {
    storage: Storage,
    audio: audio::Audio,
    engine: engine::Engine,
    chat: chatgpt::Chat,
    recording_start: Mutex<bool>,
}
#[tauri::command]
fn log_error(app: AppHandle) -> Result<(), String> {
    app.state::<Runtime>()
        .storage
        .log("UI operation failed (내용 생략)");
    Ok(())
}
#[tauri::command]
fn load_data(app: AppHandle) -> Result<Data, String> {
    Ok(app
        .state::<Runtime>()
        .storage
        .data
        .lock()
        .map_err(err)?
        .clone())
}
#[tauri::command]
fn save_project(app: AppHandle, mut project: Project) -> Result<String, String> {
    let state = app.state::<Runtime>();
    if project.id.is_empty() {
        project.id = uuid::Uuid::new_v4().to_string();
    }
    id(&project.id)?;
    if !["auto", "Korean", "English"].contains(&project.language.as_str()) {
        return Err("잘못된 언어".into());
    }
    let key = project.id.clone();
    let mut d = state.storage.data.lock().map_err(err)?;
    if let Some(p) = d.projects.iter_mut().find(|p| p.id == key) {
        *p = project;
    } else {
        d.projects.push(project)
    }
    state.storage.save(&d)?;
    engine::notify(&app);
    Ok(key)
}
#[tauri::command]
fn save_note(
    app: AppHandle,
    mut note: Note,
    fields: Option<Vec<String>>,
) -> Result<String, String> {
    let state = app.state::<Runtime>();
    let mut d = state.storage.data.lock().map_err(err)?;
    if !d.projects.iter().any(|p| p.id == note.project_id) {
        return Err("프로젝트 없음".into());
    }
    if note.id.is_empty() {
        note.id = uuid::Uuid::new_v4().to_string();
        note.created_at = chrono::Local::now().to_rfc3339();
    }
    id(&note.id)?;
    let key = note.id.clone();
    if let Some(n) = d.notes.iter_mut().find(|n| n.id == key) {
        // 엔진 갱신 필드는 UI가 덮어쓰지 않는다.
        let fields =
            fields.unwrap_or_else(|| vec!["title".into(), "speakerNames".into(), "terms".into()]);
        apply_note_fields(n, &note, &fields);
    } else {
        d.notes.push(note)
    }
    state.storage.save(&d)?;
    engine::notify(&app);
    Ok(key)
}
// 메타데이터의 서로 다른 편집이 AI 용어 추출이나 다른 필드를 되돌리지 않게 한다.
fn apply_note_fields(target: &mut Note, patch: &Note, fields: &[String]) {
    if fields.iter().any(|s| s == "title") {
        target.title = patch.title.clone();
    }
    if fields.iter().any(|s| s == "speakerNames") {
        target.speaker_names = patch.speaker_names.clone();
    }
    if fields.iter().any(|s| s == "terms") {
        target.terms = patch.terms.clone();
    }
}
#[tauri::command]
fn save_settings(app: AppHandle, settings: Settings) -> Result<(), String> {
    let state = app.state::<Runtime>();
    let mut d = state.storage.data.lock().map_err(err)?;
    let mut settings = settings;
    settings.update_checked = d.settings.update_checked.clone();
    d.settings = settings;
    state.storage.save(&d)?;
    let config_path = state.storage.root.join("config.json");
    let mut config: Value = std::fs::read(&config_path).ok()
        .and_then(|bytes| serde_json::from_slice(&bytes).ok()).unwrap_or_else(|| json!({}));
    config["asr_model"] = json!(d.settings.asr_model.clone());
    config["live_model"] = json!(d.settings.live_model.clone());
    atomic(&config_path, &serde_json::to_vec_pretty(&config).map_err(err)?)?;
    engine::notify(&app);
    Ok(())
}
#[tauri::command]
fn save_text(app: AppHandle, note_id: String, text: String) -> Result<(), String> {
    id(&note_id)?;
    atomic(
        &app.state::<Runtime>()
            .storage
            .root
            .join("notes")
            .join(format!("{note_id}.md")),
        text.as_bytes(),
    )
}
#[tauri::command]
fn note_detail(app: AppHandle, note_id: String) -> Result<Value, String> {
    id(&note_id)?;
    let state = app.state::<Runtime>();
    let d = state.storage.data.lock().map_err(err)?;
    let n = d
        .notes
        .iter()
        .find(|n| n.id == note_id)
        .ok_or("노트 없음")?;
    let rs: Vec<Recording> = n
        .recording_ids
        .iter()
        .filter_map(|id| d.recordings.iter().find(|r| &r.id == id).cloned())
        .collect();
    let mut lines = vec![];
    for (r, o) in rs.iter().zip(offsets(&rs)) {
        if let Some(path) = &r.transcript {
            lines.extend(parse_md(
                &fs::read_to_string(state.storage.owned(path)?).map_err(err)?,
                &r.id,
                o,
            ));
        } else if let Some(path) = &r.live {
            if let Ok(text) = fs::read_to_string(state.storage.owned(path)?) {
                for l in text.lines() {
                    if let Ok(v) = engine::parse_json_line(l) {
                        if v["type"] == "commit" {
                            let t = v["start"].as_f64().unwrap_or(0.);
                            lines.push(Line {
                                time: o + t,
                                local_time: t,
                                recording_id: r.id.clone(),
                                speaker: String::new(),
                                text: v["text"].as_str().unwrap_or("").into(),
                            });
                        }
                    }
                }
            }
        }
    }
    let notes = state
        .storage
        .root
        .join("notes")
        .join(format!("{note_id}.md"));
    let chats = state
        .storage
        .root
        .join("chats")
        .join(format!("{note_id}.json"));
    Ok(
        json!({"text":if notes.exists(){fs::read_to_string(notes).map_err(err)?}else{String::new()},"messages":read_json::<Vec<Value>>(&chats)?,"lines":lines}),
    )
}
fn import_one(app: &AppHandle, note_id: &str, path: &str) -> Result<String, String> {
    id(note_id)?;
    let source = std::path::Path::new(path);
    let ext = source
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_lowercase();
    let material = ext == "pdf";
    if !material
        && ![
            "wav", "mp3", "m4a", "aac", "flac", "ogg", "aiff", "aif", "mp4", "opus",
        ]
        .contains(&ext.as_str())
    {
        return Err("지원하지 않는 파일".into());
    }
    let state = app.state::<Runtime>();
    let mut d = state.storage.data.lock().map_err(err)?;
    let n = d
        .notes
        .iter_mut()
        .find(|n| n.id == note_id)
        .ok_or("노트 없음")?;
    let key = uuid::Uuid::new_v4().to_string();
    let dest = state
        .storage
        .root
        .join(if material { "materials" } else { "audio" })
        .join(format!("{key}.{ext}"));
    fs::copy(source, &dest).map_err(err)?;
    let dest = dest.to_string_lossy().to_string();
    if material {
        n.materials.push(Material {
            id: key.clone(),
            name: source.file_name().unwrap().to_string_lossy().into(),
            path: dest,
            text: String::new(),
        });
    } else {
        n.recording_ids.push(key.clone());
        d.recordings.push(Recording {
            id: key.clone(),
            note_id: note_id.into(),
            duration: audio::duration(std::path::Path::new(&dest)),
            path: dest,
            status: "queued".into(),
            ..Default::default()
        });
    }
    state.storage.save(&d)?;
    drop(d);
    if !material {
        state.engine.queue.send(key.clone()).map_err(err)?;
    }
    engine::notify(app);
    Ok(key)
}
#[tauri::command]
async fn import_file(app: AppHandle, note_id: String, path: String) -> Result<String, String> {
    tauri::async_runtime::spawn_blocking(move || import_one(&app, &note_id, &path))
        .await
        .map_err(err)?
}
#[tauri::command]
fn material_text(
    app: AppHandle,
    note_id: String,
    material_id: String,
    text: String,
) -> Result<(), String> {
    let state = app.state::<Runtime>();
    let mut d = state.storage.data.lock().map_err(err)?;
    let m = d
        .notes
        .iter_mut()
        .find(|n| n.id == note_id)
        .and_then(|n| n.materials.iter_mut().find(|m| m.id == material_id))
        .ok_or("자료 없음")?;
    m.text = text;
    state.storage.save(&d)?;
    engine::notify(&app);
    Ok(())
}
#[tauri::command]
async fn read_asset(app: AppHandle, path: String) -> Result<Vec<u8>, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let state = app.state::<Runtime>();
        fs::read(state.storage.owned(&path)?).map_err(err)
    })
    .await
    .map_err(err)?
}
#[tauri::command]
async fn start_recording(app: AppHandle, note_id: String) -> Result<String, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let state = app.state::<Runtime>();
        {
            let mut pending = state.recording_start.lock().map_err(err)?;
            if *pending || state.audio.recording.lock().map_err(err)?.is_some() {
                return Err("이미 녹음 중".into());
            }
            *pending = true;
        }
        let result = (|| {
            let key = uuid::Uuid::new_v4().to_string();
            let mut d = state.storage.data.lock().map_err(err)?;
            let live = d.settings.live_enabled;
            let n = d
                .notes
                .iter_mut()
                .find(|n| n.id == note_id)
                .ok_or("노트 없음")?;
            n.recording_ids.push(key.clone());
            let path = state.storage.root.join("audio").join(format!("{key}.wav"));
            d.recordings.push(Recording {
                id: key.clone(),
                note_id: note_id.clone(),
                path: path.to_string_lossy().into(),
                status: "recording".into(),
                ..Default::default()
            });
            state.storage.save(&d)?;
            drop(d);
            let tx = if live {
                match engine::start_live(&app, &state.storage, &key, &note_id) {
                    Ok(tx) => {
                        let mut d = state.storage.data.lock().unwrap();
                        d.recordings.iter_mut().find(|r| r.id == key).unwrap().live = Some(
                            state
                                .storage
                                .root
                                .join("live")
                                .join(format!("{key}.jsonl"))
                                .to_string_lossy()
                                .into(),
                        );
                        state.storage.save(&d)?;
                        Some(tx)
                    }
                    Err(e) => {
                        state.storage.log("live unavailable");
                        let _ = app.emit(
                            "live-message",
                            json!({"id":key,"message":{"type":"error","message":e}}),
                        );
                        None
                    }
                }
            } else {
                None
            };
            if let Err(e) = audio::start(app.clone(), key.clone(), path, tx) {
                engine::notify(&app);
                return Err(e);
            }
            engine::notify(&app);
            Ok(key)
        })();
        *state.recording_start.lock().unwrap() = false;
        result
    })
    .await
    .map_err(err)?
}
#[tauri::command]
async fn stop_recording(app: AppHandle) -> Result<(), String> {
    tauri::async_runtime::spawn_blocking(move || {
        let state = app.state::<Runtime>();
        if let Some(tx) = state.audio.control.lock().map_err(err)?.take() {
            tx.send(()).map_err(err)?;
        }
        if let Some(worker) = state.audio.worker.lock().map_err(err)?.take() {
            worker.join().map_err(|_| "녹음 종료 실패".to_string())?;
        }
        Ok(())
    })
    .await
    .map_err(err)?
}
#[tauri::command]
fn retry_recording(app: AppHandle, recording_id: String) -> Result<(), String> {
    let state = app.state::<Runtime>();
    let mut d = state.storage.data.lock().map_err(err)?;
    let r = d
        .recordings
        .iter_mut()
        .find(|r| r.id == recording_id)
        .ok_or("녹음 없음")?;
    if ["processing", "recording", "queued"].contains(&r.status.as_str()) {
        return Err("이미 처리 중".into());
    }
    r.status = "queued".into();
    r.error = None;
    state.storage.save(&d)?;
    state.engine.queue.send(recording_id).map_err(err)?;
    engine::notify(&app);
    Ok(())
}
#[tauri::command]
async fn microphone_check() -> Result<(), String> {
    tauri::async_runtime::spawn_blocking(audio::check_microphone)
        .await
        .map_err(err)?
}
#[tauri::command]
fn open_data_folder(app: AppHandle, logs: bool) -> Result<(), String> {
    use tauri_plugin_opener::OpenerExt;
    let state = app.state::<Runtime>();
    let path = if logs {
        state.storage.root.join("logs")
    } else {
        state.storage.root.clone()
    };
    app.opener()
        .open_path(path.to_string_lossy().as_ref(), None::<&str>)
        .map_err(err)
}
#[tauri::command]
async fn device_info(app: AppHandle) -> Result<Value, String> {
    tauri::async_runtime::spawn_blocking(move||{let memory=std::process::Command::new("/usr/sbin/sysctl").args(["-n","hw.memsize"]).output().map_err(err)?;let memory=String::from_utf8_lossy(&memory.stdout).trim().parse::<u64>().unwrap_or(0);let root=app.state::<Runtime>().storage.root.clone();let disk=std::process::Command::new("/bin/df").args(["-k",root.to_str().unwrap()]).output().map_err(err)?;let disk=String::from_utf8_lossy(&disk.stdout).lines().nth(1).and_then(|l|l.split_whitespace().nth(3)).and_then(|v|v.parse::<u64>().ok()).unwrap_or(0)*1024;Ok(json!({"appleSilicon":std::env::consts::ARCH=="aarch64","memoryBytes":memory,"freeBytes":disk,"recommended":if memory>=16*1024*1024*1024u64{"full"}else{"lite"}}))}).await.map_err(err)?
}
#[tauri::command]
async fn models_status(app: AppHandle) -> Result<Value, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let state = app.state::<Runtime>();
        let result = engine::command(&app, &state.storage)?
            .args(["models", "status", "--json"])
            .output()
            .map_err(err)?;
        let v = engine::parse_json_line(String::from_utf8_lossy(&result.stdout).trim())?;
        if result.status.success() {
            Ok(v)
        } else {
            Err(v["message"].as_str().unwrap_or("모델 상태 오류").into())
        }
    })
    .await
    .map_err(err)?
}
#[tauri::command]
fn download_models(app: AppHandle, model_id: String, model_type: String) -> Result<(), String> {
    let models: Vec<String> = model_id.split(',').map(str::to_string).collect();
    if !["asr", "live", "both"].contains(&model_type.as_str()) || models.is_empty() ||
        models.iter().any(|m| !["moona3k/mlx-qwen3-asr-1.7b-8bit", "moona3k/mlx-qwen3-asr-0.6b-4bit"].contains(&m.as_str())) {
        return Err("잘못된 받아쓰기 모델".into());
    }
    let state = app.state::<Runtime>();
    let (target_asr, target_live) = {
        let d = state.storage.data.lock().map_err(err)?;
        let mut asr = d.settings.asr_model.clone();
        let mut live = d.settings.live_model.clone();
        if model_type == "asr" { asr = model_id.clone(); }
        if model_type == "live" { live = model_id.clone(); }
        if model_type == "both" {
            asr = models.iter().find(|m| m.as_str() != "moona3k/mlx-qwen3-asr-0.6b-4bit").cloned().unwrap_or_else(|| models[0].clone());
            live = models.iter().find(|m| m.as_str() == "moona3k/mlx-qwen3-asr-0.6b-4bit").cloned().unwrap_or_else(|| models[0].clone());
        }
        (asr, live)
    };
    let mut busy = state.engine.downloads.lock().map_err(err)?;
    if *busy {
        return Err("이미 다운로드 중".into());
    }
    let mut child = engine::command(&app, &state.storage)?
        .args(["models", "download", "--models", &model_id, "--asr-model", &target_asr, "--live-model", &target_live, "--json"])
        .spawn()
        .map_err(err)?;
    engine::stderr(app.clone(), child.stderr.take().unwrap());
    let stdout = child.stdout.take().unwrap();
    let child = engine::track(&app, child)?;
    *busy = true;
    drop(busy);
    std::thread::spawn(move || {
        let mut completion = None;
        let mut failure = None;
        for line in BufReader::new(stdout).lines() {
            match line.map_err(err).and_then(|l| engine::parse_json_line(&l)) {
                Ok(v) => {
                    if v["status"] == "done" {
                        completion = Some(v);
                    } else if v["status"] == "error" {
                        failure = Some(
                            v["message"]
                                .as_str()
                                .unwrap_or("모델 다운로드 실패")
                                .to_string(),
                        );
                    } else {
                        let _ = app.emit("model-progress", v);
                    }
                }
                Err(_) => {
                    failure = Some("모델 엔진 메시지를 읽지 못했습니다".into());
                    engine::terminate(&child);
                    break;
                }
            }
        }
        let exit = engine::wait(&child);
        let state = app.state::<Runtime>();
        if completion.is_some() && failure.is_none() && exit.is_ok_and(|s| s.success()) {
            let mut d = state.storage.data.lock().unwrap();
            d.settings.asr_model = target_asr.clone();
            d.settings.live_model = target_live.clone();
            match state.storage.save(&d) {
                Ok(()) => {
                    engine::notify(&app);
                    let _ = app.emit("model-progress", completion.unwrap());
                }
                Err(_) => failure = Some("모델 설정을 저장하지 못했습니다".into()),
            }
        } else if failure.is_none() {
            failure = Some("모델 다운로드 실패. 다시 시도하세요.".into());
        }
        if let Some(message) = failure {
            state.storage.log("model download failed");
            let _ = app.emit(
                "model-progress",
                json!({"status":"error","message":message}),
            );
        }
        *state.engine.downloads.lock().unwrap() = false;
    });
    Ok(())
}
#[tauri::command]
fn export_note(app: AppHandle, note_id: String, path: String, plain: bool) -> Result<(), String> {
    let detail = note_detail(app.clone(), note_id.clone())?;
    let state = app.state::<Runtime>();
    let d = state.storage.data.lock().map_err(err)?;
    let n = d
        .notes
        .iter()
        .find(|n| n.id == note_id)
        .ok_or("노트 없음")?;
    let mut text = format!(
        "# {}\n\n{}\n\n## 내 노트\n\n{}\n\n## 대본\n\n",
        n.title,
        n.created_at,
        detail["text"].as_str().unwrap_or("")
    );
    for l in detail["lines"].as_array().unwrap() {
        let speaker = l["speaker"].as_str().unwrap_or("");
        let speaker = n
            .speaker_names
            .get(speaker)
            .map(String::as_str)
            .unwrap_or(speaker);
        let t = l["time"].as_f64().unwrap_or(0.) as u64;
        text.push_str(&format!(
            "[{}:{:02}] {}: {}\n\n",
            t / 60,
            t % 60,
            speaker,
            l["text"].as_str().unwrap_or("")
        ));
    }
    if plain {
        text = text
            .lines()
            .map(|l| l.trim_start_matches('#').trim_start())
            .collect::<Vec<_>>()
            .join("\n");
    }
    atomic(std::path::Path::new(&path), text.as_bytes())
}
#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .register_asynchronous_uri_scheme_protocol("asset", |ctx, req, responder| {
            let app = ctx.app_handle().clone();
            std::thread::spawn(move || responder.respond(assets::serve(&app, &req)));
        })
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_shell::init())
        .setup(|app| {
            let root = if cfg!(debug_assertions) {
                std::env::var_os("VNOTE_DATA_DIR")
                    .map(std::path::PathBuf::from)
                    .unwrap_or(dirs::data_dir().ok_or("데이터 경로 없음")?.join("VNote"))
            } else {
                dirs::data_dir().ok_or("데이터 경로 없음")?.join("VNote")
            };
            let storage = Storage::open(root).map_err(std::io::Error::other)?;
            let handle = app.handle().clone();
            let engine = engine::init(handle.clone());
            app.manage(Runtime {
                storage,
                audio: audio::Audio::default(),
                engine,
                chat: chatgpt::Chat::default(),
                recording_start: Mutex::new(false),
            });
            let state = app.state::<Runtime>();
            for r in &state.storage.data.lock().unwrap().recordings {
                if r.status == "queued" {
                    let _ = state.engine.queue.send(r.id.clone());
                }
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            log_error,
            load_data,
            save_project,
            save_note,
            save_settings,
            save_text,
            note_detail,
            import_file,
            material_text,
            read_asset,
            start_recording,
            stop_recording,
            retry_recording,
            microphone_check,
            open_data_folder,
            device_info,
            models_status,
            download_models,
            export_note,
            chatgpt::chat_status,
            chatgpt::chat_login,
            chatgpt::chat_logout,
            chatgpt::chat_stop,
            chatgpt::chat_ask,
            chatgpt::save_chat,
            updates::check_update
        ])
        .build(tauri::generate_context!())
        .expect("VNote 시작 실패")
        .run(|app, event| {
            if let tauri::RunEvent::Exit = event {
                let state = app.state::<Runtime>();
                if let Some(tx) = state.audio.control.lock().unwrap().take() {
                    let _ = tx.send(());
                }
                engine::shutdown(app);
                if let Some(worker) = state.audio.worker.lock().unwrap().take() {
                    let _ = worker.join();
                }
                if let Some(mut c) = state.chat.child.lock().unwrap().take() {
                    engine::kill_child(&mut c);
                    let _ = c.wait();
                }
                if let Some(mut c) = state.chat.login.lock().unwrap().take() {
                    engine::kill_child(&mut c);
                    let _ = c.wait();
                };
            }
        });
}

#[cfg(test)]
mod metadata_tests {
    use super::*;
    #[test]
    fn rename_does_not_replace_ai_terms() {
        let mut current = Note {
            title: "기존".into(),
            terms: vec!["AI 용어".into()],
            recording_ids: vec!["녹음".into()],
            ..Default::default()
        };
        let stale = Note {
            title: "새 제목".into(),
            terms: vec![],
            ..Default::default()
        };
        apply_note_fields(&mut current, &stale, &["title".into()]);
        assert_eq!(current.title, "새 제목");
        assert_eq!(current.terms, vec!["AI 용어"]);
        assert_eq!(current.recording_ids, vec!["녹음"]);
    }
}
