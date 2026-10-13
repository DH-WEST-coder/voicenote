use serde::{Deserialize, Serialize};
use std::{
    fs,
    io::Write,
    path::{Path, PathBuf},
    sync::Mutex,
};
use uuid::Uuid;

#[derive(Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct Project {
    pub id: String,
    pub name: String,
    pub language: String,
    pub terms: Vec<String>,
}
#[derive(Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct Material {
    pub id: String,
    pub name: String,
    pub path: String,
    pub text: String,
}
#[derive(Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct Note {
    pub id: String,
    pub project_id: String,
    pub title: String,
    pub created_at: String,
    pub recording_ids: Vec<String>,
    pub materials: Vec<Material>,
    pub terms: Vec<String>,
    pub speaker_names: std::collections::BTreeMap<String, String>,
}
#[derive(Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct Recording {
    pub id: String,
    pub note_id: String,
    pub path: String,
    pub status: String,
    pub transcript: Option<String>,
    pub live: Option<String>,
    pub duration: f64,
    pub error: Option<String>,
}
#[derive(Clone, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct Settings {
    pub onboarding_done: bool,
    pub live_enabled: bool,
    pub asr_model: String,
    pub live_model: String,
    pub theme: String,
    pub chat_provider: String,
    pub chat_model: String,
    pub chat_reasoning_effort: String,
    pub update_checked: String,
}
impl Default for Settings {
    fn default() -> Self {
        Self {
            onboarding_done: false,
            live_enabled: true,
            asr_model: "moona3k/mlx-qwen3-asr-1.7b-8bit".into(),
            live_model: "moona3k/mlx-qwen3-asr-0.6b-4bit".into(),
            theme: "system".into(),
            chat_provider: "chatgpt".into(),
            chat_model: String::new(),
            chat_reasoning_effort: "low".into(),
            update_checked: String::new(),
        }
    }
}
#[derive(Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct Data {
    pub projects: Vec<Project>,
    pub notes: Vec<Note>,
    pub recordings: Vec<Recording>,
    pub settings: Settings,
}
pub struct Storage {
    pub root: PathBuf,
    pub data: Mutex<Data>,
}
pub fn atomic(path: &Path, bytes: &[u8]) -> Result<(), String> {
    let parent = path.parent().ok_or("저장 경로 오류")?;
    fs::create_dir_all(parent).map_err(err)?;
    let tmp = parent.join(format!(".{}.tmp", Uuid::new_v4()));
    let result = (|| {
        let mut f = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&tmp)
            .map_err(err)?;
        f.write_all(bytes).map_err(err)?;
        f.sync_all().map_err(err)?;
        fs::rename(&tmp, path).map_err(err)?;
        fs::File::open(parent)
            .and_then(|f| f.sync_all())
            .map_err(err)
    })();
    if result.is_err() {
        let _ = fs::remove_file(tmp);
    }
    result
}
pub fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}
pub fn read_json<T: serde::de::DeserializeOwned + Default>(p: &Path) -> Result<T, String> {
    if !p.exists() {
        return Ok(T::default());
    }
    serde_json::from_slice(&fs::read(p).map_err(err)?).map_err(err)
}
pub fn id(value: &str) -> Result<(), String> {
    Uuid::parse_str(value)
        .map(|_| ())
        .map_err(|_| "잘못된 ID".into())
}
impl Storage {
    pub fn open(root: PathBuf) -> Result<Self, String> {
        for p in [
            "notes",
            "chats",
            "audio",
            "transcripts",
            "live",
            "materials",
            "models",
            "codex",
            "logs",
            "chat-scratch",
            "tmp",
        ] {
            fs::create_dir_all(root.join(p)).map_err(err)?;
        }
        let root = root.canonicalize().map_err(err)?;
        let mut data = Data {
            projects: read_json(&root.join("projects.json"))?,
            notes: read_json(&root.join("notes.json"))?,
            recordings: read_json(&root.join("recordings.json"))?,
            settings: read_json(&root.join("settings.json"))?,
        };
        for r in &mut data.recordings {
            if ["recording", "processing"].contains(&r.status.as_str()) {
                r.status = "failed".into();
                r.error = Some("앱 종료로 작업이 중단되었습니다. 다시 처리하세요.".into());
            }
        }
        Ok(Self {
            root,
            data: Mutex::new(data),
        })
    }
    pub fn save(&self, d: &Data) -> Result<(), String> {
        for (name, value) in [
            ("projects", serde_json::to_vec_pretty(&d.projects)),
            ("notes", serde_json::to_vec_pretty(&d.notes)),
            ("recordings", serde_json::to_vec_pretty(&d.recordings)),
            ("settings", serde_json::to_vec_pretty(&d.settings)),
        ] {
            atomic(
                &self.root.join(format!("{name}.json")),
                &value.map_err(err)?,
            )?;
        }
        Ok(())
    }
    pub fn owned(&self, p: &str) -> Result<PathBuf, String> {
        let p = PathBuf::from(p).canonicalize().map_err(err)?;
        let root = self.root.canonicalize().map_err(err)?;
        if !p.starts_with(root) {
            return Err("앱 데이터 밖 접근 금지".into());
        }
        Ok(p)
    }
    pub fn log(&self, category: &str) {
        if let Ok(mut f) = fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(self.root.join("logs/app.log"))
        {
            let _ = writeln!(f, "{} {}", chrono::Local::now().to_rfc3339(), category);
        }
    }
}
#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Line {
    pub time: f64,
    pub local_time: f64,
    pub recording_id: String,
    pub speaker: String,
    pub text: String,
}
pub fn seconds(s: &str) -> Option<f64> {
    let mut out = 0.;
    for part in s.split(':') {
        out = out * 60. + part.parse::<f64>().ok()?;
    }
    Some(out)
}
pub fn parse_md(md: &str, r: &str, offset: f64) -> Vec<Line> {
    md.lines()
        .filter_map(|l| {
            let l = l.strip_prefix('[')?;
            let (time, body) = l.split_once("] ")?;
            let local = seconds(time)?;
            let (speaker, text) = body.split_once(": ")?;
            Some(Line {
                time: offset + local,
                local_time: local,
                recording_id: r.into(),
                speaker: speaker.into(),
                text: text.into(),
            })
        })
        .collect()
}
pub fn offsets(rs: &[Recording]) -> Vec<f64> {
    let mut sum = 0.;
    rs.iter()
        .map(|r| {
            let o = sum;
            sum += r.duration.max(0.);
            o
        })
        .collect()
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn atomic_replace() {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../out/dist-test")
            .join(Uuid::new_v4().to_string());
        fs::create_dir_all(&root).unwrap();
        let p = root.join("x.json");
        atomic(&p, b"old").unwrap();
        atomic(&p, b"new").unwrap();
        assert_eq!(fs::read(&p).unwrap(), b"new");
        assert_eq!(fs::read_dir(&root).unwrap().count(), 1);
        fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn transcript_and_offsets() {
        let rs = vec![
            Recording {
                duration: 70.,
                ..Default::default()
            },
            Recording {
                duration: 50.,
                ..Default::default()
            },
        ];
        assert_eq!(offsets(&rs), vec![0., 70.]);
        let l = parse_md(
            "---\nduration: 2:00\n---\n[1:02:03] 화자2: 본문\n[0:05] 화자1: 다음",
            "id",
            70.,
        );
        assert_eq!(l[0].time, 3793.);
        assert_eq!(l[1].local_time, 5.);
        assert_eq!(l[0].speaker, "화자2");
    }
}

#[cfg(test)]
mod boundary_tests {
    use super::*;
    fn root() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../out/dist-test")
            .join(Uuid::new_v4().to_string())
    }
    #[test]
    fn recover_and_persist() {
        let root = root();
        let s = Storage::open(root.clone()).unwrap();
        let mut d = Data::default();
        d.recordings.push(Recording {
            status: "processing".into(),
            ..Default::default()
        });
        d.settings.live_enabled = false;
        s.save(&d).unwrap();
        let next = Storage::open(root.clone()).unwrap();
        let d = next.data.lock().unwrap();
        assert_eq!(d.recordings[0].status, "failed");
        assert!(d.recordings[0].error.is_some());
        assert!(!d.settings.live_enabled);
        assert_eq!(d.settings.asr_model, "moona3k/mlx-qwen3-asr-1.7b-8bit");
        assert_eq!(d.settings.live_model, "moona3k/mlx-qwen3-asr-0.6b-4bit");
        assert!(next
            .owned(root.join("../outside").to_str().unwrap())
            .is_err());
        fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn failed_atomic_write_cleans_temporary_file() {
        let root = root();
        fs::create_dir_all(root.join("target")).unwrap();
        assert!(atomic(&root.join("target"), b"new").is_err());
        assert_eq!(fs::read_dir(&root).unwrap().count(), 1);
        fs::remove_dir_all(root).unwrap();
    }
    #[cfg(unix)]
    #[test]
    fn symlink_cannot_escape_data() {
        let root = root();
        let s = Storage::open(root.join("data")).unwrap();
        atomic(&root.join("outside"), b"private").unwrap();
        std::os::unix::fs::symlink(root.join("outside"), s.root.join("audio/link.wav")).unwrap();
        assert!(s
            .owned(s.root.join("audio/link.wav").to_str().unwrap())
            .is_err());
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn settings_without_chat_provider_default_to_chatgpt() {
        let legacy = br#"{"onboardingDone":true,"liveEnabled":false,"asrModel":"a","liveModel":"b","theme":"dark","chatModel":"opus","chatReasoningEffort":"high","updateChecked":""}"#;
        let settings: Settings = serde_json::from_slice(legacy).unwrap();
        assert_eq!(settings.chat_provider, "chatgpt");
        let serialized = serde_json::to_value(Settings::default()).unwrap();
        assert_eq!(serialized["chatProvider"], "chatgpt");
    }

    #[test]
    fn model_choices_persist() {
        let root = root();
        let s = Storage::open(root.clone()).unwrap();
        let mut d = s.data.lock().unwrap();
        d.settings.asr_model = "moona3k/mlx-qwen3-asr-0.6b-4bit".into();
        d.settings.live_model = "moona3k/mlx-qwen3-asr-1.7b-8bit".into();
        s.save(&d).unwrap();
        drop(d);
        let loaded = Storage::open(root.clone()).unwrap();
        let d = loaded.data.lock().unwrap();
        assert_eq!(d.settings.asr_model, "moona3k/mlx-qwen3-asr-0.6b-4bit");
        assert_eq!(d.settings.live_model, "moona3k/mlx-qwen3-asr-1.7b-8bit");
        drop(d);
        fs::remove_dir_all(root).unwrap();
    }
}
