const crypto = require('crypto');

const TABLES = new Set(['notices','staff','achievements','gallery','downloads','site_settings']);

function sign(value){
  return crypto.createHmac('sha256', process.env.ADMIN_SESSION_SECRET || '').update(value).digest('base64url');
}
function parseCookie(header){
  return Object.fromEntries((header||'').split(';').filter(Boolean).map(x=>{
    const i=x.indexOf('='); return [x.slice(0,i).trim(), decodeURIComponent(x.slice(i+1).trim())];
  }));
}
function authenticated(req){
  const t=parseCookie(req.headers.cookie).admin_session||'';
  const [p,s]=t.split('.');
  if(!p||!s||!process.env.ADMIN_SESSION_SECRET||s!==sign(p)) return false;
  try { const d=JSON.parse(Buffer.from(p,'base64url').toString()); return !!d.exp && Date.now()<=d.exp; }
  catch { return false; }
}
function table(req){
  const t=(req.query?.table || '').toString();
  return TABLES.has(t) ? t : null;
}
async function supabase(path, options={}){
  const url=process.env.SUPABASE_URL;
  const key=process.env.SUPABASE_SERVICE_ROLE_KEY;
  if(!url||!key) throw new Error('Supabase server configuration is missing');
  const r=await fetch(`${url}/rest/v1/${path}`,{
    ...options,
    headers:{apikey:key,Authorization:`Bearer ${key}`,'Content-Type':'application/json',Prefer:'return=representation',...(options.headers||{})}
  });
  const text=await r.text();
  let data; try{data=text?JSON.parse(text):null}catch{data={message:text};}
  if(!r.ok){const e=new Error(data?.message||data?.hint||'Supabase request failed');e.status=r.status;throw e;}
  return data;
}
module.exports=async(req,res)=>{
  if(!authenticated(req)) return res.status(401).json({error:'Unauthorized'});
  const t=table(req); if(!t) return res.status(400).json({error:'Invalid table'});
  try{
    if(req.method==='GET') return res.status(200).json(await supabase(`${t}?select=*&order=created_at.desc`));
    if(req.method==='POST'){
      const body=req.body||{};
      return res.status(201).json(await supabase(t,{method:'POST',body:JSON.stringify(body)}));
    }
    if(req.method==='PATCH'){
      const id=(req.query?.id||'').toString(); if(!id) return res.status(400).json({error:'Missing id'});
      return res.status(200).json(await supabase(`${t}?id=eq.${encodeURIComponent(id)}`,{method:'PATCH',body:JSON.stringify(req.body||{})}));
    }
    if(req.method==='DELETE'){
      const id=(req.query?.id||'').toString(); if(!id) return res.status(400).json({error:'Missing id'});
      await supabase(`${t}?id=eq.${encodeURIComponent(id)}`,{method:'DELETE'});
      return res.status(200).json({ok:true});
    }
    return res.status(405).json({error:'Method not allowed'});
  }catch(e){ return res.status(e.status||500).json({error:e.message||'Server error'}); }
};
