use crate::{chatgpt::parse_terms, engine, storage::err, Runtime};
use serde_json::{json, Value};
use std::{
    io::{BufRead, BufReader, Write},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::atomic::{AtomicBool, Ordering},
    thread,
};
use tauri::{AppHandle, Emitter, Manager};

#[derive(Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelOption {
    pub(crate) id: String,
    pub(crate) label: String,
    pub(crate) efforts: Vec<String>,
}

const MODELS: &[(&str, &str)] = &[
    ("sonnet", "Claude Sonnet"),
    ("opus", "Claude Opus"),
    ("haiku", "Claude Haiku"),
];

pub fn model_options() -> Vec<ModelOption> {
    MODELS
        .iter()
        .map(|(id, label)| ModelOption {
            id: (*id).into(),
            label: (*label).into(),
            efforts: vec!["low".into(), "medium".into(), "high".into()],
        })
        .collect()
}

fn candidate_paths(home: &Path) -> Vec<PathBuf> {
    vec![
        home.join(".local/bin/claude"),
        PathBuf::from("/opt/homebrew/bin/claude"),
        PathBuf::from("/usr/local/bin/claude"),
        home.join(".claude/local/claude"),
    ]
}

fn find_cli_with<F>(home: &Path, mut is_file: F) -> Option<PathBuf>
where
    F: FnMut(&Path) -> bool,
{
    candidate_paths(home).into_iter().find(|path| is_file(path))
}

fn claude_path() -> Result<PathBuf, String> {
    let home = dirs::home_dir().ok_or("사용자 홈 경로를 찾을 수 없습니다")?;
    if let Some(path) = find_cli_with(&home, Path::is_file) {
        return Ok(path);
    }
    let output = Command::new("/bin/zsh")
        .args(["-lc", "command -v claude"])
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .map_err(|_| {
            "Claude Code가 설치돼 있지 않습니다. 설정에서 'Claude에 연결'을 누르세요.".to_string()
        })?;
    if output.status.success() {
        let path = String::from_utf8_lossy(&output.stdout).trim().to_owned();
        if !path.is_empty() {
            return Ok(PathBuf::from(path));
        }
    }
    Err("Claude Code가 설치돼 있지 않습니다. 설정에서 'Claude에 연결'을 누르세요.".into())
}

fn cli_command() -> Result<Command, String> {
    Ok(Command::new(claude_path()?))
}

fn status_result(bytes: &[u8]) -> bool {
    serde_json::from_slice::<Value>(bytes)
        .ok()
        .and_then(|v| v["loggedIn"].as_bool())
        .unwrap_or(false)
}

pub async fn chat_status(_app: AppHandle) -> Result<bool, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let output = cli_command()?
            .args(["auth", "status"])
            .stdin(Stdio::null())
            .stderr(Stdio::null())
            .output()
            .map_err(err)?;
        Ok(status_result(&output.stdout))
    })
    .await
    .map_err(err)?
}

pub async fn chat_models() -> Vec<ModelOption> {
    model_options()
}

static SETUP_RUNNING: AtomicBool = AtomicBool::new(false);

fn shell_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}

fn apple_script_quote(value: &str) -> String {
    value.replace('\\', "\\\\").replace('"', "\\\"")
}

fn login_script(path: &Path) -> String {
    let invocation = format!("{} auth login", shell_quote(&path.to_string_lossy()));
    format!(
        "tell application \"Terminal\" to do script \"{}\"",
        apple_script_quote(&invocation)
    )
}

#[cfg(target_os = "macos")]
fn open_login_terminal(path: &Path) -> Result<(), String> {
    Command::new("osascript")
        .args([
            "-e",
            "tell application \"Terminal\" to activate",
            "-e",
            &login_script(path),
        ])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map(|_| ())
        .map_err(|_| "로그인 터미널을 열지 못했습니다. 터미널에서 claude를 실행해 로그인하세요.".to_string())
}

#[cfg(not(target_os = "macos"))]
fn open_login_terminal(_path: &Path) -> Result<(), String> {
    Err("이 운영체제에서는 터미널에서 claude를 실행해 로그인하세요.".into())
}

fn install_cli() -> Result<(), String> {
    let status = Command::new("/bin/bash")
        .args(["-lc", "curl -fsSL https://claude.ai/install.sh | bash"])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map_err(|_| "Claude Code 설치를 시작하지 못했습니다.".to_string())?;
    if status.success() {
        Ok(())
    } else {
        Err("Claude Code 설치에 실패했습니다. 인터넷 연결을 확인한 뒤 다시 시도하세요.".into())
    }
}

fn setup_event(app: &AppHandle, step: &str, message: &str) {
    let _ = app.emit("claude-setup", json!({ "step": step, "message": message }));
}

/// 설치돼 있으면 로그인 터미널을 열고, 없으면 먼저 설치한다. 연결 여부는 앱의 상태 폴링이 감지한다.
pub fn chat_login(app: AppHandle) -> Result<(), String> {
    if let Ok(path) = claude_path() {
        open_login_terminal(&path)?;
        setup_event(&app, "login", "터미널에서 로그인을 마치세요.");
        return Ok(());
    }
    if SETUP_RUNNING.swap(true, Ordering::SeqCst) {
        return Ok(());
    }
    thread::spawn(move || {
        setup_event(&app, "installing", "Claude Code를 설치하는 중입니다…");
        let result = install_cli()
            .and_then(|_| claude_path())
            .and_then(|path| open_login_terminal(&path));
        match result {
            Ok(()) => setup_event(&app, "login", "터미널에서 로그인을 마치세요."),
            Err(message) => setup_event(&app, "error", &message),
        }
        SETUP_RUNNING.store(false, Ordering::SeqCst);
    });
    Ok(())
}

pub fn chat_logout() -> Result<(), String> {
    Err("Claude 연결 해제는 터미널에서 직접 관리하세요.".into())
}

fn parse_stream_event(line: &str) -> Result<StreamEvent, String> {
    let value: Value = serde_json::from_str(line).map_err(err)?;
    let kind = value["type"].as_str().unwrap_or("");
    let text = if kind == "assistant" {
        value["message"]["content"]
            .as_array()
            .into_iter()
            .flatten()
            .filter(|block| block["type"] == "text")
            .filter_map(|block| block["text"].as_str())
            .collect::<Vec<_>>()
            .join("")
    } else {
        String::new()
    };
    let error = (kind == "result" && value["is_error"].as_bool() == Some(true)).then(|| {
        value["result"]
            .as_str()
            .unwrap_or("Claude Code 실행 오류")
            .to_owned()
    });
    Ok(StreamEvent { text, error })
}

struct StreamEvent {
    text: String,
    error: Option<String>,
}

fn effort_arg(effort: &str) -> &'static str {
    match effort {
        "medium" => "medium",
        "high" => "high",
        _ => "low",
    }
}

pub fn chat_ask(
    app: AppHandle,
    note_id: String,
    prompt: String,
    request_id: String,
    terms: bool,
) -> Result<(), String> {
    crate::storage::id(&note_id)?;
    let state = app.state::<Runtime>();
    let mut busy = state.chat.busy.lock().map_err(err)?;
    if *busy {
        return Err("AI 응답 처리 중".into());
    }
    let settings = state.storage.data.lock().map_err(err)?.settings.clone();
    let scratch = state.storage.root.join("chat-scratch");
    let mut command = cli_command()?;
    command.args([
        "-p",
        "--output-format",
        "stream-json",
        "--verbose",
        "--no-session-persistence",
        "--tools",
        "",
        "--strict-mcp-config",
        "--disable-slash-commands",
        "--setting-sources",
        "",
    ]);
    if !settings.chat_model.is_empty() {
        command.args(["--model", &settings.chat_model]);
    }
    command
        .args(["--effort", effort_arg(&settings.chat_reasoning_effort)])
        .current_dir(scratch)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        command.process_group(0);
    }
    let mut child = command.spawn().map_err(|e| {
        if e.kind() == std::io::ErrorKind::NotFound {
            "Claude Code가 설치돼 있지 않습니다".into()
        } else {
            err(e)
        }
    })?;
    let mut input = child.stdin.take().ok_or("Claude stdin을 열 수 없습니다")?;
    let stdout = child
        .stdout
        .take()
        .ok_or("Claude 출력을 읽을 수 없습니다")?;
    engine::stderr(
        app.clone(),
        child
            .stderr
            .take()
            .ok_or("Claude 오류 출력을 읽을 수 없습니다")?,
    );
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
                let event = parse_stream_event(&line.map_err(err)?)?;
                if let Some(error) = event.error {
                    return Err(error);
                }
                if !event.text.is_empty() {
                    if !text.is_empty() {
                        text.push_str("\n\n");
                    }
                    text.push_str(&event.text);
                    let _ = app.emit(
                        "chat-message",
                        json!({"noteId":note_id,"requestId":request_id,"text":event.text}),
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
                return Err("중지됨 또는 Claude Code 실행 실패".into());
            }
            if text.is_empty() {
                return Err("Claude가 빈 응답을 보냈습니다".into());
            }
            Ok(text)
        })();
        let state = app.state::<Runtime>();
        if let Some(mut child) = state.chat.child.lock().unwrap().take() {
            engine::kill_child(&mut child);
            let _ = child.wait();
        }
        let mut result = if state.chat.stopped.load(Ordering::SeqCst) {
            Err("중지됨".into())
        } else {
            result
        };
        if terms {
            result = result.and_then(|text| {
                let clean = parse_terms(&text)?;
                let mut data = state.storage.data.lock().map_err(err)?;
                let note = data
                    .notes
                    .iter_mut()
                    .find(|note| note.id == note_id)
                    .ok_or("노트 없음")?;
                note.terms = clean;
                state.storage.save(&data)?;
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_auth_status() {
        assert!(status_result(br#"{"loggedIn":true}"#));
        assert!(!status_result(br#"{"loggedIn":false}"#));
        assert!(!status_result(b"bad json"));
    }

    #[test]
    fn parses_assistant_text_and_result_errors() {
        let event = parse_stream_event(r#"{"type":"assistant","message":{"content":[{"type":"text","text":"Hi"},{"type":"thinking","thinking":"hidden"},{"type":"text","text":" there"}]}}"#).unwrap();
        assert_eq!(event.text, "Hi there");
        assert!(event.error.is_none());
        let event =
            parse_stream_event(r#"{"type":"result","is_error":true,"result":"failure"}"#).unwrap();
        assert_eq!(event.error.as_deref(), Some("failure"));
        assert!(parse_stream_event("not json").is_err());
    }

    #[test]
    fn cli_path_candidates_are_in_priority_order() {
        let home = Path::new("/home/test");
        assert_eq!(
            candidate_paths(home),
            vec![
                PathBuf::from("/home/test/.local/bin/claude"),
                PathBuf::from("/opt/homebrew/bin/claude"),
                PathBuf::from("/usr/local/bin/claude"),
                PathBuf::from("/home/test/.claude/local/claude"),
            ]
        );
        let found = find_cli_with(home, |path| path == Path::new("/usr/local/bin/claude"));
        assert_eq!(found, Some(PathBuf::from("/usr/local/bin/claude")));
    }

    #[test]
    fn fixed_models_have_effort_choices() {
        let models = model_options();
        assert_eq!(models.len(), 3);
        assert_eq!(models[0].id, "sonnet");
        assert_eq!(models[1].id, "opus");
        assert_eq!(models[2].id, "haiku");
        assert_eq!(models[0].efforts, ["low", "medium", "high"]);
    }

    #[test]
    fn login_script_quotes_path_for_shell_and_applescript() {
        let script = login_script(Path::new("/Users/a b/it's/claude"));
        assert!(script.contains("auth login"));
        assert!(script.contains("'/Users/a b/it'\\\\''s/claude'") || script.contains("it'\\\\''s"));
    }
}
