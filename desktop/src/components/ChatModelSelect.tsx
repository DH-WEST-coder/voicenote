import { useEffect } from 'react';
import { ChatModel,Settings } from '../types';
import { ko } from '../i18n/ko';

export function ChatModelSelect({ settings,change,models }: {
    settings: Settings;
    change: (s: Settings) => void;
    models: ChatModel[];
}) {
    const cached=models.some(m => m.id===settings.chatModel);
    const selectedEfforts=models.find(m => m.id===settings.chatModel)?.efforts;
    const efforts=selectedEfforts?.length?selectedEfforts:['low','medium','high'];
    useEffect(() => {
        if(selectedEfforts?.length&&!efforts.includes(settings.chatReasoningEffort))
            change({ ...settings,chatReasoningEffort:'low' });
    },[selectedEfforts,efforts,settings,change]);
    return <>
        <label>
            {settings.chatProvider==='claude'?ko.claudeModel:ko.chatgptModel}
            <select value={settings.chatModel} onChange={e => {
                const model=models.find(m => m.id===e.target.value);
                const supported=model?.efforts.length?model.efforts:['low','medium','high'];
                change({ ...settings,chatModel:e.target.value,...(supported.includes(settings.chatReasoningEffort)?{}:{chatReasoningEffort:'low'}) });
            }}>
                <option value="">{settings.chatProvider==='claude'?'Claude Code 기본 모델':ko.defaultModel}</option>
                {!cached&&settings.chatModel&&<option value={settings.chatModel}>{ko.unknownModel}: {settings.chatModel}</option>}
                {models.map(m => <option key={m.id} value={m.id}>{m.label}</option>)}
            </select>
        </label>
        <label>
            {ko.effort}
            <select value={settings.chatReasoningEffort||'low'} onChange={e => change({ ...settings,chatReasoningEffort: e.target.value })}>
                {efforts.map(effort => <option key={effort} value={effort}>{({low:ko.low,medium:ko.medium,high:ko.high} as Record<string,string>)[effort]||effort}</option>)}
            </select>
        </label>
    </>;
}
