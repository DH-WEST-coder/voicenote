import { useRef,useEffect } from 'react';
import { ko } from '../i18n/ko';
import { time } from '../types';
export function NoteEditor({ text,onChange,clock }: {
    text: string;
    onChange: (text: string) => void;
    clock: () => number|null;
}) {
    const editor=useRef<HTMLTextAreaElement>(null);
    // beforeinput에서 첫 자모의 composition도 처리. Enter/paste에는 시각을 넣지 않는다.
    function stamp(inputType: string,data: string|null) {
        const e=editor.current;
        const t=clock();
        if(!e||t===null||!data||data==='\n'||!['insertText','insertCompositionText'].includes(inputType)||e.selectionStart!==e.selectionEnd)
            return;
        const start=e.selectionStart===0? 0:e.value.lastIndexOf('\n',e.selectionStart-1)+1;
        const end=e.value.indexOf('\n',e.selectionStart);
        if(e.value.slice(start,end<0? e.value.length:end)!=='')
            return;
        const pos=e.selectionStart;
        const prefix=`[${time(t)}] `;
        e.setRangeText(prefix,pos,pos,'end');
        onChange(e.value);
    }
    useEffect(() => {
        const e=editor.current; if(!e)
            return; const before=(event: InputEvent) => stamp(event.inputType,event.data); const composition=() => stamp('insertCompositionText',' '); e.addEventListener('beforeinput',before); e.addEventListener('compositionstart',composition); return () => { e.removeEventListener('beforeinput',before); e.removeEventListener('compositionstart',composition); };
    },[onChange,clock]);
    return <section className="note-editor">
        <h3>
            {ko.myNotes}
            <small>
                {ko.saved}
            </small>
        </h3>
        <textarea ref={editor} value={text} placeholder={ko.noteHint} onChange={e => onChange(e.target.value)} />
    </section>;
}
