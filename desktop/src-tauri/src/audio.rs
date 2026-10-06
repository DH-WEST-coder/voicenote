use crate::{storage::err, Runtime};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use std::{
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc, Arc, Mutex,
    },
    thread,
};
use tauri::{AppHandle, Manager};
// 표본 위치를 콜백 경계 밖까지 유지하여 분할 입력에도 같은 시간축을 만든다.
pub struct Resampler {
    rate: f64,
    next: f64,
    index: u64,
    previous: f32,
}
impl Resampler {
    pub fn new(rate: u32) -> Self {
        Self {
            rate: rate as f64,
            next: 0.,
            index: 0,
            previous: 0.,
        }
    }
    pub fn push(&mut self, samples: &[f32], channels: usize) -> Vec<f32> {
        let mut out = vec![];
        for frame in samples.chunks_exact(channels) {
            let mono = frame.iter().sum::<f32>() / channels as f32;
            let pos = self.index as f64;
            while self.next <= pos {
                let frac = (self.next - (pos - 1.)).clamp(0., 1.) as f32;
                out.push(if self.index == 0 {
                    mono
                } else {
                    self.previous + (mono - self.previous) * frac
                });
                self.next += self.rate / 16000.;
            }
            self.previous = mono;
            self.index += 1;
        }
        out
    }
}
pub struct Audio {
    pub control: Mutex<Option<mpsc::Sender<()>>>,
    pub recording: Mutex<Option<String>>,
    pub worker: Mutex<Option<thread::JoinHandle<()>>>,
}
impl Default for Audio {
    fn default() -> Self {
        Self {
            control: Mutex::new(None),
            recording: Mutex::new(None),
            worker: Mutex::new(None),
        }
    }
}
pub fn start(
    app: AppHandle,
    id: String,
    path: std::path::PathBuf,
    live: Option<mpsc::Sender<Vec<f32>>>,
) -> Result<(), String> {
    let (stop_tx, stop_rx) = mpsc::channel();
    let (ready_tx, ready_rx) = mpsc::channel();
    let handle = app.clone();
    let key = id.clone();
    if let Some(worker) = app
        .state::<Runtime>()
        .audio
        .worker
        .lock()
        .map_err(err)?
        .take()
    {
        let _ = worker.join();
    }
    *app.state::<Runtime>().audio.control.lock().map_err(err)? = Some(stop_tx);
    *app.state::<Runtime>().audio.recording.lock().map_err(err)? = Some(id);
    let worker = thread::spawn(move || {
        let result = (|| -> Result<f64, String> {
            let device = cpal::default_host()
                .default_input_device()
                .ok_or("마이크가 없습니다")?;
            let config = device.default_input_config().map_err(|_| {
                "마이크 권한을 허용하세요. 시스템 설정 > 개인정보 보호 및 보안 > 마이크".to_string()
            })?;
            let channels = config.channels() as usize;
            let rate = config.sample_rate();
            let format = config.sample_format();
            let config: cpal::StreamConfig = config.into();
            let (tx, rx) = mpsc::channel::<Vec<f32>>();
            let mut resampler = Resampler::new(rate);
            let broken = Arc::new(AtomicBool::new(false));
            let stream_broken = broken.clone();
            let error_app = handle.clone();
            let error_callback = move |_| {
                stream_broken.store(true, Ordering::SeqCst);
                error_app
                    .state::<Runtime>()
                    .storage
                    .log("microphone stream error");
            };
            let stream = match format {
                cpal::SampleFormat::F32 => device.build_input_stream(
                    config,
                    move |d: &[f32], _| {
                        let _ = tx.send(resampler.push(d, channels));
                    },
                    error_callback,
                    None,
                ),
                cpal::SampleFormat::I16 => device.build_input_stream(
                    config,
                    move |d: &[i16], _| {
                        let pcm: Vec<f32> = d.iter().map(|v| *v as f32 / 32768.).collect();
                        let _ = tx.send(resampler.push(&pcm, channels));
                    },
                    error_callback,
                    None,
                ),
                cpal::SampleFormat::U16 => device.build_input_stream(
                    config,
                    move |d: &[u16], _| {
                        let pcm: Vec<f32> =
                            d.iter().map(|v| (*v as f32 - 32768.) / 32768.).collect();
                        let _ = tx.send(resampler.push(&pcm, channels));
                    },
                    error_callback,
                    None,
                ),
                _ => return Err("지원하지 않는 마이크 표본 형식".into()),
            }
            .map_err(err)?;
            let mut writer = hound::WavWriter::create(
                path,
                hound::WavSpec {
                    channels: 1,
                    sample_rate: 16000,
                    bits_per_sample: 16,
                    sample_format: hound::SampleFormat::Int,
                },
            )
            .map_err(err)?;
            stream.play().map_err(err)?;
            let _ = ready_tx.send(Ok(()));
            let mut count = 0u64;
            loop {
                if stop_rx.try_recv().is_ok() || broken.load(Ordering::SeqCst) {
                    break;
                }
                match rx.recv_timeout(std::time::Duration::from_millis(50)) {
                    Ok(pcm) => {
                        for v in &pcm {
                            writer
                                .write_sample((v.clamp(-1., 1.) * 32767.) as i16)
                                .map_err(err)?;
                        }
                        count += pcm.len() as u64;
                        if let Some(tx) = &live {
                            let _ = tx.send(pcm);
                        }
                    }
                    Err(mpsc::RecvTimeoutError::Timeout) => {}
                    Err(_) => break,
                }
            }
            drop(stream);
            for pcm in rx.try_iter() {
                for v in &pcm {
                    writer
                        .write_sample((v.clamp(-1., 1.) * 32767.) as i16)
                        .map_err(err)?;
                }
                count += pcm.len() as u64;
                if let Some(tx) = &live {
                    let _ = tx.send(pcm);
                }
            }
            writer.finalize().map_err(err)?;
            if broken.load(Ordering::SeqCst) {
                return Err(
                    "마이크 연결이 끊겼습니다. 저장된 오디오는 다시 처리할 수 있습니다.".into(),
                );
            }
            Ok(count as f64 / 16000.)
        })();
        drop(live);
        let state = handle.state::<Runtime>();
        let mut d = state.storage.data.lock().unwrap();
        if let Some(r) = d.recordings.iter_mut().find(|r| r.id == key) {
            match &result {
                Ok(sec) => {
                    r.duration = *sec;
                    r.status = "queued".into();
                }
                Err(e) => {
                    r.status = "failed".into();
                    r.error = Some(e.clone());
                }
            }
        }
        let _ = state.storage.save(&d);
        drop(d);
        if let Err(e) = &result {
            let _ = ready_tx.send(Err(e.clone()));
            state.storage.log("recording failed");
        } else {
            let _ = state.engine.queue.send(key);
        }
        *state.audio.recording.lock().unwrap() = None;
        *state.audio.control.lock().unwrap() = None;
        crate::engine::notify(&handle);
    });
    // 마이크 생성/권한 결과가 확정된 뒤 UI 녹음 상태를 반환.
    *app.state::<Runtime>().audio.worker.lock().map_err(err)? = Some(worker);
    ready_rx.recv().map_err(err)?
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn resample_stereo_and_chunks() {
        let source: Vec<f32> = (0..48000).flat_map(|_| [0.25, 0.75]).collect();
        let mut r = Resampler::new(48000);
        let output = r.push(&source, 2);
        assert_eq!(output.len(), 16000);
        assert!(output.iter().all(|v| (*v - 0.5).abs() < 1e-6));
        let mut r = Resampler::new(48000);
        let chunks: Vec<f32> = source.chunks(120).flat_map(|s| r.push(s, 2)).collect();
        assert_eq!(chunks, output);
    }
    #[test]
    fn upsample() {
        let mut r = Resampler::new(8000);
        assert_eq!(r.push(&[0., 1., 0.], 1), vec![0., 0.5, 1., 0.5, 0.]);
    }
}

/// 권한 확인도 장치의 실제 표본 형식을 사용한다.
pub fn check_microphone() -> Result<(), String> {
    let device = cpal::default_host()
        .default_input_device()
        .ok_or("마이크가 없습니다")?;
    let config = device.default_input_config().map_err(err)?;
    let format = config.sample_format();
    let config: cpal::StreamConfig = config.into();
    let stream = match format {
        cpal::SampleFormat::F32 => {
            device.build_input_stream(config, |_: &[f32], _| {}, |_| {}, None)
        }
        cpal::SampleFormat::I16 => {
            device.build_input_stream(config, |_: &[i16], _| {}, |_| {}, None)
        }
        cpal::SampleFormat::U16 => {
            device.build_input_stream(config, |_: &[u16], _| {}, |_| {}, None)
        }
        _ => return Err("지원하지 않는 마이크 표본 형식".into()),
    }
    .map_err(|_| {
        "시스템 설정 > 개인정보 보호 및 보안 > 마이크에서 VNote 권한을 허용하세요".to_string()
    })?;
    stream.play().map_err(err)?;
    drop(stream);
    Ok(())
}

/// 가져온 오디오도 정밀본 처리 전에 길이를 알아 누적 시각을 유지한다.
pub fn duration(path: &std::path::Path) -> f64 {
    if let Ok(wav) = hound::WavReader::open(path) {
        return wav.duration() as f64 / wav.spec().sample_rate as f64;
    }
    let Ok(output) = std::process::Command::new("/usr/bin/afinfo")
        .arg("--real")
        .arg(path)
        .output()
    else {
        return 0.;
    };
    parse_duration(&String::from_utf8_lossy(&output.stdout)).unwrap_or(0.)
}
fn parse_duration(info: &str) -> Option<f64> {
    info.lines().find_map(|line| {
        line.trim()
            .strip_prefix("estimated duration: ")
            .and_then(|s| s.split_whitespace().next())
            .and_then(|s| s.parse::<f64>().ok())
            .filter(|v| v.is_finite() && *v >= 0.)
    })
}
#[cfg(test)]
mod duration_tests {
    use super::*;
    #[test]
    fn duration_metadata() {
        assert_eq!(
            parse_duration("estimated duration: 123.456 sec"),
            Some(123.456)
        );
        assert_eq!(parse_duration("estimated duration: nan sec"), None);
    }
}
