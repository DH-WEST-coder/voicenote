import { useCallback,useEffect,useRef,useState,lazy,Suspense } from 'react';
import { invoke,convertFileSrc } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import { getCurrentWebview } from '@tauri-apps/api/webview';
import { open,save } from '@tauri-apps/plugin-dialog';
import { openUrl } from '@tauri-apps/plugin-opener';
import { ko } from './i18n/ko';
import { Data,Note,Project,Detail,Message,Line,Settings,ChatModel,time } from './types';
const PdfView=lazy(() => import('./components/PdfView').then(m => ({ default: m.PdfView })));
import { NoteEditor } from './components/NoteEditor';
import { ChatPanel } from './components/ChatPanel';
import { Setup } from './components/Setup';
import { SettingsView } from './components/SettingsView';
import './App.css';
const blank: Detail={ text: '',messages: [],lines: [] };
function App() {
    const [data,setData]=useState<Data>();
    const [selected,setSelected]=useState('');
    const [details,setDetails]=useState<Record<string,Detail>>({});
    const [error,setError]=useState('');
    const [settingsOpen,setSettingsOpen]=useState(false);
    const [chatVisible,setChatVisible]=useState(true);
    const [tab,setTab]=useState('transcript');
    const [materialId,setMaterialId]=useState('');
    const [connected,setConnected]=useState(false);
    const [chatModels,setChatModels]=useState<ChatModel[]>([]);
    const [editing,setEditing]=useState<Project|null>(null);
    const [speakerEditing,setSpeakerEditing]=useState<{ note: Note; speaker: string; name: string }|null>(null);
    const testTimer=useRef<ReturnType<typeof setTimeout>|null>(null);
    const [progress,setProgress]=useState<Record<string,string>>({});
    const [live,setLive]=useState<Record<string,{
        commits: Line[];
        partial: string;
    }>>({});
    const [recording,setRecording]=useState<{
        id: string;
        noteId: string;
        start: number;
    }|null>(null);
    const [elapsed,setElapsed]=useState(0);
    const [recordBusy,setRecordBusy]=useState(false);
    const [chatBusy,setChatBusy]=useState<{
        noteId: string;
        requestId: string;
        terms: boolean;
    }|null>(null);
    const [modelProgress,setModelProgress]=useState<{ busy: boolean; done: boolean; text: string; modelSet: string; status?: string; model?: string; downloadedBytes?: number; totalBytes?: number; bytesPerSec?: number; progress?: number; lastByteAt?: number; error?: boolean }>({ busy: false,done: false,text: '',modelSet: '' });
    const [translocated,setTranslocated]=useState(false);
    const [translocationCommand,setTranslocationCommand]=useState('xattr -dr com.apple.quarantine /Applications/VNote.app');
    const [commandCopied,setCommandCopied]=useState(false);
    const pendingTerms=useRef(new Set<string>());
    const [update,setUpdate]=useState<{
        html_url: string;
        tag_name: string;
    }|null>(null);
    const [play,setPlay]=useState<{
        id: string;
        offset: number;
        position: number;
        active: boolean;
    }|null>(null);
    const audio=useRef<HTMLAudioElement>(null);
    const latest=useRef({ data,selected,details,recording,elapsed,play,chatBusy,connected });
    latest.current={ data,selected,details,recording,elapsed,play,chatBusy,connected };
    const saves=useRef(Promise.resolve());
    const detailLoads=useRef(new Map<string,Promise<Detail>>());
    const fail=useCallback((e: unknown) => { setError(String(e)); void invoke('log_error').catch(() => { }); },[]);
    const run=async <T,>(cmd: string,args?: Record<string,unknown>): Promise<T|undefined> => {
        try {
            await saves.current;
            return await invoke<T>(cmd,args);
        }
        catch(e) {
            fail(e);
        }
    };
    const refresh=useCallback(async () => {
        try {
            const d=await invoke<Data>('load_data');
            latest.current.data=d;
            setData(d);
            if(latest.current.recording) { const r=d.recordings.find(r => r.id===latest.current.recording?.id); if(r&&r.status!=='recording') { setRecording(null); latest.current.recording=null; } }
            setSelected(s => s||d.notes[0]?.id||'');
            const keys=Object.keys(latest.current.details);
            for(const key of keys) {
                const detail=await invoke<Detail>('note_detail',{ noteId: key });
                setDetails(old => ({ ...old,[key]: old[key]? { ...old[key],lines: detail.lines }:detail }));
            }
        }
        catch(e) {
            fail(e);
        }
    },[fail]);
    const loadDetail=useCallback((key: string) => {
        let promise=detailLoads.current.get(key); if(!promise) {
            promise=invoke<Detail>('note_detail',{ noteId: key });
            detailLoads.current.set(key,promise);
        } return promise;
    },[]);
    useEffect(() => {
        void refresh();
        invoke<{translocated:boolean;command:string}>('startup_status').then(s => { setTranslocated(s.translocated); setTranslocationCommand(s.command); }).catch(() => { });
        invoke<boolean>('chat_status').then(setConnected).catch(() => { });
        invoke<{
            html_url: string;
            tag_name: string;
        }|null>('check_update').then(setUpdate).catch(() => { });
        const timer=setInterval(() => { invoke<boolean>('chat_status').then(setConnected).catch(() => { }); },4000);
        return () => { clearInterval(timer); if(testTimer.current) clearTimeout(testTimer.current); };
    },[refresh]);
    useEffect(() => {
        if(connected) invoke<ChatModel[]>('chat_models').then(setChatModels).catch(fail);
    },[connected,fail]);
    useEffect(() => {
        if(selected&&!details[selected])
            loadDetail(selected).then(detail => setDetails(old => ({ ...old,[selected]: old[selected]||detail }))).catch(fail);
    },[selected,loadDetail,fail,details]);
    useEffect(() => {
        const timer=setInterval(() => {
            if(latest.current.recording)
                setElapsed((Date.now()-latest.current.recording.start)/1000);
        },250); return () => clearInterval(timer);
    },[]);
    useEffect(() => { document.documentElement.dataset.theme=data?.settings.theme||'system'; },[data?.settings.theme]);
    useEffect(() => {
        let disposed=false;
        const unlisten: (() => void)[]=[];
        const register=async (p: Promise<() => void>) => {
            const off=await p; if(disposed)
                off();
            else
                unlisten.push(off);
        };
        void register(listen('data-changed',() => void refresh()));
        void register(listen<{
            id: string;
            message: {
                stage: string;
                status?: string;
                progress?: number;
            };
        }>('engine-progress',({ payload: p }) => setProgress(old => ({ ...old,[p.id]: `${ko.stages[p.message.stage as keyof typeof ko.stages]||p.message.stage} ${p.message.progress!==undefined? Math.round(p.message.progress*100)+'%':ko.progressStatus[p.message.status as keyof typeof ko.progressStatus]||p.message.status||''}` }))));
        void register(listen<{
            id: string;
            message: {
                type: string;
                start?: number;
                text?: string;
                message?: string;
            };
        }>('live-message',({ payload: p }) => {
            if(p.message.type==='error') {
                fail(`${ko.liveError}: ${p.message.message}`);
                return;
            } setLive(old => {
                const current=old[p.id]||{ commits: [],partial: '' }; if(p.message.type==='partial')
                    return { ...old,[p.id]: { ...current,partial: p.message.text||'' } }; if(p.message.type==='commit')
                    return { ...old,[p.id]: { commits: [...current.commits,{ time: p.message.start||0,localTime: p.message.start||0,recordingId: p.id,speaker: '',text: p.message.text||'' }],partial: '' } }; return old;
            });
        }));
        void register(listen<{
            status: string;
            model?: string;
            progress?: number;
            message?: string;
            model_set?: string;
            downloaded_bytes?: number;
            total_bytes?: number;
            bytes_per_sec?: number;
        }>('model-progress',({ payload: p }) => {
            setModelProgress(old => {
                const downloaded=p.downloaded_bytes??old.downloadedBytes??0;
                return { ...old,busy: !['done','error'].includes(p.status),done: p.status==='done',error:p.status==='error',status:p.status,model:p.model||old.model,modelSet:p.model_set||old.modelSet,text:p.status==='done'? ko.modelDone:p.status==='error'? p.message||ko.retryDownload:old.text,downloadedBytes:downloaded,totalBytes:p.total_bytes??old.totalBytes,bytesPerSec:p.bytes_per_sec??0,progress:p.progress??old.progress,lastByteAt:downloaded>(old.downloadedBytes||0)?Date.now():(old.lastByteAt||Date.now()) };
            }); if(p.status==='done') void refresh();
        }));
        void register(listen<{
            noteId: string;
            requestId: string;
            text?: string;
            done?: boolean;
            error?: string;
        }>('chat-message',({ payload: p }) => {
            const busy=latest.current.chatBusy;
            if(!busy||p.requestId!==busy.requestId)
                return;
            if(busy.terms) {
                if(p.done) {
                    latest.current.chatBusy=null;
                    setChatBusy(null);
                    if(p.error)
                        fail(p.error);
                    void refresh().then(drainTerms);
                }
                return;
            }
            const d=latest.current.details[p.noteId]||blank;
            const messages=d.messages.map((m,i) => i===d.messages.length-1? { ...m,text: p.error? m.text+'\n'+p.error:m.text+(p.text? (m.text? '\n\n':'')+p.text:''),error: !!p.error&&!(p.error===ko.chatStopped&&!!m.text) }:m);
            latest.current.details={ ...latest.current.details,[p.noteId]: { ...d,messages } };
            setDetails(latest.current.details);
            if(p.done) { enqueue(() => invoke('save_chat',{ noteId: p.noteId,messages })); latest.current.chatBusy=null; setChatBusy(null); drainTerms(); }
        }));
        void register(getCurrentWebview().onDragDropEvent(e => {
            if(e.payload.type==='drop')
                void importPaths(e.payload.paths);
        }));
        return () => { disposed=true; unlisten.forEach(off => off()); };
    },[refresh,fail]);
    function enqueue(task: () => Promise<unknown>) { saves.current=saves.current.then(task).then(() => { }).catch(fail); }
    function setText(key: string,text: string) { latest.current.details={ ...latest.current.details,[key]: { ...(latest.current.details[key]||blank),text } }; setDetails(latest.current.details); enqueue(() => invoke('save_text',{ noteId: key,text })); }
    function changeSettings(s: Settings) { setData(d => d? { ...d,settings: s }:d); enqueue(() => invoke('save_settings',{ settings: s })); }
    async function createNote(projectId: string) {
        const key=await run<string>('save_note',{ note: { id: '',projectId,title: ko.newNote,createdAt: '',recordingIds: [],materials: [],terms: [],speakerNames: {} } }); if(key)
            setSelected(key);
    }
    async function importPaths(paths: string[]) {
        let importedPdf=false; const key=latest.current.selected; if(!key) {
            fail(ko.empty);
            return;
        } for(const path of paths) {
            try {
                const materialId=await invoke<string>('import_file',{ noteId: key,path });
                if(path.toLowerCase().endsWith('.pdf')) {
                    const d=await invoke<Data>('load_data');
                    const material=d.notes.find(n => n.id===key)?.materials.find(m => m.id===materialId);
                    if(!material)
                        continue;
                    const { extractPdf }=await import('./components/PdfView');
                    const text=await extractPdf(material.path);
                    await invoke('material_text',{ noteId: key,materialId,text });
                    await refresh();
                    if(!text.trim())
                        fail(ko.extractEmpty);
                    else if(latest.current.connected)
                        importedPdf=true;
                    else
                        fail(ko.extractLogin);
                    setTab('materials');
                    setMaterialId(materialId);
                }
            }
            catch(e) {
                fail(e);
            }
        } if(importedPdf) { pendingTerms.current.add(key); drainTerms(); }
    }
    async function chooseFiles() {
        const paths=await open({ multiple: true,filters: [{ name: ko.audio+' / '+ko.pdf,extensions: ['pdf','wav','m4a','mp3','aac','flac','ogg','aiff','mp4','opus'] }] }); if(paths)
            await importPaths(Array.isArray(paths)? paths:[paths]);
    }
    function drainTerms() { if(latest.current.chatBusy) return; const key=pendingTerms.current.values().next().value; if(key) { pendingTerms.current.delete(key); void extractTerms(key); } }
    async function extractTerms(key: string,body?: string) {
        if(latest.current.chatBusy) { pendingTerms.current.add(key); return; } const n=latest.current.data?.notes.find(n => n.id===key); const budget=Math.max(1000,Math.floor(40000/(n?.materials.length||1))); const text=body||n?.materials.map(m => m.name+'\n'+m.text.slice(0,budget)).join('\n')||''; if(!text.trim()) {
            fail(ko.extractEmpty);
            return;
        } const project=latest.current.data?.projects.find(p => p.id===n?.projectId); const requestId=crypto.randomUUID(); const busy={ noteId: key,requestId,terms: true }; latest.current.chatBusy=busy; setChatBusy(busy); try {
            await invoke('chat_ask',{ noteId: key,requestId,terms: true,prompt: ko.systemPrompt+'\n'+ko.termsPrompt+'\n'+(project?.language||'auto')+'\n'+text.slice(0,40000) });
        }
        catch(e) {
            setChatBusy(null);
            latest.current.chatBusy=null;
            fail(e);
        }
    }
    function clock(): number|null {
        const state=latest.current; if(state.recording?.noteId===state.selected) {
            const note=state.data?.notes.find(n => n.id===state.selected);
            const offset=(note?.recordingIds||[]).filter(id => id!==state.recording?.id).reduce((s,id) => s+(state.data?.recordings.find(r => r.id===id)?.duration||0),0);
            return offset+state.elapsed;
        } if(state.play?.active&&state.data?.notes.find(n => n.id===state.selected)?.recordingIds.includes(state.play.id))
            return state.play.offset+state.play.position; return null;
    }
    function ask(question: string,recent=false) {
        const state=latest.current;
        const key=state.selected;
        const n=state.data?.notes.find(n => n.id===key);
        if(!n||state.chatBusy)
            return;
        const detail=state.details[key]||blank;
        const lines=combinedLines(n,detail);
        const now=clock()??lines[lines.length-1]?.time??0;
        const requested=recent? lines.filter(l => l.time>=now-180&&l.time<=now):lines;
        const formatted=requested.map(l => `[${time(l.time)}] ${n.speakerNames[l.speaker]||l.speaker}: ${l.text}`);
        let transcript=formatted.join('\n');
        if(transcript.length>60000) {
            const tail=transcript.slice(-36000);
            transcript=transcript.slice(0,24000)+'\n[…]\n'+tail;
        }
        const block=(name: string,text: string) => `\n<${name}>\n${text}\n</${name}>\n`;
        const prompt=ko.systemPrompt+block(ko.context.info,n.title+'\n'+time(now))+block(ko.context.transcript,transcript)+block(ko.context.materials,n.materials.map(m => m.name+'\n'+m.text).join('\n').slice(0,40000))+block(ko.context.notes,detail.text.slice(0,40000))+block(ko.context.history,detail.messages.slice(-8).map(m => m.role+': '+m.text).join('\n').slice(-30000))+block(ko.context.question,question);
        const messages: Message[]=[...detail.messages,{ id: crypto.randomUUID(),role: 'user',text: question },{ id: crypto.randomUUID(),role: 'assistant',text: '' }];
        latest.current.details={ ...latest.current.details,[key]: { ...detail,messages } };
        setDetails(latest.current.details);
        enqueue(() => invoke('save_chat',{ noteId: key,messages }));
        const requestId=crypto.randomUUID();
        const busy={ noteId: key,requestId,terms: false };
        latest.current.chatBusy=busy;
        setChatBusy(busy);
        invoke('chat_ask',{ noteId: key,requestId,prompt,terms: false }).catch(e => { setChatBusy(null); latest.current.chatBusy=null; const d=latest.current.details[key]; const messages=d.messages.map((m,i) => i===d.messages.length-1? { ...m,text: String(e),error: true }:m); latest.current.details={ ...latest.current.details,[key]: { ...d,messages } }; setDetails(latest.current.details); enqueue(() => invoke('save_chat',{ noteId: key,messages })); fail(e); drainTerms(); });
    }
    function combinedLines(n: Note,d: Detail) {
        let offset=0; const lines: Line[]=[]; for(const id of n.recordingIds) {
            const r=latest.current.data?.recordings.find(r => r.id===id);
            const stored=d.lines.filter(l => l.recordingId===id);
            const commits=live[id]?.commits;
            lines.push(...(r?.transcript||!commits?.length? stored.map(l => ({ ...l,time: offset+l.localTime })):commits.map(l => ({ ...l,time: offset+l.localTime }))));
            offset+=r?.duration||0;
        } return lines;
    }
    function recordingOffset(id: string) { let offset=0; for(const key of note?.recordingIds||[]) { if(key===id) return offset; offset+=data?.recordings.find(r => r.id===key)?.duration||0; } return offset; }
    function seek(l: Line) {
        const r=data?.recordings.find(r => r.id===l.recordingId); if(!r||r.status==='recording'||!audio.current)
            return; const player=audio.current; const src=convertFileSrc(r.path); const go=() => { player.currentTime=l.localTime; void player.play().catch(fail); }; setPlay({ id: r.id,offset: l.time-l.localTime,position: l.localTime,active: true }); if(player.src!==src) {
                player.src=src;
                player.addEventListener('loadedmetadata',go,{ once: true });
                player.load();
            }
        else
            go();
    }
    async function startRecording(noteId: string) {
        const id=await invoke<string>('start_recording',{ noteId });
        const state={ id,noteId,start: Date.now() };
        latest.current.recording=state;
        setRecording(state);
        setElapsed(0);
        return id;
    }
    async function stopRecording() {
        if(testTimer.current) { clearTimeout(testTimer.current); testTimer.current=null; }
        await invoke('stop_recording');
        latest.current.recording=null;
        setRecording(null);
    }
    async function record() {
        if(!selected||recordBusy)
            return; setRecordBusy(true); try {
                if(recording)
                    await stopRecording();
                else
                    await startRecording(selected);
            }
        catch(e) {
            fail(e);
        }
        finally {
            setRecordBusy(false);
        }
    }
    async function testRecording() {
        if(!data||recordBusy||recording) return;
        setRecordBusy(true);
        try {
            await saves.current;
            const projectId=await invoke<string>('save_project',{ project: { id: '',name: ko.testProject,language: 'auto',terms: [] } });
            const noteId=await invoke<string>('save_note',{ note: { id: '',projectId,title: ko.testRecord,createdAt: '',recordingIds: [],materials: [],terms: [],speakerNames: {} } });
            latest.current.selected=noteId; setSelected(noteId);
            await refresh();
            await startRecording(noteId);
            changeSettings({ ...data.settings,onboardingDone: true });
            testTimer.current=setTimeout(() => { testTimer.current=null; void stopRecording().catch(fail); },10000);
        } catch(e) { fail(e); } finally { setRecordBusy(false); }
    }
    async function exportNote(plain: boolean) {
        try {
            await saves.current;
            const path=await save({ defaultPath: (note?.title||ko.app)+(plain? '.txt':'.md'),filters: [{ name: plain? ko.text:ko.markdown,extensions: [plain? 'txt':'md'] }] });
            if(path)
                await invoke('export_note',{ noteId: selected,path,plain });
        }
        catch(e) {
            fail(e);
        }
    }
    function insert(text: string) { const detail=latest.current.details[selected]||blank; const t=clock(); setText(selected,detail.text+(detail.text&&!detail.text.endsWith('\n')? '\n':'')+(t!==null? `[${time(t)}] `:'')+text.trim()+'\n'); }
    function download(asrModel: string,liveModel: string) {
        const modelSet=`${asrModel},${liveModel}`;
        setModelProgress({ busy: true,done: false,text: ko.downloading,modelSet,lastByteAt:Date.now(),status:'connecting',downloadedBytes:0,totalBytes:0,progress:0 });
        invoke('download_models',{ asrModel,liveModel }).catch(e => setModelProgress(old => ({ ...old,busy:false,error:true,text:String(e) })));
    }
    const note=data?.notes.find(n => n.id===selected);
    const detail=details[selected]||blank;
    const materials=note?.materials||[];
    const material=materials.find(m => m.id===materialId)||materials[0];
    const lines=note? combinedLines(note,detail):[];
    if(translocated) return <div className="overlay"><section className="modal"><h1>VNote를 응용 프로그램 폴더로 끌어다 놓은 뒤 다시 열어 주세요</h1><p>또는 터미널에서 아래 명령을 실행한 뒤 다시 여세요.</p><code style={{ display:'block',wordBreak:'break-all',margin:'16px 0' }}>{translocationCommand}</code><button onClick={async () => { try { await navigator.clipboard.writeText(translocationCommand); } catch { const field=document.createElement('textarea'); field.value=translocationCommand; document.body.appendChild(field); field.select(); document.execCommand('copy'); field.remove(); } setCommandCopied(true); }}>{commandCopied?'복사됨':'명령 복사'}</button></section></div>;
    return <>
        <header>
            <b>
                {ko.app}
            </b>
            <button onClick={() => setSettingsOpen(true)}>
                {ko.settings}
            </button>
            <button onClick={() => setChatVisible(!chatVisible)}>
                {chatVisible? ko.hideChat:ko.showChat}
            </button>
            {update&&<div className="update">
                {ko.update} {update.tag_name}
                <button onClick={() => openUrl(update.html_url).catch(fail)}>
                    {ko.getUpdate}
                </button>
            </div>}
        </header>
        {error&&<div className="error-banner" role="alert">
            {error}
            {error.includes(ko.microphoneKeyword)&&<button onClick={() => openUrl(ko.microphoneUrl).catch(fail)}>
                {ko.openMic}
            </button>}
            <button onClick={() => setError('')}>
                {ko.close}
            </button>
        </div>}
        <main>
            <nav className="sidebar">
                <h2>
                    {ko.projects}
                </h2>
                <button onClick={() => setEditing({ id: '',name: '',language: 'auto',terms: [] })}>
                    {ko.newProject}
                </button>
                {data?.projects.map(p => <section key={p.id}>
                    <h3>
                        {p.name}
                        <button title={ko.edit} onClick={() => setEditing({ ...p })}>⋯</button>
                    </h3>
                    <button onClick={() => void createNote(p.id)}>+ {ko.newNote}
                    </button>
                    {data.notes.filter(n => n.projectId===p.id).map(n => <button className={'note-link '+(n.id===selected? 'selected':'')} key={n.id} disabled={!!recording&&n.id!==recording.noteId} onClick={() => { audio.current?.pause(); setPlay(null); latest.current.play=null; latest.current.selected=n.id; setSelected(n.id); setMaterialId(''); }}>
                        {n.title}
                        <small>
                            {new Date(n.createdAt).toLocaleDateString('ko-KR')}
                        </small>
                    </button>)}
                </section>)}
            </nav>
            <section className="center">
                {note? <>
                    <div className="note-title">
                        <input key={note.id+note.title} defaultValue={note.title} aria-label={ko.title} onBlur={e => {
                            if(e.target.value!==note.title)
                                void run('save_note',{ fields: ['title'],note: { ...note,title: e.target.value } });
                        }} />
                        <div className="toolbar">
                            <button className={recording? 'recording':''} disabled={recordBusy} onClick={() => void record()}>
                                {recording? `${ko.stop} ${time(elapsed)}`:ko.record}
                            </button>
                            <button onClick={() => void chooseFiles().catch(fail)}>
                                {ko.import}
                            </button>
                            <button onClick={() => void exportNote(false)}>
                                {ko.export} .md</button>
                            <button onClick={() => void exportNote(true)}>.txt</button>
                        </div>
                    </div>
                    <div className="tabs">
                        <button className={tab==='transcript'? 'selected':''} onClick={() => setTab('transcript')}>
                            {ko.transcript}
                        </button>
                        <button className={tab==='materials'? 'selected':''} onClick={() => setTab('materials')}>
                            {ko.materials} ({materials.length})</button>
                    </div>
                    <div className="content">
                        {tab==='transcript'? <>
                            <div className="jobs">
                                {note.recordingIds.map(id => {
                                    const r=data?.recordings.find(r => r.id===id); return r&&<div key={id}>
                                        <button onClick={() => seek({ recordingId: id,time: recordingOffset(id),localTime: 0,speaker: '',text: '' })}>
                                            {ko.status[r.status as keyof typeof ko.status]||r.status} · {time(r.duration)}
                                        </button>
                                        {r.status==='processing'&&<small>
                                            {progress[id]}
                                        </small>}
                                        {r.error&&<span className="error">
                                            {r.error}
                                            <button onClick={() => void run('retry_recording',{ recordingId: id })}>
                                                {ko.retry}
                                            </button>
                                        </span>}
                                    </div>;
                                })}
                            </div>
                            {!lines.length&&<p className="empty">
                                {ko.noTranscript}
                            </p>}
                            {lines.map((l,i) => <p className="line" key={l.recordingId+':'+i}>
                                <button className="timestamp" onClick={() => seek(l)}>[{time(l.time)}]</button>
                                {l.speaker&&<button className="speaker" onClick={() => setSpeakerEditing({ note,speaker: l.speaker,name: note.speakerNames[l.speaker]||l.speaker })}>
                                    {note.speakerNames[l.speaker]||l.speaker}
                                </button>}
                                <span>
                                    {l.text}
                                </span>
                            </p>)}
                            {recording&&live[recording.id]?.partial&&<p className="partial">
                                {live[recording.id].partial}
                            </p>}
                        </>:<>
                            {materials.length? <>
                                <div className="toolbar">
                                    <select value={material?.id||''} onChange={e => setMaterialId(e.target.value)}>
                                        {materials.map(m => <option value={m.id} key={m.id}>
                                            {m.name}
                                        </option>)}
                                    </select>
                                    <button disabled={!connected||!!chatBusy} onClick={() => void extractTerms(note.id)}>
                                        {chatBusy?.terms? ko.extracting:ko.extract}
                                    </button>
                                </div>
                                {material&&<Suspense fallback={<p>
                                    {ko.loading}
                                </p>}>
                                    <PdfView material={material} onError={fail} />
                                </Suspense>}
                            </>:<p className="empty">
                                {ko.noMaterials}
                            </p>}
                        </>}
                    </div>
                    <audio ref={audio} controls onTimeUpdate={() => setPlay(p => p? { ...p,position: audio.current?.currentTime||0 }:p)} onPlay={() => setPlay(p => p? { ...p,active: true }:p)} onPause={() => setPlay(p => p? { ...p,active: false }:p)} onEnded={() => setPlay(p => p? { ...p,active: false }:p)} />
                    <NoteEditor key={selected} text={detail.text} onChange={text => setText(selected,text)} clock={clock} />
                    <details className="terms">
                        <summary>
                            {ko.terms} ({note.terms.length})</summary>
                        <textarea key={note.id+note.terms.join()} defaultValue={note.terms.join('\n')} onBlur={e => void run('save_note',{ fields: ['terms'],note: { ...note,terms: e.target.value.split('\n').map(s => s.trim()).filter(Boolean).slice(0,80) } })} />
                    </details>
                </>:<p className="empty">
                    {ko.empty}
                </p>}
            </section>
            {chatVisible&&data&&<ChatPanel messages={detail.messages} connected={connected} busy={!!chatBusy} ask={ask} stop={() => void run('chat_stop')} login={() => void run('chat_login')} insert={insert} settings={data.settings} change={changeSettings} models={chatModels} />}
        </main>
        {speakerEditing&&<div className="overlay">
            <form className="modal" onSubmit={e => { e.preventDefault(); void run('save_note',{ fields: ['speakerNames'],note: { ...speakerEditing.note,speakerNames: { ...speakerEditing.note.speakerNames,[speakerEditing.speaker]: speakerEditing.name.trim()||speakerEditing.speaker } } }).then(() => setSpeakerEditing(null)); }}>
                <h2>
                    {ko.speaker}
                </h2>
                <input autoFocus value={speakerEditing.name} aria-label={ko.speaker} onChange={e => setSpeakerEditing({ ...speakerEditing,name: e.target.value })} />
                <footer>
                    <button type="button" onClick={() => setSpeakerEditing(null)}>
                        {ko.cancel}
                    </button>
                    <button>
                        {ko.save}
                    </button>
                </footer>
            </form>
        </div>}
        {editing&&<div className="overlay">
            <form className="modal" onSubmit={e => {
                e.preventDefault(); void run('save_project',{ project: editing }).then(key => {
                    if(key)
                        setEditing(null);
                });
            }}>
                <h2>
                    {ko.projects}
                </h2>
                <label>
                    {ko.name}
                    <input required value={editing.name} onChange={e => setEditing({ ...editing,name: e.target.value })} />
                </label>
                <label>
                    {ko.language}
                    <select value={editing.language} onChange={e => setEditing({ ...editing,language: e.target.value })}>
                        {[['auto',ko.auto],['Korean',ko.korean],['English',ko.english]].map(([v,l]) => <option key={v} value={v}>
                            {l}
                        </option>)}
                    </select>
                </label>
                <label>
                    {ko.terms}
                    <textarea value={editing.terms.join('\n')} onChange={e => setEditing({ ...editing,terms: e.target.value.split('\n') })} />
                </label>
                <footer>
                    <button type="button" onClick={() => setEditing(null)}>
                        {ko.cancel}
                    </button>
                    <button>
                        {ko.save}
                    </button>
                </footer>
            </form>
        </div>}
        {data&&!data.settings.onboardingDone&&<Setup settings={data.settings} onSettings={changeSettings} testRecording={() => void testRecording()} connected={connected} login={() => void run('chat_login')} download={download} modelProgress={modelProgress} onError={fail} />}
        {data&&settingsOpen&&<SettingsView settings={data.settings} change={changeSettings} close={() => setSettingsOpen(false)} connected={connected} login={() => void run('chat_login')} logout={() => void run('chat_logout').then(() => setConnected(false))} download={download} retryDownload={() => download(data.settings.asrModel,data.settings.liveModel)} progress={modelProgress} onError={fail} onModels={setChatModels} />}
    </>;
}
export default App;
