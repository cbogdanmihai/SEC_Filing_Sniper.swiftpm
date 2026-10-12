import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const PORT = Number(process.env.PORT || 3000);
const POLL_MS = Math.max(10000, Number(process.env.POLL_MS || 15000));
const USER_AGENT = process.env.SEC_USER_AGENT || 'SEC-Filing-Sniper/0.1 admin contact@example.com';
const SOURCE = 'https://www.sec.gov/cgi-bin/browse-edgar?action=getcurrent&output=atom&count=100';
const FORMS = (process.env.SEC_FORMS || '').split(',').map(x=>x.trim().toUpperCase()).filter(Boolean);
const clients = new Set();
const records = new Map();
let state = {lastPoll:null,lastSuccess:null,lastError:null,source:SOURCE,pollMs:POLL_MS,count:0};

const decode = s => String(s || '').replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&amp;/g,'&').replace(/&quot;/g,'"').replace(/&#39;/g,"'");
const tag = (xml,name) => decode((xml.match(new RegExp('<'+name+'(?:\\s[^>]*)?>([\\s\\S]*?)<\\/'+name+'>','i'))||[])[1] || '').replace(/<[^>]+>/g,'').trim();
const attr = (str, name) => (str.match(new RegExp('\\b'+name+'="([^"]*)"','i'))||[])[1] || '';
function classify(form, title){
  const s=(form+' '+title).toLowerCase();
  if (/424b5|424b2|s-1|s-3|offering|dilution|bankruptcy|delisting|going concern/.test(s)) return {signal:'BEARISH?',priority:85,reason:'Possible financing or financial risk; verify document'};
  if (/tender offer|merger|acquisition|material definitive agreement|contract award/.test(s)) return {signal:'BULLISH?',priority:80,reason:'Potential material event; terms and price reaction unknown'};
  if (/8-k|6-k|13d|13g|form 4|^4$/.test(s)) return {signal:'REVIEW',priority:70,reason:'Material or ownership filing; inspect full content'};
  return {signal:'REVIEW',priority:40,reason:'Unclassified; inspect original filing'};
}
function parse(xml){
  return [...xml.matchAll(/<entry(?:\s[^>]*)?>([\s\S]*?)<\/entry>/gi)].map(m=>{
    const body=m[1], title=tag(body,'title'), id=tag(body,'id');
    const linkMatch=body.match(/<link\b[^>]*>/i), link=linkMatch?attr(linkMatch[0],'href'):'';
    const form=tag(body,'category') || attr((body.match(/<category\b[^>]*>/i)||[])[0]||'','term') || (title.match(/^([A-Z0-9-]+)\s+-/)||[])[1] || '';
    const updated=tag(body,'updated')||tag(body,'published');
    const cik=(id.match(/\b(\d{10})\b/)||[])[1] || '';
    const key=id||link;
    if(!key || !link.startsWith('https://www.sec.gov/')) return null;
    return {id:key,url:link,title,form,feedTime:updated||null,cik,...classify(form,title)};
  }).filter(Boolean);
}
function snapshot(){return {status:state,filings:[...records.values()].sort((a,b)=>b.detectedAt.localeCompare(a.detectedAt)).slice(0,150)}}
function send(res,payload){res.write('data: '+JSON.stringify(payload)+'\n\n')}
function broadcast(){const data=snapshot();for(const client of clients){try{send(client,data)}catch{clients.delete(client)}}}
async function poll(){
  state.lastPoll=new Date().toISOString();
  try {
    const controller=new AbortController(), timeout=setTimeout(()=>controller.abort(),10000);
    let response;
    try {response=await fetch(SOURCE,{headers:{'User-Agent':USER_AGENT,'Accept':'application/atom+xml, application/xml;q=0.9','Accept-Encoding':'gzip, deflate'},signal:controller.signal});}
    finally {clearTimeout(timeout)}
    if(!response.ok) throw Error('SEC returned HTTP '+response.status);
    const entries=parse(await response.text());
    if(!entries.length) throw Error('No valid entries parsed from SEC feed');
    for(const row of entries){
      if(FORMS.length && !FORMS.includes(row.form.toUpperCase())) continue;
      if(!records.has(row.id)) records.set(row.id,{...row,detectedAt:new Date().toISOString()});
    }
    while(records.size>400) records.delete(records.keys().next().value);
    state.lastSuccess=new Date().toISOString();state.lastError=null;state.count=records.size;
  } catch(e){state.lastError=String(e?.message||e)}
  broadcast();
}
let polling=false;
async function tick(){if(polling)return;polling=true;try{await poll()}finally{polling=false}}
const root=path.join(path.dirname(fileURLToPath(import.meta.url)),'public');
const assets={'/':'index.html','/index.html':'index.html','/manifest.webmanifest':'manifest.webmanifest','/sw.js':'sw.js'};
const mime={'index.html':'text/html; charset=utf-8','manifest.webmanifest':'application/manifest+json','sw.js':'text/javascript; charset=utf-8'};
http.createServer(async(req,res)=>{
  const pathname=new URL(req.url,'http://localhost').pathname;
  res.setHeader('X-Content-Type-Options','nosniff');
  if(pathname==='/api/filings'||pathname==='/api/health'){
    res.writeHead(200,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'});
    res.end(JSON.stringify(pathname==='/api/health'?state:snapshot()));return;
  }
  if(pathname==='/api/stream'){
    res.writeHead(200,{'Content-Type':'text/event-stream','Cache-Control':'no-cache, no-transform','Connection':'keep-alive','X-Accel-Buffering':'no'});
    clients.add(res);send(res,snapshot());req.on('close',()=>clients.delete(res));return;
  }
  const file=assets[pathname];
  if(!file){res.writeHead(404);res.end('Not found');return}
  try {const data=await readFile(path.join(root,file));res.writeHead(200,{'Content-Type':mime[file],'Cache-Control':file==='sw.js'?'no-cache':'public, max-age=60'});res.end(data)}
  catch{res.writeHead(500);res.end('Asset not available')}
}).listen(PORT,'0.0.0.0',()=>console.log('SEC Filing Sniper listening on '+PORT));
await tick();setInterval(tick,POLL_MS);
