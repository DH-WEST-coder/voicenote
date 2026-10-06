use tauri::{AppHandle,Manager};
use crate::{Runtime,storage::err};
#[tauri::command]
pub async fn check_update(app:AppHandle)->Result<Option<serde_json::Value>,String>{
 tauri::async_runtime::spawn_blocking(move||{let state=app.state::<Runtime>();let today=chrono::Local::now().format("%Y-%m-%d").to_string();{let mut d=state.storage.data.lock().map_err(err)?;if d.settings.update_checked==today{return Ok(None)}d.settings.update_checked=today;state.storage.save(&d)?;}
 // macOS 기본 curl 사용. 새 HTTP crate 없이 타임아웃·TLS 검증 유지.
 let output=match std::process::Command::new("/usr/bin/curl").args(["--fail","--silent","--max-time","8","-H","Accept: application/vnd.github+json","https://api.github.com/repos/DH-WEST-coder/vnote-releases/releases/latest"]).output(){Ok(o) if o.status.success()=>o,_=>return Ok(None)};
 let v:serde_json::Value=match serde_json::from_slice(&output.stdout){Ok(v)=>v,Err(_)=>return Ok(None)};let tag=v["tag_name"].as_str().unwrap_or("");let version=app.package_info().version.to_string();if newer(tag,&version){Ok(Some(v))}else{Ok(None)}}).await.map_err(err)?
}
fn newer(a:&str,b:&str)->bool{fn parse(s:&str)->Option<Vec<u64>>{s.trim_start_matches('v').split('.').map(str::parse).collect::<Result<Vec<_>,_>>().ok()}match(parse(a),parse(b)){(Some(a),Some(b))=>a>b,_=>false}}
#[cfg(test)]mod tests{use super::*;#[test]fn versions(){assert!(newer("v0.10.0","0.2.0"));assert!(!newer("v0.1.0","0.1.0"));assert!(!newer("draft","0.1.0"));}}
