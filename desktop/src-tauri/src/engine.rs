use crate::{
    storage::{atomic, err, Storage},
    Runtime,
};
use serde_json::{json, Value};
use std::{
    io::{BufRead, BufReader, Write},
    process::{Child, Command, Stdio},
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc, Arc, Mutex,
    },
    thread,
};
use tauri::{AppHandle, Emitter, Manager};
pub struct Engine {
    pub queue: mpsc::Sender<String>,
    pub processes: Mutex<Vec<Arc<Mutex<Child>>>>,
    pub closing: AtomicBool,
    pub downloads: Mutex<bool>,
}
pub const TRANSLOCATION_MESSAGE: &str = "VNote를 응용 프로그램 폴더로 옮긴 뒤 다시 열어 주세요";
pub const QUARANTINE_ENGINE_MESSAGE: &str = "macOS가 엔진 실행을 막았습니다. 시스템 설정 → 개인정보 보호 및 보안에서 허용하거나, 앱을 응용 프로그램 폴더로 옮긴 뒤 다시 실행하세요.";
pub const QUARANTINE_COMMAND: &str = "xattr -dr com.apple.quarantine /Applications/VNote.app";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AppLocation {
    Translocated,
    Volume,
    Normal,
}

pub fn classify_app_path(path: &std::path::Path) -> AppLocation {
    if is_translocated_path(path) {
        AppLocation::Translocated
    } else if path.starts_with("/Volumes") {
        AppLocation::Volume
    } else {
        AppLocation::Normal
    }
}

pub fn should_relaunch(original: &std::path::Path, relaunched: bool, writable: bool) -> bool {
    !relaunched
        && writable
        && original.extension().is_some_and(|ext| ext == "app")
        && classify_app_path(original) == AppLocation::Normal
}

#[cfg(target_os = "macos")]
mod translocation {
    use std::{ffi::{c_char, c_void, CString}, os::unix::ffi::OsStrExt, path::{Path, PathBuf}, ptr};

    type CFUrl = *const c_void;
    type IsTranslocated = unsafe extern "C" fn(CFUrl, *mut u8, *mut *const c_void) -> u8;
    type CreateOriginal = unsafe extern "C" fn(CFUrl, *mut *const c_void) -> CFUrl;
    type CreateUrl = unsafe extern "C" fn(*const c_void, *const u8, isize, u8) -> CFUrl;
    type GetPath = unsafe extern "C" fn(CFUrl, u8, *mut u8, isize) -> u8;
    type Release = unsafe extern "C" fn(*const c_void);

    #[link(name = "System")]
    unsafe extern "C" {
        fn dlopen(path: *const c_char, mode: i32) -> *mut c_void;
        fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
        fn access(path: *const c_char, mode: i32) -> i32;
    }

    unsafe fn symbol<T: Copy>(handle: *mut c_void, name: &str) -> Option<T> {
        let name = CString::new(name).ok()?;
        let ptr = dlsym(handle, name.as_ptr());
        if ptr.is_null() { None } else { Some(std::mem::transmute_copy(&ptr)) }
    }

    pub fn original_path(bundle: &Path) -> Option<PathBuf> {
        unsafe {
            let security = dlopen(b"/System/Library/Frameworks/Security.framework/Security\0".as_ptr().cast(), 1);
            let cf = dlopen(b"/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation\0".as_ptr().cast(), 1);
            if security.is_null() || cf.is_null() { return None; }
            let is_translocated: IsTranslocated = symbol(security, "SecTranslocateIsTranslocatedURL")?;
            let create_original: CreateOriginal = symbol(security, "SecTranslocateCreateOriginalPathForURL")?;
            let create_url: CreateUrl = symbol(cf, "CFURLCreateFromFileSystemRepresentation")?;
            let get_path: GetPath = symbol(cf, "CFURLGetFileSystemRepresentation")?;
            let release: Release = symbol(cf, "CFRelease")?;
            let bytes = bundle.as_os_str().as_bytes();
            let url = create_url(ptr::null(), bytes.as_ptr(), bytes.len() as isize, 1);
            if url.is_null() { return None; }
            let mut translocated = 0u8;
            if is_translocated(url, &mut translocated, ptr::null_mut()) == 0 || translocated == 0 {
                release(url);
                return None;
            }
            let original = create_original(url, ptr::null_mut());
            release(url);
            if original.is_null() { return None; }
            let mut buffer = vec![0u8; 4096];
            let ok = get_path(original, 1, buffer.as_mut_ptr(), buffer.len() as isize);
            release(original);
            if ok == 0 { return None; }
            let len = buffer.iter().position(|b| *b == 0)?;
            Some(PathBuf::from(std::ffi::OsStr::from_bytes(&buffer[..len])))
        }
    }

    pub fn writable(path: &Path) -> bool {
        let Ok(path) = CString::new(path.as_os_str().as_bytes()) else { return false; };
        unsafe { access(path.as_ptr(), 2) == 0 }
    }
}

#[cfg(target_os = "macos")]
pub fn repair_translocated_launch() -> bool {
    use std::process;
    if std::env::var_os("VNOTE_RELAUNCHED").is_some() { return false; }
    let current = match std::env::current_exe().ok().and_then(|p| bundle_path(&p)) { Some(p) => p, None => return false };
    if classify_app_path(&current) != AppLocation::Translocated { return false; }
    let Some(original) = translocation::original_path(&current) else { return false; };
    if !original.is_dir() { return false; }
    if !should_relaunch(&original, false, translocation::writable(&original)) { return false; }
    let removed = Command::new("/usr/bin/xattr").args(["-dr", "com.apple.quarantine"]).arg(&original).status().is_ok_and(|s| s.success());
    if !removed { return false; }
    let opened = Command::new("/usr/bin/open").args(["-n", "--env", "VNOTE_RELAUNCHED=1"]).arg(&original).status().is_ok_and(|s| s.success());
    if opened { process::exit(0); }
    false
}

#[cfg(not(target_os = "macos"))]
pub fn repair_translocated_launch() -> bool { false }

pub fn bundle_path(exe: &std::path::Path) -> Option<std::path::PathBuf> {
    exe.parent()?
        .parent()?
        .parent()
        .map(std::path::Path::to_path_buf)
}
pub fn is_translocated_path(path: &std::path::Path) -> bool {
    path.components()
        .any(|c| c.as_os_str() == "AppTranslocation")
}
pub fn is_app_translocated() -> bool {
    std::env::current_exe()
        .ok()
        .and_then(|p| bundle_path(&p))
        .is_some_and(|p| is_translocated_path(&p))
}
pub fn clear_bundle_quarantine() -> bool {
    if is_app_translocated() {
        return false;
    }
    let Some(bundle) = std::env::current_exe().ok().and_then(|p| bundle_path(&p)) else {
        return false;
    };
    let mut failed = false;
    for target in [
        bundle.join("Contents/Resources/vnote-engine"),
        bundle.join("Contents/MacOS/fluidaudiocli"),
    ] {
        if target.exists() {
            if let Ok(status) = Command::new("/usr/bin/xattr")
                .args(["-dr", "com.apple.quarantine"])
                .arg(&target)
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status()
            {
                if !status.success() {
                    failed = true;
                }
            } else {
                failed = true;
            }
        }
    }
    failed
}
pub fn signaled(exit: &std::process::ExitStatus) -> bool {
    #[cfg(unix)]
    {
        use std::os::unix::process::ExitStatusExt;
        exit.signal().is_some()
    }
    #[cfg(not(unix))]
    {
        let _ = exit;
        false
    }
}
pub fn spawn_with_retry(app: &AppHandle, mut cmd: Command) -> Result<Child, String> {
    for attempt in 0..2 {
        let mut child = cmd.spawn().map_err(err)?;
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(2);
        loop {
            if let Some(exit) = child.try_wait().map_err(err)? {
                if signaled(&exit) && attempt == 0 {
                    thread::sleep(std::time::Duration::from_secs(2));
                    break;
                }
                if signaled(&exit) {
                    app.state::<Runtime>()
                        .storage
                        .log("engine terminated by signal");
                    return Err(QUARANTINE_ENGINE_MESSAGE.into());
                }
                return Ok(child);
            }
            if std::time::Instant::now() >= deadline {
                return Ok(child);
            }
            thread::sleep(std::time::Duration::from_millis(50));
        }
    }
    Err(QUARANTINE_ENGINE_MESSAGE.into())
}
// 환경 명령은 shell 실행 없이 인자로 분리한다. 따옴표/공백 경로 지원.
pub fn split_command(s: &str) -> Result<Vec<String>, String> {
    let mut words = vec![];
    let mut word = String::new();
    let mut quote = None;
    let mut escape = false;
    for c in s.chars() {
        if escape {
            word.push(c);
            escape = false;
            continue;
        }
        if c == '\\' && quote != Some('\'') {
            escape = true;
            continue;
        }
        if let Some(q) = quote {
            if c == q {
                quote = None
            } else {
                word.push(c)
            }
        } else if c == '\'' || c == '"' {
            quote = Some(c)
        } else if c.is_whitespace() {
            if !word.is_empty() {
                words.push(std::mem::take(&mut word));
            }
        } else {
            word.push(c)
        }
    }
    if quote.is_some() || escape {
        return Err("VNOTE_ENGINE_CMD 따옴표 오류".into());
    }
    if !word.is_empty() {
        words.push(word)
    }
    if words.is_empty() {
        return Err("엔진이 설치되지 않았습니다".into());
    }
    Ok(words)
}
pub fn binary(app: &AppHandle, name: &str) -> Result<std::path::PathBuf, String> {
    let exe = std::env::current_exe().map_err(err)?;
    let mut paths = vec![exe.parent().unwrap().join(name)];
    if cfg!(debug_assertions) {
        paths.push(
            std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                .join(format!("binaries/{name}-aarch64-apple-darwin")),
        );
    }
    if let Ok(resource) = app.path().resource_dir() {
        paths.push(resource.join(name));
    }
    paths
        .into_iter()
        .find(|p| p.is_file())
        .ok_or("엔진이 설치되지 않았습니다".into())
}
pub fn command(app: &AppHandle, s: &Storage) -> Result<Command, String> {
    let override_cmd = std::env::var("VNOTE_ENGINE_CMD").ok();
    let mut cmd = if let Some(v) = override_cmd {
        let parts = split_command(&v)?;
        let mut c = Command::new(&parts[0]);
        c.args(&parts[1..]);
        c
    } else {
        Command::new(
            app.path()
                .resource_dir()
                .map_err(err)?
                .join("vnote-engine/vnote-engine"),
        )
    };
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        cmd.process_group(0);
    }
    cmd.env("VNOTE_DATA_DIR", &s.root)
        .env("HF_HOME", s.root.join("models"))
        .env("TMPDIR", s.root.join("tmp"))
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    if let Ok(fluid) = std::env::var("VNOTE_FLUID_BIN") {
        cmd.env("VNOTE_FLUID_BIN", fluid);
    } else if let Ok(fluid) = binary(app, "fluidaudiocli") {
        cmd.env("VNOTE_FLUID_BIN", fluid);
    }
    Ok(cmd)
}
pub fn parse_json_line(s: &str) -> Result<Value, String> {
    let value: Value = serde_json::from_str(s).map_err(err)?;
    if !value.is_object() {
        return Err("JSON 객체 필요".into());
    }
    Ok(value)
}
pub fn stderr(app: AppHandle, reader: impl std::io::Read + Send + 'static) {
    thread::spawn(move || {
        for line in BufReader::new(reader).lines() {
            let Ok(line) = line else { break };
            if line.starts_with("[diarize] skipped:") {
                app.state::<Runtime>().storage.log(&line);
                continue;
            }
            // stderr에는 라이브러리가 대본/용어를 출력할 수도 있어 원문은 남기지 않는다.
            // 예외 종류와 알려진 처리 단계만 기록한다.
            app.state::<Runtime>().storage.log(&stderr_category(&line));
        }
    });
}
fn stderr_category(line: &str) -> String {
    let head = line.split(':').next().unwrap_or("").trim();
    if (head.ends_with("Error") || head.ends_with("Exception"))
        && head.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
    {
        return format!("engine stderr: {head} (내용 생략)");
    }
    for stage in ["convert", "diarize", "asr", "merge"] {
        if line.starts_with(&format!("[{stage}]")) {
            return format!("engine stderr: {stage} (내용 생략)");
        }
    }
    "engine stderr (내용 생략)".into()
}
pub fn terms(s: &Storage, note_id: &str, key: &str) -> Result<(String, String), String> {
    let d = s.data.lock().map_err(err)?;
    let note = d
        .notes
        .iter()
        .find(|n| n.id == note_id)
        .ok_or("노트 없음")?;
    let p = d
        .projects
        .iter()
        .find(|p| p.id == note.project_id)
        .ok_or("프로젝트 없음")?;
    let mut list = vec![];
    for t in p.terms.iter().chain(note.terms.iter()) {
        let t = t.trim();
        if !t.is_empty()
            && !list
                .iter()
                .any(|x: &String| x.to_lowercase() == t.to_lowercase())
        {
            list.push(t.to_string());
        }
        if list.len() >= 80 {
            break;
        }
    }
    let file = s.root.join("tmp").join(format!("{key}-terms.txt"));
    atomic(&file, list.join("\n").as_bytes())?;
    Ok((file.to_string_lossy().into(), p.language.clone()))
}
pub fn notify(app: &AppHandle) {
    let _ = app.emit("data-changed", ());
}
pub fn init(app: AppHandle) -> Engine {
    let (tx, rx) = mpsc::channel::<String>();
    thread::spawn(move || {
        for id in rx {
            let state = app.state::<Runtime>();
            if state.engine.closing.load(Ordering::SeqCst) {
                break;
            }
            let result = transcribe(&app, &state.storage, &id);
            if let Err(e) = result {
                let mut d = state.storage.data.lock().unwrap();
                if let Some(r) = d.recordings.iter_mut().find(|r| r.id == id) {
                    r.status = "failed".into();
                    r.error = Some("녹음 처리가 실패했습니다. 로그를 확인한 뒤 다시 처리하세요.".into());
                }
                let _ = state.storage.save(&d);
                state.storage.log(&format!("transcribe failed: {e}"));
                notify(&app);
            }
        }
    });
    Engine {
        queue: tx,
        processes: Mutex::new(Vec::new()),
        closing: AtomicBool::new(false),
        downloads: Mutex::new(false),
    }
}
fn transcribe(app: &AppHandle, s: &Storage, id: &str) -> Result<(), String> {
    let r = {
        let mut d = s.data.lock().map_err(err)?;
        let r = d
            .recordings
            .iter_mut()
            .find(|r| r.id == id)
            .ok_or("녹음 없음")?;
        r.status = "processing".into();
        r.error = None;
        let r = r.clone();
        s.save(&d)?;
        r
    };
    notify(app);
    let (file, lang) = terms(s, &r.note_id, id)?;
    let result = (|| {
        let mut command = command(app, s)?;
        command.args([
            "transcribe",
            &r.path,
            "--json-progress",
            "--out",
            s.root.join("transcripts").to_str().unwrap(),
            "--terms-file",
            &file,
            "--language",
            &lang,
        ]);
        let mut child = spawn_with_retry(app, command)?;
        stderr(app.clone(), child.stderr.take().unwrap());
        let stdout = child.stdout.take().unwrap();
        let child = track(app, child)?;
        let mut output = None;
        let mut failure = None;
        for line in BufReader::new(stdout).lines() {
            let msg = match line.map_err(err).and_then(|l| parse_json_line(&l)) {
                Ok(v) => v,
                Err(e) => {
                    terminate(&child);
                    return Err(e);
                }
            };
            let _ = app.emit("engine-progress", json!({"id":id,"message":msg}));
            if msg["stage"] == "done" {
                output = msg["output"].as_str().map(str::to_owned);
            }
            if msg["stage"] == "error" {
                failure = Some(msg["message"].as_str().unwrap_or("처리 실패").to_owned());
            }
        }
        let exit = wait(&child)?;
        if let Some(e) = failure {
            return Err(e);
        }
        if !exit.success() {
            return Err(if signaled(&exit) {
                QUARANTINE_ENGINE_MESSAGE.into()
            } else {
                "엔진 종료 오류".into()
            });
        }
        let path = s.owned(&output.ok_or("엔진 결과 없음")?)?;
        let md = std::fs::read_to_string(&path).map_err(err)?;
        let duration = md.lines().find_map(|l| {
            l.strip_prefix("duration: ")
                .and_then(crate::storage::seconds)
        });
        let mut d = s.data.lock().map_err(err)?;
        let r = d
            .recordings
            .iter_mut()
            .find(|r| r.id == id)
            .ok_or("녹음 없음")?;
        r.transcript = Some(path.to_string_lossy().into());
        r.status = "done".into();
        if let Some(t) = duration {
            r.duration = t;
        }
        s.save(&d)?;
        notify(app);
        Ok(())
    })();
    let _ = std::fs::remove_file(file);
    result
}
// 자식 프로세스를 공유하여 종료·파싱 오류에도 정리한다.
pub fn track(app: &AppHandle, child: Child) -> Result<Arc<Mutex<Child>>, String> {
    let state = app.state::<Runtime>();
    let mut processes = state.engine.processes.lock().map_err(err)?;
    let child = Arc::new(Mutex::new(child));
    if state.engine.closing.load(Ordering::SeqCst) {
        terminate(&child);
        return Err("앱 종료 중".into());
    }
    processes.retain(|p| {
        p.lock()
            .ok()
            .and_then(|mut c| c.try_wait().ok().flatten())
            .is_none()
    });
    processes.push(child.clone());
    Ok(child)
}
pub fn kill_child(child: &mut Child) {
    #[cfg(unix)]
    {
        // Python의 FluidAudio 하위 프로세스도 같은 그룹에서 함께 끝낸다.
        let _ = Command::new("/bin/kill")
            .args(["-TERM", "--", &format!("-{}", child.id())])
            .status();
    }
    let _ = child.kill();
}
pub fn terminate(child: &Arc<Mutex<Child>>) {
    if let Ok(mut child) = child.lock() {
        kill_child(&mut child);
        let _ = child.wait();
    }
}
pub fn wait(child: &Arc<Mutex<Child>>) -> Result<std::process::ExitStatus, String> {
    loop {
        if let Some(exit) = child.lock().map_err(err)?.try_wait().map_err(err)? {
            return Ok(exit);
        }
        thread::sleep(std::time::Duration::from_millis(25));
    }
}
pub fn shutdown(app: &AppHandle) {
    let state = app.state::<Runtime>();
    state.engine.closing.store(true, Ordering::SeqCst);
    for child in state.engine.processes.lock().unwrap().drain(..) {
        terminate(&child);
    }
}
pub fn start_live(
    app: &AppHandle,
    s: &Storage,
    id: &str,
    note: &str,
) -> Result<mpsc::Sender<Vec<f32>>, String> {
    let (file, lang) = terms(s, note, &format!("{id}-live"))?;
    let model = s.data.lock().map_err(err)?.settings.live_model.clone();
    // 파일을 먼저 만들므로 note_detail이 존재하지 않는 live 경로를 읽지 않는다.
    let path = s.root.join("live").join(format!("{id}.jsonl"));
    let mut output_file = std::fs::File::create(path).map_err(err)?;
    let result = (|| {
        let mut command = command(app, s)?;
        command
            .args(["live", "--model", &model, "--terms-file", &file, "--language", &lang])
            .stdin(Stdio::piped());
        let mut child = spawn_with_retry(app, command)?;
        stderr(app.clone(), child.stderr.take().unwrap());
        let stdin = child.stdin.take().unwrap();
        let stdout = child.stdout.take().unwrap();
        let child = track(app, child)?;
        let (tx, rx) = mpsc::channel::<Vec<f32>>();
        let handle = app.clone();
        thread::spawn(move || {
            let mut input = stdin;
            for pcm in rx {
                let bytes: Vec<u8> = pcm.iter().flat_map(|s| s.to_le_bytes()).collect();
                if input.write_all(&bytes).is_err() {
                    handle.state::<Runtime>().storage.log("live stdin closed");
                    break;
                }
            }
        });
        let handle = app.clone();
        let key = id.to_string();
        let terms_file = file.clone();
        thread::spawn(move || {
            let mut finished = false;
            for line in BufReader::new(stdout).lines().map_while(Result::ok) {
                match parse_json_line(&line) {
                    Ok(msg) => {
                        if msg["type"] == "done" || msg["type"] == "error" {
                            finished = true;
                        }
                        if writeln!(output_file, "{line}").is_err() {
                            handle.state::<Runtime>().storage.log("live save failed");
                        }
                        let _ = handle.emit("live-message", json!({"id":key,"message":msg}));
                    }
                    Err(_) => handle
                        .state::<Runtime>()
                        .storage
                        .log("live JSON parse failed"),
                }
            }
            let exit = wait(&child);
            if !finished || !exit.as_ref().is_ok_and(|s| s.success()) {
                handle.state::<Runtime>().storage.log("live process failed");
                let message = if exit.as_ref().is_ok_and(signaled) {
                    QUARANTINE_ENGINE_MESSAGE
                } else {
                    "실시간 엔진이 종료되었습니다. 녹음은 계속 저장됩니다."
                };
                let _ = handle.emit(
                    "live-message",
                    json!({"id":key,"message":{"type":"error","message":message}}),
                );
            }
            let _ = output_file.sync_all();
            let _ = std::fs::remove_file(terms_file);
            notify(&handle);
        });
        Ok(tx)
    })();
    if result.is_err() {
        let _ = std::fs::remove_file(file);
    }
    result
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn json_lines() {
        assert_eq!(
            parse_json_line("{\"stage\":\"asr\",\"progress\":0.4}").unwrap()["progress"],
            0.4
        );
        assert!(parse_json_line("[1]").is_err());
        assert!(parse_json_line("broken").is_err());
    }
    #[test]
    fn command_quotes() {
        assert_eq!(
            split_command("'/a b/python' /c/script.py").unwrap(),
            vec!["/a b/python", "/c/script.py"]
        );
        assert!(split_command("'bad").is_err());
    }
    #[test]
    fn detects_app_translocation_from_bundle_executable() {
        let exe = std::path::Path::new(
            "/private/var/folders/x/AppTranslocation/d/VNote.app/Contents/MacOS/VNote",
        );
        let bundle = bundle_path(exe).unwrap();
        assert!(is_translocated_path(&bundle));
        assert_eq!(
            bundle,
            std::path::PathBuf::from("/private/var/folders/x/AppTranslocation/d/VNote.app")
        );
        assert!(!is_translocated_path(std::path::Path::new(
            "/Applications/VNote.app"
        )));
    }
    #[test]
    fn classifies_app_locations() {
        assert_eq!(classify_app_path(std::path::Path::new("/private/var/folders/x/AppTranslocation/d/VNote.app")), AppLocation::Translocated);
        assert_eq!(classify_app_path(std::path::Path::new("/Volumes/VNote/VNote.app")), AppLocation::Volume);
        assert_eq!(classify_app_path(std::path::Path::new("/Applications/VNote.app")), AppLocation::Normal);
    }
    #[test]
    fn relaunch_is_limited_to_once_and_skips_dmg_paths() {
        let app = std::path::Path::new("/Applications/VNote.app");
        let dmg_app = std::path::Path::new("/Volumes/VNote/VNote.app");
        assert!(should_relaunch(app, false, true));
        assert!(!should_relaunch(app, true, true));
        assert!(!should_relaunch(app, false, false));
        assert!(!should_relaunch(dmg_app, false, true));
        assert!(!should_relaunch(std::path::Path::new("/Applications/VNote"), false, true));
    }
    #[test]
    fn classifies_signal_exit() {
        use std::os::unix::process::ExitStatusExt;
        assert!(signaled(&std::process::ExitStatus::from_raw(9)));
        assert!(!signaled(&std::process::ExitStatus::from_raw(0)));
    }
}

#[cfg(test)]
mod privacy_tests {
    use super::*;
    #[test]
    fn diagnostics_without_transcript() {
        assert_eq!(
            stderr_category("RuntimeError: 개인 대본"),
            "engine stderr: RuntimeError (내용 생략)"
        );
        assert_eq!(stderr_category("개인 대본"), "engine stderr (내용 생략)");
        assert!(!stderr_category("[asr] text=비공개").contains("비공개"));
    }
}
