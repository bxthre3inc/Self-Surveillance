// MARK: - WebUI.swift
// The entire browser-based viewer as a single self-contained HTML string.
// Served by EmbeddedServer at GET /

enum WebUI {
    static let html = #"""
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>Self Surveillance</title>
<style>
:root {
  --bg:#0D1117; --surface:#161B22; --surface2:#1C2128; --primary:#64FFDA;
  --text:#E6EDF3; --muted:#8B949E; --border:#30363D; --error:#FF5370;
  --warn:#FFD54F; --r:8px;
}
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--bg);color:var(--text);font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
  height:100dvh;display:flex;flex-direction:column;overflow:hidden}
/* ── Tab bar ── */
.tab-bar{display:flex;background:var(--surface);border-top:1px solid var(--border);
  padding-bottom:env(safe-area-inset-bottom,0px);flex-shrink:0}
.t{flex:1;padding:10px 0 8px;background:none;border:none;color:var(--muted);cursor:pointer;
  display:flex;flex-direction:column;align-items:center;gap:3px;font-size:10px}
.t.on{color:var(--primary)}
.t svg{width:22px;height:22px}
/* ── Screens ── */
.screen{display:none;flex:1;flex-direction:column;overflow:hidden}
.screen.on{display:flex}
/* ── Header ── */
.hdr{display:flex;align-items:center;padding:12px 14px;background:var(--surface);
  border-bottom:1px solid var(--border);gap:8px;flex-shrink:0}
.hdr h1{font-size:17px;font-weight:600;flex:1}
/* ── Scroll body ── */
.body{flex:1;overflow-y:auto;padding:10px;display:flex;flex-direction:column;gap:8px}
/* ── Card ── */
.card{background:var(--surface);border:1px solid var(--border);border-radius:var(--r)}
/* ── Section header inside card ── */
.sec{padding:9px 14px;font-size:11px;color:var(--muted);font-weight:600;letter-spacing:.6px;
  border-bottom:1px solid var(--border);text-transform:uppercase}
/* ── Chips ── */
.chips{display:flex;gap:6px;overflow-x:auto;padding:8px 12px;scrollbar-width:none;flex-shrink:0}
.chip{flex-shrink:0;padding:4px 10px;border-radius:20px;font-size:12px;cursor:pointer;
  background:var(--surface2);color:var(--muted);border:1px solid var(--border)}
.chip.on{background:#64FFDA22;color:var(--primary);border-color:var(--primary)}
/* ── Buttons ── */
.btn{padding:7px 14px;border-radius:var(--r);border:none;cursor:pointer;font-size:13px;font-weight:500}
.btn-p{background:var(--primary);color:#003828}
.btn-g{background:var(--surface2);color:var(--text);border:1px solid var(--border)}
.btn-r{background:#FF5370;color:#fff}
.btn-w{background:#FFD54F22;color:var(--warn);border:1px solid var(--warn)}
/* ── Rows ── */
.row{padding:10px 12px;cursor:pointer}
.row:hover{background:var(--surface2)}
.row+.row{border-top:1px solid var(--border)}
.meta{font-size:11px;color:var(--muted);margin-top:2px}
/* ── Badge ── */
.badge{display:inline-block;padding:1px 6px;border-radius:4px;font-size:10px;font-weight:500;font-family:monospace}
/* ── Search ── */
.srch{padding:7px 12px;background:var(--surface2);border:1px solid var(--border);border-radius:var(--r);
  color:var(--text);font-size:14px;width:100%;outline:none}
.srch:focus{border-color:var(--primary)}
/* ── Screen view ── */
#sv{background:#000;flex:1;display:flex;align-items:center;justify-content:center;position:relative;overflow:hidden}
#sc{max-width:100%;max-height:100%;object-fit:contain;display:none}
.rec-badge{position:absolute;top:12px;right:12px;background:rgba(255,0,0,.85);color:#fff;
  font-size:11px;font-weight:700;padding:3px 8px;border-radius:4px;display:none}
.rec-badge.on{display:block}
/* ── Live dot ── */
.dot{width:8px;height:8px;border-radius:50%;background:var(--error);animation:pulse 1.5s infinite}
.dot.on{background:var(--primary);animation:none}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.3}}
/* ── Modal ── */
.overlay{position:fixed;inset:0;background:rgba(0,0,0,.6);display:none;
  align-items:flex-end;z-index:99;padding:16px}
.overlay.on{display:flex}
.modal{background:var(--surface);border-radius:12px;width:100%;max-height:75vh;overflow-y:auto;padding:16px}
pre{background:var(--surface2);padding:10px;border-radius:6px;font-size:11px;
  overflow:auto;white-space:pre-wrap;word-break:break-all;max-height:260px}
/* ── Spinner ── */
.spin{width:32px;height:32px;border:3px solid var(--border);border-top-color:var(--primary);
  border-radius:50%;animation:rot .8s linear infinite;margin:20px auto}
@keyframes rot{to{transform:rotate(360deg)}}
/* ── Progress bar ── */
.bar-bg{background:var(--border);border-radius:2px;height:4px;margin-top:5px}
.bar{height:4px;border-radius:2px}
/* ── Toggle switch ── */
.toggle-row{display:flex;align-items:center;justify-content:space-between;
  padding:11px 14px;border-bottom:1px solid var(--border)}
.toggle-row:last-child{border-bottom:none}
.toggle-row span{font-size:14px}
.sw{position:relative;display:inline-block;width:44px;height:26px;flex-shrink:0}
.sw input{opacity:0;width:0;height:0;position:absolute}
.sl{position:absolute;inset:0;background:var(--border);border-radius:13px;cursor:pointer;transition:.2s}
.sl:before{content:"";position:absolute;width:20px;height:20px;left:3px;top:3px;
  background:#fff;border-radius:50%;transition:.2s}
input:checked+.sl{background:var(--primary)}
input:checked+.sl:before{transform:translateX(18px)}
input:disabled+.sl{opacity:.4;cursor:default}
/* ── Range slider ── */
.range-row{padding:6px 14px 10px}
.range-label{display:flex;justify-content:space-between;font-size:13px;margin-bottom:5px}
input[type=range]{width:100%;accent-color:var(--primary)}
/* ── Status pill ── */
.pill{display:inline-flex;align-items:center;gap:5px;padding:3px 9px;border-radius:20px;
  font-size:11px;font-weight:600}
.pill-g{background:#64FFDA18;color:var(--primary)}
.pill-r{background:#FF537018;color:var(--error)}
/* ── Full-width btn ── */
.full{width:100%;text-align:left;padding:11px 14px;border-radius:0;border:none;
  background:none;color:var(--text);cursor:pointer;font-size:14px;border-bottom:1px solid var(--border)}
.full:last-child{border-bottom:none}
.full:hover{background:var(--surface2)}
.full:disabled{color:var(--muted);cursor:default}
</style>
</head>
<body>

<!-- ═══ DASHBOARD ════════════════════════════════════════════════════════════ -->
<div id="s-dash" class="screen on">
  <div class="hdr">
    <h1>Dashboard</h1>
    <span id="wifi-url" style="font-size:11px;color:var(--muted);font-family:monospace"></span>
    <button class="btn btn-g" style="font-size:12px;padding:5px 10px" onclick="loadSummary()">↻</button>
  </div>
  <div id="device-chips" class="chips"></div>
  <div id="dash-body" class="body"></div>
</div>

<!-- ═══ LIVE ══════════════════════════════════════════════════════════════════ -->
<div id="s-live" class="screen">
  <div class="hdr">
    <h1>Live</h1>
    <div class="dot" id="ldot"></div>
    <button class="btn btn-g" style="font-size:12px;padding:5px 10px" id="pbtn" onclick="togglePause()">Pause</button>
    <button class="btn btn-g" style="font-size:12px;padding:5px 10px" onclick="clearLive()">Clear</button>
  </div>
  <div class="chips" id="lchips"></div>
  <div class="card" style="flex:1;overflow-y:auto;border-radius:0;border-left:none;border-right:none">
    <div id="llist"></div>
  </div>
</div>

<!-- ═══ LOGS ══════════════════════════════════════════════════════════════════ -->
<div id="s-logs" class="screen">
  <div class="hdr"><h1>Logs</h1></div>
  <div style="padding:8px 12px">
    <input class="srch" type="search" placeholder="Search…" oninput="debSearch(this.value)">
  </div>
  <div class="chips" id="logchips"></div>
  <div class="card" style="flex:1;overflow-y:auto;border-radius:0;border-left:none;border-right:none"
       id="logscroll" onscroll="onLogScroll()">
    <div id="loglist"></div>
    <div id="logspinner" style="display:none"><div class="spin"></div></div>
  </div>
</div>

<!-- ═══ SCREEN ════════════════════════════════════════════════════════════════ -->
<div id="s-screen" class="screen">
  <div class="hdr">
    <h1>Screen Mirror</h1>
    <span id="fpslabel" style="font-size:12px;color:var(--muted);font-family:monospace"></span>
    <button class="btn btn-g" id="connbtn" style="font-size:12px;padding:5px 10px" onclick="toggleScreenWS()">Connect</button>
  </div>
  <div id="sv">
    <div id="sph" style="text-align:center;color:var(--muted)">
      <div style="font-size:48px;margin-bottom:8px">📱</div>
      <div style="font-size:14px">Tap Connect to mirror iPhone screen</div>
    </div>
    <canvas id="sc"></canvas>
    <div class="rec-badge" id="recbadge">⏺ REC</div>
  </div>
  <div style="display:flex;align-items:center;justify-content:space-between;padding:10px 16px;
    background:var(--surface);border-top:1px solid var(--border);flex-shrink:0">
    <div>
      <div style="font-size:10px;color:var(--muted)">Frames</div>
      <div id="fcount" style="font-family:monospace;font-size:15px">0</div>
    </div>
    <button class="btn btn-r" id="recbtn" onclick="toggleRec()" style="display:none">⏺ Record</button>
    <div id="recpath" style="font-size:10px;color:var(--muted);text-align:right;max-width:140px"></div>
  </div>
</div>

<!-- ═══ CONTROLS ══════════════════════════════════════════════════════════════ -->
<div id="s-ctrl" class="screen">
  <div class="hdr">
    <h1>Controls</h1>
    <button class="btn btn-g" style="font-size:12px;padding:5px 10px" onclick="loadStatus()">↻</button>
  </div>
  <div class="body">

    <!-- Collectors -->
    <div class="card">
      <div class="sec">Collectors</div>
      <div id="coll-list">
        <div style="padding:20px;text-align:center"><div class="spin"></div></div>
      </div>
    </div>

    <!-- Screen capture -->
    <div class="card">
      <div class="sec">Screen Capture</div>
      <div class="toggle-row">
        <span>Streaming</span>
        <div style="display:flex;align-items:center;gap:8px">
          <span id="scr-pill" class="pill pill-r">Off</span>
          <label class="sw">
            <input type="checkbox" id="scr-sw" onchange="toggleCapture(this)">
            <span class="sl"></span>
          </label>
        </div>
      </div>
      <div class="range-row" style="margin-top:4px">
        <div class="range-label"><span>FPS</span><span id="fps-val">10</span></div>
        <input type="range" id="fps-sl" min="1" max="30" value="10"
               oninput="document.getElementById('fps-val').textContent=this.value">
      </div>
      <div class="range-row">
        <div class="range-label"><span>JPEG Quality</span><span id="q-val">50%</span></div>
        <input type="range" id="q-sl" min="10" max="100" value="50"
               oninput="document.getElementById('q-val').textContent=this.value+'%'">
      </div>
      <div style="padding:8px 14px 14px">
        <button class="btn btn-p" style="width:100%" onclick="saveSettings()">Save Settings</button>
      </div>
    </div>

    <!-- Data -->
    <div class="card">
      <div class="sec">Data</div>
      <button class="full" onclick="exportLogs()">⬇&nbsp; Export All Logs (.ndjson)</button>
      <button class="full" id="integ-btn" onclick="checkIntegrity()">✓&nbsp; Verify Data Integrity</button>
      <div id="integ-result" style="padding:0 14px 12px;font-size:12px;display:none"></div>
    </div>

    <!-- Sync engine -->
    <div class="card">
      <div class="sec">Sync Engine</div>
      <div style="padding:10px 14px;display:flex;flex-direction:column;gap:8px">
        <div style="font-size:12px;color:var(--muted)">Backend server URL (optional cloud sync)</div>
        <input class="srch" id="sync-url" type="url" placeholder="http://192.168.1.x:3000"
               style="font-family:monospace;font-size:13px">
        <button class="btn btn-g" style="align-self:flex-start" onclick="saveSyncURL()">Save URL</button>
      </div>
    </div>

  </div><!-- /.body -->
</div>

<!-- ═══ TAB BAR ═══════════════════════════════════════════════════════════════ -->
<nav class="tab-bar">
  <button class="t on" onclick="go('dash',this)">
    <svg fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
      <rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/>
      <rect x="3" y="14" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/>
    </svg>Dashboard
  </button>
  <button class="t" onclick="go('live',this)">
    <svg fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
      <polyline points="22 12 18 12 15 21 9 3 6 12 2 12"/>
    </svg>Live
  </button>
  <button class="t" onclick="go('logs',this)">
    <svg fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
      <line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/>
      <line x1="8" y1="18" x2="21" y2="18"/><line x1="3" y1="6" x2="3.01" y2="6"/>
      <line x1="3" y1="12" x2="3.01" y2="12"/><line x1="3" y1="18" x2="3.01" y2="18"/>
    </svg>Logs
  </button>
  <button class="t" onclick="go('screen',this)">
    <svg fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
      <rect x="5" y="2" width="14" height="20" rx="2"/>
      <line x1="12" y1="18" x2="12.01" y2="18"/>
    </svg>Screen
  </button>
  <button class="t" onclick="go('ctrl',this)">
    <svg fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
      <circle cx="12" cy="12" r="3"/>
      <path d="M19.07 4.93a10 10 0 0 1 0 14.14M4.93 4.93a10 10 0 0 0 0 14.14"/>
      <path d="M15.54 8.46a5 5 0 0 1 0 7.07M8.46 8.46a5 5 0 0 0 0 7.07"/>
    </svg>Controls
  </button>
</nav>

<!-- ═══ DETAIL MODAL ══════════════════════════════════════════════════════════ -->
<div class="overlay" id="overlay" onclick="if(event.target===this)closeModal()">
  <div class="modal" id="modal"></div>
</div>

<script>
// ─── Constants ───────────────────────────────────────────────────────────────
const COLORS = {
  app_usage:'#64FFDA',notifications:'#4FC3F7',clipboard:'#FFD54F',
  network:'#81C784',packet_flow:'#EF9A9A',location:'#CE93D8',
  health:'#F48FB1',system_events:'#FFCC02',dns_query:'#80DEEA',
  bluetooth:'#80CBC4',wifi:'#A5D6A7',contacts:'#FFAB91',
  photo_library:'#CE93D8',files:'#B0BEC5',notes:'#FFE082',
  keychain:'#EF9A9A',calendar:'#80DEEA'
};
const COLL_LABELS = {
  app_usage:'App Usage', notifications:'Notifications', clipboard:'Clipboard',
  photo_library:'Photo Library', contacts:'Contacts', calendar:'Calendar',
  location:'Location', health:'Health', network:'Network & WiFi',
  files:'Files & Notes', system_events:'System Events'
};
const SRCS = Object.keys(COLORS);

function col(src){ return COLORS[src]||'#90A4AE'; }
function fmt(s){ return s.replace(/_/g,' ').replace(/\b\w/g,c=>c.toUpperCase()); }

// ─── Tab navigation ───────────────────────────────────────────────────────────
function go(name, btn){
  document.querySelectorAll('.screen').forEach(e=>e.classList.remove('on'));
  document.querySelectorAll('.t').forEach(b=>b.classList.remove('on'));
  document.getElementById('s-'+name).classList.add('on');
  btn.classList.add('on');
  if(name==='live' && !lws) connectLive();
  if(name==='dash') loadSummary();
  if(name==='ctrl') loadStatus();
}

// ─── Dashboard ────────────────────────────────────────────────────────────────
let selDev = null;

async function loadSummary(){
  const ip = await fetch('/ip').then(r=>r.text()).catch(()=>'');
  if(ip) document.getElementById('wifi-url').textContent='http://'+ip;

  const url='/api/logs/summary'+(selDev?'?deviceID='+selDev:'');
  const s=await fetch(url).then(r=>r.json()).catch(()=>null);
  if(!s) return;

  const dc=document.getElementById('device-chips');
  if(s.devices && s.devices.length>1){
    dc.innerHTML=[null,...s.devices].map(d=>`
      <span class="chip${(d===null&&!selDev)||(d&&d.deviceID===selDev)?' on':''}"
            onclick="selDevice('${d?d.deviceID:''}')">
        ${d?d.deviceName:'All'}
      </span>`).join('');
  } else { dc.innerHTML=''; }

  const body=document.getElementById('dash-body');
  body.innerHTML='';

  body.insertAdjacentHTML('beforeend',`
    <div class="card" style="padding:14px 16px">
      <div style="font-size:30px;font-weight:700;color:var(--primary)">${(s.totalEntries||0).toLocaleString()}</div>
      <div style="font-size:13px;color:var(--muted)">Total Events</div>
      ${s.oldestTimestamp?`<div style="font-size:11px;color:var(--muted);margin-top:6px">
        ${s.oldestTimestamp.slice(0,10)} → ${(s.newestTimestamp||'').slice(0,10)}</div>`:''}
    </div>`);

  const total=s.totalEntries||1;
  const sorted=Object.entries(s.bySource||{}).sort((a,b)=>b[1]-a[1]);
  for(const [src,cnt] of sorted){
    const pct=Math.round(cnt/total*100);
    const c=col(src);
    body.insertAdjacentHTML('beforeend',`
      <div class="card" style="padding:10px 14px;cursor:pointer"
           onclick="filterLogs('${src}')">
        <div style="display:flex;justify-content:space-between">
          <span style="font-size:13px">${fmt(src)}</span>
          <span style="font-weight:600;color:${c}">${cnt.toLocaleString()}</span>
        </div>
        <div class="bar-bg"><div class="bar" style="background:${c};width:${pct}%"></div></div>
      </div>`);
  }
}

function selDevice(id){ selDev=id||null; loadSummary(); }

function filterLogs(src){
  logFilt=src; buildLogChips(); resetLogs();
  // switch to logs tab
  document.querySelectorAll('.screen').forEach(e=>e.classList.remove('on'));
  document.querySelectorAll('.t').forEach(b=>b.classList.remove('on'));
  document.getElementById('s-logs').classList.add('on');
  document.querySelectorAll('.t')[2].classList.add('on');
}

// ─── Live Feed ────────────────────────────────────────────────────────────────
let lws=null, paused=false, lfilt=null;

function buildLChips(){
  const el=document.getElementById('lchips');
  el.innerHTML=[null,...SRCS.slice(0,9)].map(s=>`
    <span class="chip${lfilt===s?' on':''}" onclick="setLFilt(${s?`'${s}'`:'null'})">
      ${s?fmt(s):'All'}
    </span>`).join('');
}
function setLFilt(s){ lfilt=s; buildLChips(); }

function connectLive(){
  if(lws) return;
  const ws=new WebSocket(`ws://${location.host}/live`);
  lws=ws;
  const dot=document.getElementById('ldot');
  ws.onopen=()=>dot.classList.add('on');
  ws.onclose=()=>{ dot.classList.remove('on'); lws=null; setTimeout(connectLive,3000); };
  ws.onmessage=e=>{
    if(paused) return;
    let entry; try{ entry=JSON.parse(e.data); }catch(){ return; }
    if(lfilt && entry.source!==lfilt) return;
    const c=col(entry.source);
    const list=document.getElementById('llist');
    const div=document.createElement('div');
    div.className='row';
    div.innerHTML=`
      <div style="display:flex;gap:8px;align-items:flex-start">
        <span class="badge" style="background:${c}22;color:${c};margin-top:1px">${entry.source.replace(/_/g,'·')}</span>
        <div style="flex:1;min-width:0">
          <div style="font-size:13px;font-weight:500">${entry.eventType}</div>
          ${entry.appDisplayName?`<div class="meta">${entry.appDisplayName}</div>`:''}
        </div>
        <div style="font-size:10px;color:var(--muted);font-family:monospace;white-space:nowrap">
          ${(entry.timestamp||'').slice(11,19)}
        </div>
      </div>`;
    div.onclick=()=>openModal(entry);
    list.prepend(div);
    while(list.children.length>300) list.lastChild.remove();
  };
}

function togglePause(){ paused=!paused; document.getElementById('pbtn').textContent=paused?'Resume':'Pause'; }
function clearLive(){ document.getElementById('llist').innerHTML=''; }

// ─── Log Browser ─────────────────────────────────────────────────────────────
let logOff=0,logLoading=false,logMore=true,logFilt=null,logQ='',debTimer=null;

function buildLogChips(){
  const el=document.getElementById('logchips');
  el.innerHTML=[null,...SRCS].map(s=>`
    <span class="chip${logFilt===s?' on':''}" onclick="setLogFilt(${s?`'${s}'`:'null'})">
      ${s?fmt(s).replace(/ /g,'&nbsp;'):'All'}
    </span>`).join('');
}
function setLogFilt(s){ logFilt=s; buildLogChips(); resetLogs(); }
function debSearch(v){ clearTimeout(debTimer); debTimer=setTimeout(()=>{ logQ=v; resetLogs(); },400); }
function resetLogs(){ logOff=0; logMore=true; document.getElementById('loglist').innerHTML=''; loadLogs(); }

async function loadLogs(){
  if(logLoading||!logMore) return;
  logLoading=true;
  document.getElementById('logspinner').style.display='block';
  const p=new URLSearchParams({limit:50,offset:logOff});
  if(logFilt) p.set('source',logFilt);
  if(logQ)    p.set('search',logQ);
  const entries=await fetch('/api/logs?'+p).then(r=>r.json()).catch(()=>[]);
  const list=document.getElementById('loglist');
  for(const e of entries){
    const c=col(e.source);
    const div=document.createElement('div');
    div.className='row';
    div.innerHTML=`
      <div style="display:flex;gap:6px;align-items:center">
        <span style="font-size:13px;font-weight:500;flex:1">${e.eventType}</span>
        <span style="font-size:11px;color:${c}">${fmt(e.source)}</span>
        <span style="font-size:10px;color:var(--muted);font-family:monospace">#${e.sequenceNumber}</span>
      </div>
      ${e.appDisplayName?`<div class="meta">${e.appDisplayName}</div>`:''}
      <div class="meta">${(e.timestamp||'').replace('T',' ').slice(0,19)}</div>`;
    div.onclick=()=>openModal(e);
    list.appendChild(div);
  }
  logOff+=entries.length;
  logMore=entries.length===50;
  logLoading=false;
  document.getElementById('logspinner').style.display='none';
}

function onLogScroll(){
  const el=document.getElementById('logscroll');
  if(el.scrollTop+el.clientHeight>=el.scrollHeight-120) loadLogs();
}

// ─── Detail Modal ─────────────────────────────────────────────────────────────
function openModal(e){
  document.getElementById('modal').innerHTML=`
    <div style="font-size:16px;font-weight:600;margin-bottom:8px">${e.eventType}</div>
    <div style="font-size:12px;color:var(--muted);margin-bottom:12px;line-height:1.6">
      ${fmt(e.source)} · ${e.category||''}<br>
      ${(e.timestamp||'').replace('T',' ').slice(0,19)} · #${e.sequenceNumber}<br>
      ${e.deviceName||''} (iOS ${e.iOSVersion||''})
      ${e.appBundleID?'<br>'+e.appBundleID:''}
    </div>
    <pre>${JSON.stringify(e.payload,null,2)}</pre>
    <button class="btn btn-g" style="margin-top:12px;width:100%" onclick="closeModal()">Close</button>`;
  document.getElementById('overlay').classList.add('on');
}
function closeModal(){ document.getElementById('overlay').classList.remove('on'); }

// ─── Screen Mirror ────────────────────────────────────────────────────────────
let sws=null, fc=0, fpsF=0, fpsT=Date.now(), mr=null, rc=[];

function toggleScreenWS(){
  if(sws){ sws.close(); sws=null; return; }
  connectScreenWS();
}

function connectScreenWS(){
  const canvas=document.getElementById('sc');
  const ctx=canvas.getContext('2d');
  const ws=new WebSocket(`ws://${location.host}/screen`);
  ws.binaryType='arraybuffer';
  sws=ws;
  ws.onopen=()=>{
    document.getElementById('connbtn').textContent='Disconnect';
    document.getElementById('sph').style.display='none';
    canvas.style.display='block';
    document.getElementById('recbtn').style.display='block';
  };
  ws.onclose=()=>{
    document.getElementById('connbtn').textContent='Connect';
    document.getElementById('recbtn').style.display='none';
    canvas.style.display='none';
    document.getElementById('sph').style.display='block';
    if(mr && mr.state!=='inactive') mr.stop();
    sws=null;
  };
  ws.onmessage=e=>{
    const blob=new Blob([e.data],{type:'image/jpeg'});
    const url=URL.createObjectURL(blob);
    const img=new Image();
    img.onload=()=>{
      if(canvas.width!==img.width||canvas.height!==img.height){
        canvas.width=img.width; canvas.height=img.height;
      }
      ctx.drawImage(img,0,0);
      URL.revokeObjectURL(url);
      fc++; document.getElementById('fcount').textContent=fc;
      fpsF++;
      const now=Date.now();
      if(now-fpsT>=1000){
        document.getElementById('fpslabel').textContent=fpsF+' fps';
        fpsF=0; fpsT=now;
      }
    };
    img.src=url;
  };
}

function toggleRec(){
  if(mr && mr.state==='recording'){
    mr.stop();
    document.getElementById('recbtn').textContent='⏺ Record';
    document.getElementById('recbadge').classList.remove('on');
  } else { startRec(); }
}

function startRec(){
  const canvas=document.getElementById('sc');
  const stream=canvas.captureStream(10);
  rc=[];
  const mime=MediaRecorder.isTypeSupported('video/webm;codecs=vp9')?'video/webm;codecs=vp9':'video/webm';
  mr=new MediaRecorder(stream,{mimeType:mime});
  mr.ondataavailable=e=>{ if(e.data.size>0) rc.push(e.data); };
  mr.onstop=()=>{
    const blob=new Blob(rc,{type:'video/webm'});
    const url=URL.createObjectURL(blob);
    const a=document.createElement('a');
    const name=`screen_${Date.now()}.webm`;
    a.href=url; a.download=name; a.click();
    setTimeout(()=>URL.revokeObjectURL(url),5000);
    document.getElementById('recpath').textContent=name;
  };
  mr.start(1000);
  document.getElementById('recbtn').textContent='■ Stop';
  document.getElementById('recbadge').classList.add('on');
}

// ─── Controls ────────────────────────────────────────────────────────────────
let statusCache = {};

async function loadStatus(){
  let s;
  try { s = await fetch('/api/status').then(r=>r.json()); }
  catch(_){ return; }
  statusCache = s;

  // Render collector toggles
  const states = s.collectors || {};
  document.getElementById('coll-list').innerHTML =
    Object.entries(COLL_LABELS).map(([key,label])=>`
      <div class="toggle-row">
        <span>${label}</span>
        <label class="sw">
          <input type="checkbox" data-coll="${key}" ${states[key]?'checked':''}
                 onchange="toggleColl(this)">
          <span class="sl"></span>
        </label>
      </div>`).join('');

  // Screen capture
  const streaming = s.screenStreaming || false;
  const sw = document.getElementById('scr-sw');
  sw.checked = streaming;
  const pill = document.getElementById('scr-pill');
  pill.textContent = streaming ? 'Live' : 'Off';
  pill.className = 'pill ' + (streaming ? 'pill-g' : 'pill-r');

  // Settings sliders
  const cfg = s.settings || {};
  const fps = cfg.fps || 10;
  const q   = Math.round((cfg.quality || 0.5) * 100);
  document.getElementById('fps-sl').value = fps;
  document.getElementById('fps-val').textContent = fps;
  document.getElementById('q-sl').value = q;
  document.getElementById('q-val').textContent = q + '%';
}

async function toggleColl(input){
  const name = input.dataset.coll;
  const on   = input.checked;
  try {
    await fetch('/api/collector', {
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body: JSON.stringify({name, on})
    });
  } catch(_){ input.checked = !on; } // revert on network error
}

async function toggleCapture(input){
  const streaming = input.checked;
  const pill = document.getElementById('scr-pill');
  try {
    await fetch('/api/screen', {
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body: JSON.stringify({streaming})
    });
    pill.textContent = streaming ? 'Live' : 'Off';
    pill.className = 'pill ' + (streaming ? 'pill-g' : 'pill-r');
  } catch(_){ input.checked = !streaming; }
}

async function saveSettings(){
  const fps     = parseFloat(document.getElementById('fps-sl').value);
  const quality = parseFloat(document.getElementById('q-sl').value) / 100;
  try {
    await fetch('/api/settings', {
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body: JSON.stringify({fps, quality})
    });
  } catch(_){}
}

function exportLogs(){
  const a = document.createElement('a');
  a.href = '/api/export';
  a.click();
}

async function checkIntegrity(){
  const btn = document.getElementById('integ-btn');
  const res = document.getElementById('integ-result');
  btn.disabled = true;
  btn.textContent = '… Checking';
  res.style.display = 'none';
  try {
    const r = await fetch('/api/integrity').then(x=>x.json());
    res.style.display = 'block';
    if(!r.issues || r.issues.length===0){
      res.style.color = 'var(--primary)';
      res.textContent = `✓ Chain intact — ${r.checked} log file(s) verified`;
    } else {
      res.style.color = 'var(--error)';
      res.textContent = `⚠ ${r.issues.length} integrity issue(s) in ${r.checked} file(s)`;
    }
  } catch(_){
    res.style.display = 'block';
    res.style.color = 'var(--error)';
    res.textContent = 'Could not reach device';
  }
  btn.disabled = false;
  btn.textContent = '✓  Verify Data Integrity';
}

async function saveSyncURL(){
  const url = document.getElementById('sync-url').value.trim();
  if(!url) return;
  try {
    await fetch('/api/settings', {
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body: JSON.stringify({syncURL: url})
    });
  } catch(_){}
}

// ─── Init ─────────────────────────────────────────────────────────────────────
buildLChips();
buildLogChips();
loadSummary();
loadLogs();
</script>
</body>
</html>
"""#
}
