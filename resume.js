import {extractResume} from './core.js';
export async function readResume(file){
 if(file.size>2*1024*1024)throw Error('Please upload a CV smaller than 2 MB.');
 const ext=file.name.split('.').pop().toLowerCase();if(!['pdf','docx'].includes(ext))throw Error('Please choose a PDF or DOCX file.');
 const bytes=await file.arrayBuffer();let text='';
 if(ext==='pdf'){
  const pdfjs=await import('https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/build/pdf.min.mjs');
  pdfjs.GlobalWorkerOptions.workerSrc='https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/build/pdf.worker.min.mjs';
  const doc=await pdfjs.getDocument({data:bytes,isEvalSupported:false}).promise;
  try{if(doc.numPages>30)throw Error('Please use a CV of 30 pages or fewer.');for(let i=1;i<=doc.numPages;i++){const page=await doc.getPage(i);const content=await page.getTextContent();text+=content.items.map(x=>x.str||'').join(' ')+'\n';}}finally{await doc.destroy();}
 }else{
  if(!window.mammoth){await new Promise((resolve,reject)=>{const s=document.createElement('script');s.src='https://cdn.jsdelivr.net/npm/mammoth@1.9.0/mammoth.browser.min.js';s.onload=resolve;s.onerror=()=>{s.remove();reject(Error('Document reader could not load. Enter your profile manually or try again.'));};document.head.append(s);});}
  text=(await window.mammoth.extractRawText({arrayBuffer:bytes})).value;
 }
 if(text.trim().length<30)throw Error('This CV has no readable text. Use a text-based PDF/DOCX or complete your profile manually; scanned CV OCR is not included yet.');
 return {...extractResume(text),ext};
}
