import { useEffect,useRef,useState } from 'react';
import { invoke } from '@tauri-apps/api/core';
import * as pdfjs from 'pdfjs-dist';
import worker from 'pdfjs-dist/build/pdf.worker.min.mjs?url';
import { ko } from '../i18n/ko';
import { Material } from '../types';
pdfjs.GlobalWorkerOptions.workerSrc=worker;
const pdfOptions={
    cMapUrl: '/pdfjs/cmaps/',cMapPacked: true,useWorkerFetch: false,
    standardFontDataUrl: '/pdfjs/standard_fonts/',wasmUrl: '/pdfjs/wasm/',iccUrl: '/pdfjs/iccs/',
};
export async function extractPdf(path: string): Promise<string> {
    const bytes=await invoke<number[]>('read_asset',{ path });
    const task=pdfjs.getDocument({ ...pdfOptions,data: new Uint8Array(bytes) });
    const doc=await task.promise;
    try {
        let text='';
        for(let page=1;page<=doc.numPages&&text.length<80000;page++) {
            const content=await (await doc.getPage(page)).getTextContent();
            text+=`\n[p.${page}] `+content.items.map(item => 'str' in item? item.str:'').join(' ')+'\n';
        }
        return text.slice(0,80000);
    }
    finally {
        await task.destroy();
    }
}
export function PdfView({ material,onError }: {
    material: Material;
    onError: (e: unknown) => void;
}) {
    const canvas=useRef<HTMLCanvasElement>(null);
    const [page,setPage]=useState(1);
    const [count,setCount]=useState(0);
    useEffect(() => { setPage(1); },[material.id]);
    useEffect(() => {
        let cancelled=false;
        let doc: pdfjs.PDFDocumentProxy|undefined;
        let task: pdfjs.PDFDocumentLoadingTask|undefined;
        let render: pdfjs.RenderTask|undefined;
        (async () => {
            const bytes=await invoke<number[]>('read_asset',{ path: material.path }); if(cancelled)
                return; task=pdfjs.getDocument({ ...pdfOptions,data: new Uint8Array(bytes) }); doc=await task.promise; if(cancelled) {
                    await task.destroy();
                    return;
                } setCount(doc.numPages); const p=await doc.getPage(Math.min(page,doc.numPages)); if(cancelled||!canvas.current)
                return; const viewport=p.getViewport({ scale: 1.3 }); canvas.current.width=viewport.width; canvas.current.height=viewport.height; render=p.render({ canvas: canvas.current,viewport }); await render.promise;
        })().catch(e => {
            if(!cancelled)
                onError(e);
        });
        return () => {
            cancelled=true; render?.cancel(); if(task)
                void task.destroy();
        };
    },[material.path,page]);
    return <div className="pdf">
        <div className="toolbar">
            <button disabled={page<=1} onClick={() => setPage(page-1)}>
                {ko.previous}
            </button>
            <span>
                {ko.page} {page} / {count}
            </span>
            <button disabled={page>=count} onClick={() => setPage(page+1)}>
                {ko.nextPage}
            </button>
        </div>
        <canvas ref={canvas} />
    </div>;
}
