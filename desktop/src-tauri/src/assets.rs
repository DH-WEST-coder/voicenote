//! 추가 crate 없이 제공하는 앱 전용 asset 프로토콜. 오디오/PDF만 노출한다.
use crate::{storage::{err, Storage}, Runtime};
use std::{fs::File, io::{Read, Seek, SeekFrom}};
use tauri::{http::{Request, Response}, Manager};

fn decode_path(raw: &str) -> Result<String, String> {
    let raw = raw.trim_start_matches('/').as_bytes();
    let mut bytes = Vec::new();
    let mut i = 0;
    while i < raw.len() {
        if raw[i] == b'%' {
            let hex = raw.get(i + 1..i + 3).ok_or("잘못된 경로")?;
            bytes.push(u8::from_str_radix(std::str::from_utf8(hex).map_err(err)?, 16).map_err(err)?);
            i += 3;
        } else { bytes.push(raw[i]); i += 1; }
    }
    Ok(format!("/{}", String::from_utf8(bytes).map_err(err)?))
}
fn byte_range(value: &str, len: u64) -> Result<(u64, u64), String> {
    let value = value.strip_prefix("bytes=").ok_or("range")?;
    let (a, b) = value.split_once('-').ok_or("range")?;
    if len == 0 || value.contains(',') { return Err("range".into()); }
    let start = if a.is_empty() {
        let suffix = b.parse::<u64>().map_err(err)?;
        if suffix == 0 { return Err("range".into()); }
        len.saturating_sub(suffix)
    } else { a.parse::<u64>().map_err(err)? };
    let end = if a.is_empty() || b.is_empty() { len - 1 } else { b.parse::<u64>().map_err(err)?.min(len - 1) };
    if start > end || start >= len { return Err("range".into()); }
    Ok((start, end))
}
fn response(storage: &Storage, req: &Request<Vec<u8>>) -> Result<Response<Vec<u8>>, String> {
    let path = storage.owned(&decode_path(req.uri().path())?)?;
    let root = storage.root.canonicalize().map_err(err)?;
    if !path.starts_with(root.join("audio")) && !path.starts_with(root.join("materials")) {
        return Err("미디어 폴더 밖 접근 금지".into());
    }
    let mime = match path.extension().and_then(|s|s.to_str()).unwrap_or("") {
        "pdf" => "application/pdf", "wav" => "audio/wav", "mp3" => "audio/mpeg",
        "m4a" | "mp4" => "audio/mp4", "aac" => "audio/aac", "flac" => "audio/flac",
        "ogg" | "opus" => "audio/ogg", "aiff" | "aif" => "audio/aiff", _ => return Err("지원하지 않는 미디어".into())
    };
    let mut file = File::open(path).map_err(err)?;
    let len = file.metadata().map_err(err)?.len();
    let mut builder = Response::builder().header("Content-Type", mime)
        .header("Access-Control-Allow-Origin", "*").header("Accept-Ranges", "bytes");
    let (start, length) = if let Some(range) = req.headers().get("range") {
        match byte_range(range.to_str().map_err(err)?, len) {
            Ok((start, end)) => {
                builder = builder.status(206).header("Content-Range", format!("bytes {start}-{end}/{len}"));
                (start, end - start + 1)
            },
            Err(_) => return Response::builder().status(416).header("Content-Range", format!("bytes */{len}"))
                .body(Vec::new()).map_err(err)
        }
    } else { (0, len) };
    builder = builder.header("Content-Length", length);
    let mut bytes = Vec::new();
    if req.method() != "HEAD" {
        file.seek(SeekFrom::Start(start)).map_err(err)?;
        file.take(length).read_to_end(&mut bytes).map_err(err)?;
    }
    builder.body(bytes).map_err(err)
}
pub fn serve(app: &tauri::AppHandle, req: &Request<Vec<u8>>) -> Response<Vec<u8>> {
    response(&app.state::<Runtime>().storage, req).unwrap_or_else(|_| {
        Response::builder().status(403).body(Vec::new()).unwrap()
    })
}
#[cfg(test)] mod tests {
    use super::*;
    #[test] fn range_forms() {
        assert_eq!(byte_range("bytes=3-5", 10).unwrap(), (3,5));
        assert_eq!(byte_range("bytes=3-", 10).unwrap(), (3,9));
        assert_eq!(byte_range("bytes=-4", 10).unwrap(), (6,9));
        assert_eq!(byte_range("bytes=0-99", 10).unwrap(), (0,9));
        for value in ["bytes=10-", "bytes=5-3", "bytes=-0", "bytes=0-1,3-4"] { assert!(byte_range(value,10).is_err()); }
    }
    #[test] fn percent_encoding() {
        assert_eq!(decode_path("/Users/a%20b/%ED%95%9C.wav").unwrap(), "/Users/a b/한.wav");
        assert!(decode_path("/bad%2").is_err());
    }
}

#[cfg(test)]mod protocol_tests{
 use super::*;
 #[test]fn media_scope_and_range(){
  let root=std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../out/dist-test").join(uuid::Uuid::new_v4().to_string());
  let storage=Storage::open(root.clone()).unwrap();let path=storage.root.join("audio/clip.wav");
  std::fs::write(&path,b"0123456789").unwrap();
  let req=Request::builder().uri(format!("asset://localhost{}",path.display())).header("Range","bytes=-3").body(Vec::new()).unwrap();
  let res=response(&storage,&req).unwrap();assert_eq!(res.status(),206);assert_eq!(res.body(),b"789");
  assert_eq!(res.headers()["Content-Range"],"bytes 7-9/10");
  let secret=storage.root.join("notes/private.md");std::fs::write(&secret,b"private").unwrap();
  let req=Request::builder().uri(format!("asset://localhost{}",secret.display())).body(Vec::new()).unwrap();
  assert!(response(&storage,&req).is_err());std::fs::remove_dir_all(root).unwrap();
 }
}
