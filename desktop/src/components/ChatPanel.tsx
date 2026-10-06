import { useState } from 'react';
import ReactMarkdown from 'react-markdown';
import { ko } from '../i18n/ko';
import { Message } from '../types';
export function ChatPanel({ messages,busy,connected,ask,stop,login,insert }: {
    messages: Message[];
    busy: boolean;
    connected: boolean;
    ask: (q: string,recent?: boolean) => void;
    stop: () => void;
    login: () => void;
    insert: (s: string) => void;
}) {
    const [q,setQ]=useState('');
    return <aside className="chat">
        <h2>
            {ko.chat}
            <small>
                {connected? ko.connected:ko.disconnected}
            </small>
        </h2>
        {!connected&&<>
            <p>
                {ko.privacy}
            </p>
            <button onClick={login}>
                {ko.login}
            </button>
        </>}
        <div className="quick">
            {[[ko.recent,ko.recentPrompt],[ko.draft,ko.draftPrompt],[ko.unknown,ko.unknownPrompt]].map(([label,prompt],i) => <button key={label} disabled={busy||!connected} onClick={() => ask(prompt,i===0)}>
                {label}
            </button>)}
        </div>
        <div className="messages">
            {messages.map(m => <article key={m.id} className={m.role+(m.error? ' error':'')}>
                <ReactMarkdown>
                    {m.text}
                </ReactMarkdown>
                {m.role==='assistant'&&!m.error&&m.text&&<button onClick={() => insert(m.text)}>
                    {ko.insert}
                </button>}
            </article>)}
        </div>
        {busy? <button onClick={stop}>
            {ko.stopChat}
        </button>:<form onSubmit={e => {
            e.preventDefault(); if(q.trim()) {
                ask(q);
                setQ('');
            }
        }}>
            <textarea value={q} onChange={e => setQ(e.target.value)} placeholder={ko.question} />
            <button disabled={!connected||!q.trim()}>
                {ko.send}
            </button>
        </form>}
    </aside>;
}
