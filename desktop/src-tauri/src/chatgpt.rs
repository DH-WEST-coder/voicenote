//! 개발용 Codex 자체 로그인. 정식 OAuth로 교체할 경계를 이 모듈에 둔다.
use crate::{
    engine,
    storage::{atomic, err, id},
    Runtime,
};
use serde_json::{json, Value};
use std::{
    io::{BufRead, BufReader, Write},
    process::{Child, Command, Stdio},
    sync::{
        atomic::{AtomicBool, Ordering},
        Mutex,
    },
    thread,
};
use tauri::{AppHandle, Emitter, Manager};
pub struct Chat {
    pub child: Mutex<Option<Child>>,
    pub busy: Mutex<bool>,
    pub login: Mutex<Option<Child>>,
    pub stopped: AtomicBool,
}
impl Default for Chat {
    fn default() -> Self {
        Self {
            child: Mutex::new(None),
            busy: Mutex::new(false),
            login: Mutex::new(None),
            stopped: AtomicBool::new(false),
        }
    }
}
fn command(app: &AppHandle) -> Result<Command, String> {
    let state = app.state::<Runtime>();
    let mut c = Command::new(engine::binary(app, "codex")?);
    let home = if cfg!(debug_assertions) {
        std::env::var_os("VNOTE_CODEX_HOME")
            .map(std::path::PathBuf::from)
            .unwrap_or(state.storage.root.join("codex"))
    } else {
        state.storage.root.join("codex")
    };
    std::fs::create_dir_all(&home).map_err(err)?;
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        c.process_group(0);
    }
    c.env_remove("OPENAI_API_KEY")
        .env_remove("CODEX_API_KEY")
        .env_remove("OPENAI_BASE_URL")
        .env("CODEX_HOME", home)
        .env("TMPDIR", state.storage.root.join("tmp"))
        .current_dir(state.storage.root.join("chat-scratch"))
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    Ok(c)
}
#[tauri::command]
pub async fn chat_status(app: AppHandle) -> Result<bool, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let result = command(&app)?
            .args(["login", "status"])
            .output()
            .map_err(err)?;
        Ok(result.status.success())
    })
    .await
    .map_err(err)?
}
#[tauri::command]
pub fn chat_login(app: AppHandle) -> Result<(), String> {
    let state = app.state::<Runtime>();
    let mut login = state.chat.login.lock().map_err(err)?;
    if let Some(c) = login.as_mut() {
        if c.try_wait().map_err(err)?.is_none() {
            return Ok(());
        }
    }
    let mut c = command(&app)?.arg("login").spawn().map_err(err)?;
    engine::stderr(app.clone(), c.stderr.take().unwrap());
    let out = c.stdout.take().unwrap();
    thread::spawn(move || for _ in BufReader::new(out).lines() {});
    *login = Some(c);
    Ok(())
}
#[tauri::command]
pub async fn chat_logout(app: AppHandle) -> Result<(), String> {
    tauri::async_runtime::spawn_blocking(move || {
        chat_stop(app.clone())?;
        let state = app.state::<Runtime>();
        if let Some(mut c) = state.chat.login.lock().map_err(err)?.take() {
            engine::kill_child(&mut c);
            let _ = c.wait();
        }
        let result = command(&app)?.arg("logout").output().map_err(err)?;
        if result.status.success() {
            Ok(())
        } else {
            Err("연결 해제 실패".into())
        }
    })
    .await
    .map_err(err)?
}
#[tauri::command]
pub fn chat_stop(app: AppHandle) -> Result<(), String> {
    let state = app.state::<Runtime>();
    state.chat.stopped.store(true, Ordering::SeqCst);
    if let Some(c) = state.chat.child.lock().map_err(err)?.as_mut() {
        engine::kill_child(c);
    }
    Ok(())
}
#[tauri::command]
pub fn chat_ask(
    app: AppHandle,
    note_id: String,
    prompt: String,
    request_id: String,
    terms: bool,
) -> Result<(), String> {
    id(&note_id)?;
    let state = app.state::<Runtime>();
    let mut busy = state.chat.busy.lock().map_err(err)?;
    if *busy {
        return Err("AI 응답 처리 중".into());
    }
    let model = state
        .storage
        .data
        .lock()
        .map_err(err)?
        .settings
        .chat_model
        .clone();
    let scratch = state.storage.root.join("chat-scratch");
    let mut cmd = command(&app)?;
    cmd.args([
        "exec",
        "--json",
        "-s",
        "read-only",
        "--skip-git-repo-check",
        "--ephemeral",
        "-c",
        "model_reasoning_effort=\"low\"",
        "-C",
        scratch.to_str().unwrap(),
    ]);
    if !model.is_empty() {
        cmd.args(["-m", &model]);
    }
    cmd.arg("-").stdin(Stdio::piped());
    let mut child = cmd.spawn().map_err(err)?;
    let mut input = child.stdin.take().unwrap();
    let stdout = child.stdout.take().unwrap();
    engine::stderr(app.clone(), child.stderr.take().unwrap());
    *state.chat.child.lock().map_err(err)? = Some(child);
    state.chat.stopped.store(false, Ordering::SeqCst);
    *busy = true;
    drop(busy);
    thread::spawn(move || {
        let result = (|| -> Result<String, String> {
            input.write_all(prompt.as_bytes()).map_err(err)?;
            drop(input);
            let mut text = String::new();
            for line in BufReader::new(stdout).lines() {
                if let Some(t) = agent_message(&line.map_err(err)?)? {
                    if !text.is_empty() {
                        text.push_str("\n\n");
                    }
                    text.push_str(&t);
                    let _ = app.emit(
                        "chat-message",
                        json!({"noteId":note_id,"requestId":request_id,"text":t}),
                    );
                }
            }
            let state = app.state::<Runtime>();
            let mut child = state
                .chat
                .child
                .lock()
                .map_err(err)?
                .take()
                .ok_or("채팅 프로세스 없음")?;
            let status = child.wait().map_err(err)?;
            if !status.success() {
                return Err("중지됨 또는 ChatGPT 실행 실패".into());
            }
            if text.is_empty() {
                return Err("ChatGPT가 빈 응답을 보냈습니다".into());
            }
            Ok(text)
        })();
        let state = app.state::<Runtime>();
        if let Some(mut c) = state.chat.child.lock().unwrap().take() {
            engine::kill_child(&mut c);
            let _ = c.wait();
        }
        let mut result = if state.chat.stopped.load(Ordering::SeqCst) {
            Err("중지됨".into())
        } else {
            result
        };
        if terms {
            result = result.and_then(|text| {
                let clean = parse_terms(&text)?;
                let mut d = state.storage.data.lock().map_err(err)?;
                let n = d
                    .notes
                    .iter_mut()
                    .find(|n| n.id == note_id)
                    .ok_or("노트 없음")?;
                n.terms = clean;
                state.storage.save(&d)?;
                engine::notify(&app);
                Ok(text)
            });
        }
        *state.chat.busy.lock().unwrap() = false;
        let error = result.err();
        if error.is_some() {
            state.storage.log("chat failed");
        }
        let _ = app.emit(
            "chat-message",
            json!({"noteId":note_id,"requestId":request_id,"done":true,"error":error}),
        );
    });
    Ok(())
}
#[tauri::command]
pub fn save_chat(app: AppHandle, note_id: String, messages: Value) -> Result<(), String> {
    id(&note_id)?;
    atomic(
        &app.state::<Runtime>()
            .storage
            .root
            .join("chats")
            .join(format!("{note_id}.json")),
        &serde_json::to_vec(&messages).map_err(err)?,
    )
}

pub fn parse_terms(text: &str) -> Result<Vec<String>, String> {
    let a = text
        .find('[')
        .ok_or("AI 답에서 용어 목록을 읽지 못했습니다")?;
    let b = text
        .rfind(']')
        .ok_or("AI 답에서 용어 목록을 읽지 못했습니다")?;
    if a > b {
        return Err("AI 용어 형식 오류".into());
    }
    let list: Vec<String> = serde_json::from_str(&text[a..=b]).map_err(|_| "AI 용어 형식 오류")?;
    let mut clean = vec![];
    for t in list {
        let t = t.split_whitespace().collect::<Vec<_>>().join(" ");
        if !t.is_empty()
            && t.chars().count() <= 60
            && !clean
                .iter()
                .any(|x: &String| x.to_lowercase() == t.to_lowercase())
        {
            clean.push(t);
        }
        if clean.len() >= 80 {
            break;
        }
    }
    if clean.is_empty() {
        return Err("자료에서 전공 용어를 찾지 못했습니다".into());
    }
    Ok(clean)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn terms_validation() {
        assert_eq!(
            parse_terms("```json\n[\" PWM \",\"pwm\",\"PI   제어기\"]\n```").unwrap(),
            vec!["PWM", "PI 제어기"]
        );
        assert!(parse_terms("no JSON").is_err());
        assert!(parse_terms("[]").is_err());
        let list: Vec<String> = (0..100).map(|i| format!("term{i}")).collect();
        assert_eq!(
            parse_terms(&serde_json::to_string(&list).unwrap())
                .unwrap()
                .len(),
            80
        );
    }
}

/// Swift 참고 구현과 같은 exec JSONL 경계: 완성된 agent_message마다 전달한다.
fn agent_message(line: &str) -> Result<Option<String>, String> {
    let msg = engine::parse_json_line(line)?;
    if msg["type"] == "error" || msg["type"] == "turn.failed" {
        return Err("ChatGPT 응답 오류. 로그인 상태와 네트워크를 확인하세요.".into());
    }
    if msg["type"] == "item.completed" && msg["item"]["type"] == "agent_message" {
        return Ok(msg["item"]["text"].as_str().map(str::to_owned));
    }
    Ok(None)
}
#[cfg(test)]
mod message_tests {
    use super::*;
    #[test]
    fn exec_message_contract() {
        assert_eq!(
            agent_message(
                r#"{"type":"item.completed","item":{"type":"agent_message","text":"설명"}}"#
            )
            .unwrap(),
            Some("설명".into())
        );
        assert_eq!(
            agent_message(r#"{"type":"item.completed","item":{"type":"reasoning","text":"생각"}}"#)
                .unwrap(),
            None
        );
        assert!(agent_message(r#"{"type":"turn.failed"}"#).is_err());
        assert!(agent_message("bad JSON").is_err());
    }
}
