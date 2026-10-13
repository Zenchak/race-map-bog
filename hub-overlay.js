(()=>{
'use strict';

const BUILD='2026.10.13-0815';
const state={types:new Set(),races:[]};

const norm=v=>String(v??'').replace(/\s+/g,' ').trim();

function raceTypes(r){
  const all=norm([r.name,r.distance,r.discipline].filter(Boolean).join(' ')).toLowerCase();
  const nd=norm([r.name,r.distance].filter(Boolean).join(' ')).toLowerCase();
  const out=new Set();
  const isTri=/(?:\btriathlon\b|\bironman\b|70[.,]3|\bolimpic[oa]\b|\bolympic\b|\bsprint\b|\bmedio\b|middle\s*distance|\bfull\b)/i.test(all);
  if(isTri){
    if(/\b(?:super\s*)?sprint\b/i.test(all))out.add('sprint');
    if(/\b(?:olimpic[oa]|olympic)\b/i.test(all))out.add('olimpico');
    if(/(?:70[.,]3|half\s*ironman|ironman\s*70|middle\s*distance|\bmedio\b)/i.test(all))out.add('70.3');
    if(/(?:ironman\s*full|full\s*ironman|full[-\s]*distance|\bfull\b|140[.,]6)/i.test(all))out.add('full');
  } else {
    const half=/(?:mezza\s+maratona|half\s+marathon|\b21(?:[.,]\d+)?\s*km\b)/i.test(nd);
    const clean=nd.replace(/mezza\s+maratona/gi,'').replace(/half\s+marathon/gi,'');
    const marathon=/(?:\bmaratona\b|\bmarathon\b|\b42(?:[.,]\d+)?\s*km\b)/i.test(clean);
    if(half)out.add('mezza');
    if(marathon)out.add('maratona');
  }
  if(/(?:\btrail\b|ultra\s*trail|skyrace|sky\s*race|vertical\s*(?:km|race)?)/i.test(all))out.add('trail');
  if(!isTri && /(?:\b10(?:[.,]\d+)?\s*km\b|\b10k\b)/i.test(nd))out.add('10k');
  if(/\bduathlon\b/i.test(all))out.add('duathlon');
  if(/(?:\bciclismo\b|\bcycling\b|\bgranfondo\b|\bgran\s*fondo\b|\bcriterium\b|\bciclotur)/i.test(all))out.add('ciclismo');
  if(/(?:\bnuoto\b|\bswim(?:ming)?\b|open\s*water)/i.test(all))out.add('nuoto');
  if(/\baquathlon\b/i.test(all))out.add('aquathlon');
  if(!out.size)out.add('altro');
  return out;
}

function selectedYear(){
  const el=document.getElementById('year');
  const v=String(el?.value||'').trim();
  return /^20\d{2}$/.test(v)?Number(v):null;
}
function selectedMonth(){
  const el=document.getElementById('month');
  const v=String(el?.value||'').trim();
  if(/^\d{1,2}$/.test(v)){
    const n=Number(v);
    if(n>=1&&n<=12)return n-1;
    if(n>=0&&n<=11)return n;
  }
  const label=norm(el?.options?.[el.selectedIndex]?.textContent).toLowerCase();
  const names=['gennaio','febbraio','marzo','aprile','maggio','giugno','luglio','agosto','settembre','ottobre','novembre','dicembre'];
  const i=names.findIndex(x=>label.startsWith(x));
  return i>=0?i:null;
}
function searchText(){return norm(document.getElementById('search')?.value).toLowerCase()}

function matches(r){
  const date=/^\d{4}-\d{2}-\d{2}$/.test(String(r.date||''))?new Date(r.date+'T12:00:00'):null;
  if(!date||Number.isNaN(date.getTime()))return false;

  const today=new Date(); today.setHours(0,0,0,0);
  const rd=new Date(date); rd.setHours(0,0,0,0);
  if(rd<today)return false;

  const y=selectedYear();
  if(y!==null&&date.getFullYear()!==y)return false;

  const m=selectedMonth();
  if(m!==null&&date.getMonth()!==m)return false;

  const q=searchText();
  if(q){
    const hay=norm([r.name,r.location,r.distance,r.discipline,r.status,r.note].filter(Boolean).join(' ')).toLowerCase();
    if(!hay.includes(q))return false;
  }

  if(state.types.size){
    const t=raceTypes(r);
    if(![...state.types].some(x=>t.has(x)))return false;
  }
  return true;
}

function addStyles(){
  if(document.getElementById('hub-overlay-style'))return;
  const st=document.createElement('style');
  st.id='hub-overlay-style';
  st.textContent=`
    #hub-format-panel{grid-column:1/-1;border:1px solid var(--border);border-radius:12px;padding:8px 10px;background:var(--card)}
    #hub-format-panel .hub-title{font-size:11px;font-weight:800;color:var(--muted);margin-bottom:6px}
    #hub-format-panel .hub-row{display:flex;gap:6px;flex-wrap:wrap}
    #hub-format-panel button{width:auto;min-height:34px;padding:6px 12px;font-size:12px;border-radius:9px}
    #hub-format-panel button[aria-pressed="true"]{background:#0d2f4d;color:#fff;border-color:#0d2f4d}
    #hub-format-panel .hub-note{font-size:10px;color:var(--muted);margin-top:6px}
    #category.closest-hide{display:none!important}
    #events .hub-event{padding:12px;border-bottom:1px solid var(--border);background:var(--card)}
    #events .hub-event-title{font-weight:700;line-height:1.25}
    #events .hub-event-meta{margin-top:5px;font-size:13px;color:var(--muted);line-height:1.4}
    #events .hub-event-badge{display:inline-block;margin-top:7px;padding:3px 7px;border-radius:999px;background:var(--accent-soft);color:var(--accent);font-size:11px;font-weight:700}
    #events .hub-event-note{margin-top:6px;font-size:12px;color:var(--muted);line-height:1.35}
    #events .hub-links{display:flex;gap:6px;flex-wrap:wrap;margin-top:8px}
    #events .hub-links a{text-decoration:none;padding:6px 8px;border-radius:8px;font-size:11px;font-weight:700;background:var(--accent-soft);color:var(--accent)}
    #hub-debug{font-size:10px;color:var(--muted);margin-top:4px}
    @media(max-width:800px){
      #hub-format-panel .hub-row{display:grid;grid-template-columns:repeat(3,minmax(0,1fr))}
      #hub-format-panel button{width:100%;min-height:40px;padding:5px 3px}
    }
  `;
  document.head.appendChild(st);
}

function populateYears(){
  const sel=document.getElementById('year');
  if(!sel)return;
  const current=sel.value;
  const years=[...new Set(state.races.map(r=>String(r.date||'').slice(0,4)).filter(x=>/^20\d{2}$/.test(x)))].sort();
  sel.innerHTML='<option value="">Tutti</option>'+years.map(y=>'<option value="'+y+'">'+y+'</option>').join('');
  if(years.includes(current))sel.value=current;
}

function installFormatPanel(){
  if(document.getElementById('hub-format-panel'))return;
  const controls=document.querySelector('.controls');
  if(!controls)return;

  const category=document.getElementById('category');
  if(category?.parentElement)category.parentElement.style.display='none';

  const panel=document.createElement('section');
  panel.id='hub-format-panel';
  panel.innerHTML='<div class="hub-title">Formato gara</div><div class="hub-row"></div><div class="hub-note">Nessuna selezione: mostro tutte le gare</div><div id="hub-debug"></div>';
  const row=panel.querySelector('.hub-row');
  const defs=[
    ['sprint','Sprint'],['olimpico','Olimpico'],['70.3','70.3'],
    ['mezza','Mezza maratona'],['maratona','Maratona'],['full','Full Ironman']
  ];
  for(const [key,label] of defs){
    const b=document.createElement('button');
    b.type='button';
    b.dataset.hubType=key;
    b.textContent=label;
    b.setAttribute('aria-pressed','false');
    b.addEventListener('click',()=>{
      state.types.has(key)?state.types.delete(key):state.types.add(key);
      b.setAttribute('aria-pressed',state.types.has(key)?'true':'false');
      panel.querySelector('.hub-note').textContent=state.types.size?'Filtri combinati attivi · tocca di nuovo per rimuoverli':'Nessuna selezione: mostro tutte le gare';
      render();
    });
    row.appendChild(b);
  }
  controls.appendChild(panel);
}

function cardFor(r){
  const card=document.createElement('div');
  card.className='hub-event';
  const d=new Date(r.date+'T12:00:00');
  const dateText=d.toLocaleDateString('it-IT',{day:'2-digit',month:'long',year:'numeric'});
  const title=document.createElement('div');
  title.className='hub-event-title';
  title.textContent=r.name||'Gara';
  const meta=document.createElement('div');
  meta.className='hub-event-meta';
  meta.textContent=[dateText,r.distance,r.location].filter(Boolean).join(' · ');
  const badge=document.createElement('span');
  badge.className='hub-event-badge';
  badge.textContent=r.discipline||r.status||'Gara';
  card.append(title,meta,badge);
  if(r.note){
    const note=document.createElement('div');
    note.className='hub-event-note';
    note.textContent=r.note;
    card.appendChild(note);
  }
  if(r.url||r.mapUrl){
    const links=document.createElement('div');
    links.className='hub-links';
    if(r.url){
      const a=document.createElement('a');a.href=r.url;a.target='_blank';a.rel='noopener';a.textContent='Dettagli';links.appendChild(a);
    }
    if(r.mapUrl){
      const a=document.createElement('a');a.href=r.mapUrl;a.target='_blank';a.rel='noopener';a.textContent='Mappa';links.appendChild(a);
    }
    card.appendChild(links);
  }
  return card;
}

function render(){
  const list=document.getElementById('events');
  const count=document.getElementById('count');
  if(!list||!count)return;

  const visible=state.races.filter(matches).sort((a,b)=>String(a.date).localeCompare(String(b.date)));
  list.replaceChildren(...(visible.length?visible.map(cardFor):[Object.assign(document.createElement('div'),{className:'empty',textContent:'Nessuna gara con questi filtri.'})]));
  count.textContent=visible.length+' '+(visible.length===1?'evento':'eventi');

  const dbg=document.getElementById('hub-debug');
  if(dbg)dbg.textContent='HUB '+BUILD+' · dataset '+state.races.length+' · visibili '+visible.length;
}

function bindControls(){
  for(const id of ['year','month']){
    const el=document.getElementById(id);
    if(el&&!el.dataset.hubBound){el.dataset.hubBound='1';el.addEventListener('change',()=>setTimeout(render,0));}
  }
  const search=document.getElementById('search');
  if(search&&!search.dataset.hubBound){search.dataset.hubBound='1';search.addEventListener('input',()=>setTimeout(render,0));}
}

function loadData(){
  return new Promise(resolve=>{
    if(Array.isArray(window.EXTRA_RACES)&&window.EXTRA_RACES.length){resolve(window.EXTRA_RACES);return;}
    const sc=document.createElement('script');
    sc.src='/legacy/extra-races.js?hub='+Date.now();
    sc.onload=()=>resolve(Array.isArray(window.EXTRA_RACES)?window.EXTRA_RACES:[]);
    sc.onerror=()=>resolve([]);
    document.head.appendChild(sc);
  });
}

async function init(){
  addStyles();
  state.races=await loadData();
  populateYears();
  installFormatPanel();
  bindControls();
  render();

  // The legacy page can redraw #events; always re-assert the HUB list afterwards.
  const list=document.getElementById('events');
  if(list){
    const obs=new MutationObserver(()=>{
      clearTimeout(window.__hubRenderTimer);
      window.__hubRenderTimer=setTimeout(()=>{
        if(!list.querySelector('.hub-event')&&state.races.length)render();
      },30);
    });
    obs.observe(list,{childList:true,subtree:true});
  }

  window.__hubRenderStructured=render;
}

if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>setTimeout(init,50),{once:true});
else setTimeout(init,50);
})();