import { useEffect,useState } from 'react';

type Progress = { busy: boolean; done: boolean; error?: boolean; text: string; status?: string; modelSet: string; model?: string; downloadedBytes?: number; totalBytes?: number; bytesPerSec?: number; progress?: number; lastByteAt?: number };
const bytes = (n: number) => `${(n/1e9).toFixed(1)}GB`;
export function ModelProgress({ value,retry }: { value: Progress; retry: () => void }) {
    const [,tick]=useState(0);
    useEffect(() => { const id=setInterval(() => tick(v => v+1),1000); return () => clearInterval(id); },[]);
    const downloaded=value.downloadedBytes||0, total=value.totalBytes||0, speed=value.bytesPerSec||0;
    const percent=Math.max(0,Math.min(100,Math.round((value.progress===undefined?(total?downloaded/total:0):value.progress)*100)));
    const stalled=value.busy&&Date.now()-(value.lastByteAt||Date.now())>=60000;
    const eta=speed>0&&total>downloaded? Math.ceil((total-downloaded)/speed):null;
    return <div className="model-progress">
        {value.busy&&<>
            {value.status==='connecting'? <><p>연결 중…</p><p>{value.model||'모델 준비 중'}</p></>:<p>{value.model||'모델 준비 중'}</p>}
            <progress max="100" value={percent}/>
            <div className="progress-meta"><span>{percent}% · {bytes(downloaded)} / {total?bytes(total):'용량 확인 중'}</span><span>{speed>0?`${(speed/1e6).toFixed(1)} MB/s`:'— MB/s'} · {eta===null?'남은 시간 계산 중':`약 ${Math.floor(eta/60)}분 ${eta%60}초 남음`}</span></div>
            {stalled&&<p className="error">인터넷 연결을 확인하세요. 다운로드 바이트가 60초 동안 늘지 않았습니다.</p>}
        </>}
        {!value.busy&&value.text&&<p className={value.error?'error':''}>{value.text}</p>}
        {value.error&&<button onClick={retry}>다시 시도</button>}
    </div>;
}
