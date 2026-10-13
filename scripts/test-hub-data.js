const fs=require('fs');
const vm=require('vm');

const code=fs.readFileSync('extra-races.js','utf8');
const sandbox={window:{}};
vm.createContext(sandbox);
vm.runInContext(code,sandbox);
const races=sandbox.window.EXTRA_RACES||[];

function types(r){
  const all=[r.name,r.distance,r.discipline].filter(Boolean).join(' ').toLowerCase();
  const nd=[r.name,r.distance].filter(Boolean).join(' ').toLowerCase();
  const out=new Set();
  const isTri=/(?:\btriathlon\b|\bironman\b|70[.,]3|\bolimpic[oa]\b|\bolympic\b|\bsprint\b|\bmedio\b|middle\s*distance|\bfull\b)/i.test(all);
  if(isTri){
    if(/\b(?:super\s*)?sprint\b/i.test(all))out.add('sprint');
    if(/\b(?:olimpic[oa]|olympic)\b/i.test(all))out.add('olimpico');
    if(/(?:70[.,]3|half\s*ironman|ironman\s*70|middle\s*distance|\bmedio\b)/i.test(all))out.add('70.3');
    if(/(?:ironman\s*full|full\s*ironman|full[-\s]*distance|\bfull\b|140[.,]6)/i.test(all))out.add('full');
  }else{
    const half=/(?:mezza\s+maratona|half\s+marathon|\b21(?:[.,]\d+)?\s*km\b)/i.test(nd);
    const clean=nd.replace(/mezza\s+maratona/gi,'').replace(/half\s+marathon/gi,'');
    const marathon=/(?:\bmaratona\b|\bmarathon\b|\b42(?:[.,]\d+)?\s*km\b)/i.test(clean);
    if(half)out.add('mezza');
    if(marathon)out.add('maratona');
  }
  return out;
}

function count(year,type){
  const now=new Date('2026-10-13T00:00:00+02:00');
  return races.filter(r=>{
    const d=new Date(r.date+'T12:00:00');
    return !Number.isNaN(d.getTime()) && d>=now && d.getFullYear()===year && types(r).has(type);
  }).length;
}

const checks={
  total:races.length,
  mezza2026:count(2026,'mezza'),
  maratona2026:count(2026,'maratona'),
  mezza2027:count(2027,'mezza'),
  sprint2027:count(2027,'sprint'),
  olimpico2027:count(2027,'olimpico'),
  medio2027:count(2027,'70.3'),
  full2027:count(2027,'full')
};

console.log(JSON.stringify(checks,null,2));
if(checks.total<50)throw new Error('Too few races in HUB dataset');
if(checks.mezza2026<1)throw new Error('2026 half-marathon filter would return zero');
if(checks.maratona2026<1)throw new Error('2026 marathon filter would return zero');
if(checks.mezza2027<1)throw new Error('2027 half-marathon filter would return zero');
if(checks.sprint2027<1||checks.olimpico2027<1||checks.medio2027<1||checks.full2027<1){
  throw new Error('One or more primary triathlon filters would return zero');
}

const app=fs.readFileSync('app.html','utf8');
if(!app.includes('<script src="./extra-races.js"></script>'))throw new Error('extra-races.js is not loaded synchronously');
if(!app.includes("const HUB_BUILD='2026.10.13-0700'"))throw new Error('unexpected HUB build');
console.log('HUB_DATA_SELFTEST_OK');
