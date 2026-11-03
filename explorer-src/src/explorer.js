// explorer UI v5.0 — data machinery, a verbatim port of the UI v4.4 engine:
//  · v4.3 fetch resilience (in-flight guard, self-scheduling loop)
//  · v4.3.1 engine-independent deadlines (Promise.race backstop, no-abort 3-failure breaker, 8 s boot watchdog)
//  · v4.4 steady 10 s cadence (no backoff, no reconnecting chip, no wake probes — owner order, Task 45)
//  · content-signature change detection (rail + list refresh only on real change)
//  · static-copy graceful mode + manual live-recovery
import { reactive, shallowRef } from 'vue'
import { fmtDur } from './util.js'
import { snack } from './snack.js'

/* ================= state ================= */
export const S=reactive({q:"",type:"all",task:null,sort:{col:"mtime",dir:"desc"},root:"all",view:"grid",page:1});
export const PER_PAGE=100;
export const META=shallowRef(null);        // per-poll feed (stats/chips/footer read this)
export const TASKS=shallowRef(null);       // rail data — replaced ONLY on real change (content signature)
export const PAGE=shallowRef(null);
export const PAGE_MAP={};                  // key -> file (server page map)
export const ui=reactive({
  clock:"--:--:--", footer:"loading…", lastScan:"—",
  error:false, static:false, staticLive:false, listAnim:true,
  spinning:false, fab:false, themeDark:false,
});

/* ================= v4.3/v4.3.1/v4.4 constants ================= */
const FETCH_TIMEOUT_MS=5000;
const POLL_BASE_MS=10000;
const CAN_ABORT=(typeof AbortController!=="undefined");
const RECOVER_MS=1000;
const BOOT_WATCHDOG_MS=8000;
let pollTimer=null, metaInFlight=false, connFails=0, lastSig="", firstLoadDone=false,
    TASKS_DONE=false, bootWatchdogFired=false, RECOVER_ARMED=false, scanBusy=false,
    AUTO_BROKE_OUT=false;   /* Task 67: static→live auto-breakout fired flag (once per page) */

/* ================= v4.3.1 fetch deadline ================= */
export function fetchT(url,ms){
  ms=ms||FETCH_TIMEOUT_MS;
  const ctl=CAN_ABORT?new AbortController():null;
  const t=ctl?setTimeout(()=>ctl.abort(),ms):null;
  const p=fetch(url,{cache:"no-store",signal:ctl?ctl.signal:undefined})
    .finally(()=>{if(t)clearTimeout(t)});
  const bs=new Promise((_,rej)=>{setTimeout(()=>{const e=new Error("signal timed out");e.name="AbortError";rej(e)},ms+250)});
  bs.catch(()=>{});
  return Promise.race([p,bs]);
}
export function schedulePoll(ms){clearTimeout(pollTimer);pollTimer=setTimeout(pollOnce,ms)}
export async function pollOnce(){
  if(metaInFlight)return null;
  metaInFlight=true;
  try{return await loadMeta()}
  catch(_){schedulePoll(POLL_BASE_MS);return false}
  finally{metaInFlight=false}
}
export function probeNow(){clearTimeout(pollTimer);return pollOnce()}

/* ================= list (server-paged) ================= */
export function listURL(){
  const p=new URLSearchParams({root:S.root,sort:S.sort.col,dir:S.sort.dir,
    page:String(S.page),per_page:String(PER_PAGE)});
  if(S.q)p.set("q",S.q);
  if(S.type!=="all")p.set("type",S.type);
  if(S.task)p.set("task",S.task);
  return "/api/list?"+p.toString();
}
export async function loadList(silent){
  try{
    const d=await(await fetchT(listURL())).json();
    PAGE.value=d;
    for(const k in PAGE_MAP)delete PAGE_MAP[k];
    d.files.forEach(f=>PAGE_MAP[f.key]=f);
    if(d.page<S.page)S.page=d.page;              /* server clamped the page */
    ui.listAnim=!silent;                          /* v4.1: animate on first load + user actions; silent on background refresh */
    ui.error=false;
    if(!firstLoadDone&&!ui.static){firstLoadDone=true}
  }catch(e){
    if(!silent&&!ui.static&&firstLoadDone)snack("Connection to explorer.py lost — retrying every 10 s","Retry",()=>loadList());
    if(!PAGE.value&&!ui.static)ui.error=true;
  }
}

/* ================= meta (slim poll) ================= */
export async function loadMeta(){
  try{
    const d=await(await fetchT("/api/files?max=0")).json();
    if(ui.static){   /* live feed reachable from this origin — recover the window */
      if(d&&d.server&&d.server.pid){
        if(!ui.staticLive){ui.staticLive=true;
          /* Task 67 (owner order "popup preview platform mati permanent"): the
             platform file-preview chrome that wrapped this static copy is
             replaced by the LIVE app at top level the moment the live feed
             answers on this origin — auto-breakout, ONCE per page (guarded:
             a replace that lands somewhere static again must not loop).
             Supersedes the v4.2 "manual live-recovery, never auto-navigates"
             note per this owner order; the banner + button stay as the
             fallback when top-level navigation is sandbox-blocked. */
          if(!AUTO_BROKE_OUT){AUTO_BROKE_OUT=true;goLive()}
          ui.footer="live explorer reachable on this origin — recovering the live view…"}
      }
      schedulePoll(POLL_BASE_MS);
      return true;
    }
    META.value=d;
    const sig=d.content_sig||d.inventory_built||"";   /* v4.1 content signature (old servers fall back to the timestamp) */
    const changed=lastSig&&sig&&sig!==lastSig;
    /* stats/chips recompute from META per poll (cheap); the rail ONLY on real change (scroll + churn preserved) */
    if(changed||!TASKS_DONE){TASKS.value=(d.tasks||[]);TASKS_DONE=true}
    const sv=d.server,up=Date.now()/1000-sv.started_epoch;
    const st=(d.stats&&d.stats.total_files!=null)?d.stats.total_files:"?";
    ui.lastScan=st+" files @ "+new Date().toLocaleTimeString("en-US");
    ui.footer=`PID ${sv.pid} · up ${fmtDur(up)} · auto-refresh every 10 s · scanned ${st} files · inventory built ${d.inventory_built}`;
    if(changed&&firstLoadDone){
      loadList(true);                            /* data actually changed — silent refresh, no animation replay */
    }else if(PAGE.value===null&&bootWatchdogFired){
      loadList(true);                            /* v4.3.1: cold start into a dead origin — the boot list never completed */
    }
    lastSig=sig;
    firstLoadDone=true;
    connFails=0;schedulePoll(POLL_BASE_MS);       /* v4.4: healthy — reset the no-abort breaker, steady cadence resumes */
    return true;
  }catch(e){
    if(e instanceof SyntaxError)ui.static=true;   /* origin answered, but not explorer.py JSON */
    if(ui.static){
      ui.footer="static copy — explorer.py is not serving this page";
      if(ui.staticLive){ui.staticLive=false}
      else if(!firstLoadDone){/* first-paint static banner */}
      if(!RECOVER_ARMED&&location.protocol!=="file:"){RECOVER_ARMED=true;setTimeout(()=>pollOnce(),RECOVER_MS)}
      schedulePoll(POLL_BASE_MS);                 /* v4.3: bounded static probes — a hung origin cannot stack them */
      return false;
    }
    connFails++;                                  /* v4.4: steady cadence — no backoff, no reconnecting chip (owner order, Task 45) */
    const paused=!(CAN_ABORT||connFails<3);       /* v4.3.1 breaker KEPT: engines that cannot abort stop auto-polling after 3 failures */
    ui.footer=(paused
      ?"explorer.py not answering — automatic retry paused on this engine (tap Rescan to retry)"
      :"explorer.py not answering — retrying automatically every "+Math.round(POLL_BASE_MS/1000)+" s")
      +" · the sandbox may be asleep (it wakes when you send a chat message) · last scan: "+ui.lastScan;
    if(!firstLoadDone)ui.error=true;
    if(connFails===1)snack("Connection to explorer.py lost — retrying every 10 s","Retry now",probeNow);
    if(!paused)schedulePoll(POLL_BASE_MS);        /* steady retry — the next successful poll IS the recovery */
    return false;
  }
}

/* ================= states ================= */
export function resetErrorAndRetry(){
  ui.error=false;
  probeNow();
  loadList();
}
export function goLive(){const u=new URL("/",location.href).href;   /* absolute: the top window may be another origin */
  try{top.location.replace(u)}   /* platform file preview at top level: recover the whole window */
  catch(e){try{location.replace(u)}catch(_){}}}   /* sandboxed/cross-origin frame: at least recover this frame */

/* ================= copy path ================= */
export async function copyPath(f){
  if(!f)return;
  let base="";
  if(META.value&&META.value.roots){
    const lbl=f.key.split("/")[0];
    const r=META.value.roots.find(x=>x.label===lbl);
    if(r&&r.path)base=r.path.replace(/\/+$/,"")+"/";
  }
  const p=base?base+f.rel:f.key;   /* f.key = "<label>/<rel>" — the server-side label path */
  let ok=true;
  try{await navigator.clipboard.writeText(p)}catch(e){ok=false;
    try{const ta=document.createElement("textarea");ta.value=p;ta.style.position="fixed";ta.style.opacity="0";
      document.body.appendChild(ta);ta.select();document.execCommand("copy");ta.remove();ok=true}catch(e2){}}
  snack(ok?"Path copied: "+p:"Failed to copy the path");
}

/* ================= boot + watchdog + scan ================= */
export function boot(){
  /* static-copy detection — explorer.py serves this UI ONLY at "/" and "/index.html" on its own origin */
  ui.static=(location.protocol==="file:")||(location.pathname!=="/"&&location.pathname!=="/index.html");
  pollOnce();                                           /* v4.3: guarded boot poll — starts the resilient loop */
  if(!ui.static)loadList(true);else ui.staticLive=false;/* v4.2: first load renders SILENT — no entrance burst at open */
  setTimeout(()=>{                                      /* v4.3.1 boot watchdog — the ABSOLUTE anti-silent-freeze guarantee */
    if(bootWatchdogFired||ui.static||firstLoadDone)return;
    bootWatchdogFired=true;
    if(metaInFlight)metaInFlight=false;                 /* un-wedge the guard so probing can continue */
    if(!connFails)connFails=1;
    ui.error=true;
    ui.footer="explorer.py not answering — retrying automatically every "+Math.round(POLL_BASE_MS/1000)+" s · the sandbox may be asleep (it wakes when you send a chat message) · last scan: "+ui.lastScan;
    if(CAN_ABORT||connFails<3)schedulePoll(POLL_BASE_MS);
  },BOOT_WATCHDOG_MS);
}
export async function onScan(){
  if(scanBusy)return;
  scanBusy=true;ui.spinning=true;
  try{
    const ok=await probeNow();
    if(ok===null){snack("A scan is already in progress…")}
    else if(ok&&!ui.static){
      await loadList(true);                            /* silent refresh — no animation replay */
      snack("Scan complete — "+ui.lastScan);
    }else if(!ui.static){
      snack("Scan failed — explorer.py is not answering; retrying automatically");
    }                                                 /* static copies: the probe result speaks through the banner */
  }finally{ui.spinning=false;scanBusy=false}
}
