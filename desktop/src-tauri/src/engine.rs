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
                    r.error = Some(e);
                }
                let _ = state.storage.save(&d);
                state.storage.log("transcribe failed");
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
        let mut child = command(app, s)?
            .args([
                "transcribe",
                &r.path,
                "--json-progress",
                "--out",
                s.root.join("transcripts").to_str().unwrap(),
                "--terms-file",
                &file,
                "--language",
                &lang,
            ])
            .spawn()
            .map_err(err)?;
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
            return Err("엔진 종료 오류".into());
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
    // 파일을 먼저 만들므로 note_detail이 존재하지 않는 live 경로를 읽지 않는다.
    let path = s.root.join("live").join(format!("{id}.jsonl"));
    let mut output_file = std::fs::File::create(path).map_err(err)?;
    let result = (|| {
        let mut child = command(app, s)?
            .args(["live", "--terms-file", &file, "--language", &lang])
            .stdin(Stdio::piped())
            .spawn()
            .map_err(err)?;
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
            if !finished || !exit.is_ok_and(|s| s.success()) {
                handle.state::<Runtime>().storage.log("live process failed");
                let _=handle.emit("live-message",json!({"id":key,"message":{"type":"error","message":"실시간 엔진이 종료되었습니다. 녹음은 계속 저장됩니다."}}));
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
