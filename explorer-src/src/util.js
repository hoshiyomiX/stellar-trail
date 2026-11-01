// explorer UI v5.0 (miuix-vue migration, Task 53) — utils ported verbatim from UI v4.4
export const esc=s=>String(s).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
export const I=(n,cls="ic")=>`<svg class="${cls}" aria-hidden="true"><use href="#i-${n}"/></svg>`;
export const fmtSize=n=>{if(n<1024)return n+" B";const u=["KB","MB","GB"];let i=-1;do{n/=1024;i++}while(n>=1024&&i<2);return n.toFixed(n>=100?0:1)+" "+u[i]};
export const fmtDate=t=>new Date(t*1000).toLocaleString("en-US",{dateStyle:"medium",timeStyle:"short"});
export const fmtRel=t=>{const d=Date.now()/1000-t;if(d<60)return"just now";if(d<3600)return Math.floor(d/60)+" min ago";if(d<86400)return Math.floor(d/3600)+" h ago";if(d<604800)return Math.floor(d/86400)+" d ago";return fmtDate(t)};
export const fmtDur=s=>{s=Math.max(0,Math.floor(s));const h=Math.floor(s/3600),m=Math.floor(s%3600/60),x=s%60;return(h?h+"h ":"")+(m?m+"m ":"")+x+"s"};
export const TYPES=["doc","pdf","img","data","pkg","code","office","other"];
export const EXTICON={pdf:"pdf",md:"doc",txt:"doc",rtf:"doc",html:"code",htm:"code",json:"data",csv:"data",
  tsv:"data",xlsx:"data",xls:"data",png:"img",jpg:"img",jpeg:"img",gif:"img",svg:"img",webp:"img",
  bmp:"img",ico:"img",skill:"pkg",zip:"pkg",tar:"pkg",gz:"pkg",whl:"pkg",py:"code",sh:"code",
  js:"code",ts:"code",css:"code",docx:"office",doc:"office",pptx:"office",ppt:"office"};
export const TYPEICON={doc:"doc",pdf:"pdf",img:"img",data:"data",pkg:"pkg",code:"code",office:"office",other:"file"};
export const iconFor=f=>EXTICON[(f.ext||"").toLowerCase()]||TYPEICON[f.type]||"file";
export const classFor=f=>EXTICON[(f.ext||"").toLowerCase()]||f.type||"other";
