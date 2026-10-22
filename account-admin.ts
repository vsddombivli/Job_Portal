import { createClient } from 'npm:@supabase/supabase-js@2.49.8';
// Set ALLOWED_ORIGIN to the exact production frontend origin. Never use '*'.
const url = Deno.env.get('SUPABASE_URL')!;
const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const allowed = (Deno.env.get('ALLOWED_ORIGIN') || '').split(',').map(x=>x.trim()).filter(Boolean);
Deno.serve(async(req: Request)=>{
 const origin=req.headers.get('origin')||'';
 const headers={'Content-Type':'application/json','Access-Control-Allow-Origin':allowed.includes(origin)?origin:'null','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Vary':'Origin','Cache-Control':'no-store'};
 const reply=(status:number,value:unknown)=>new Response(JSON.stringify(value),{status,headers});
 if(origin&&!allowed.includes(origin))return reply(403,{error:'Origin not allowed'});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return reply(405,{error:'POST required'});
 const service=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
 try{
  const token=(req.headers.get('authorization')||'').replace(/^Bearer\s+/i,'');if(!token)return reply(401,{error:'Sign in required'});
  const {data:{user},error:authError}=await service.auth.getUser(token);if(authError||!user)return reply(401,{error:'Session expired. Sign in again.'});
  const {data:actor,error:actorError}=await service.from('profiles').select('id,role,active,must_change_password,access_version').eq('id',user.id).single();if(actorError||!actor?.active)return reply(403,{error:'Account unavailable'});
  // getUser verifies the JWT. Inspect its signed payload only after verification.
  const payload=JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(token.split('.')[1].replace(/-/g,'+').replace(/_/g,'/')),c=>c.charCodeAt(0))));
  if(payload.app_metadata?.access_version!==actor.access_version)return reply(401,{error:'This session is no longer valid. Sign in again.'});
  const body=await req.json();
  const check=(error:unknown)=>{if(error)throw error;};
  if(body.action==='change-password'){
   if(typeof body.password!=='string'||body.password.length<12||body.password.length>128)return reply(400,{error:'Use a password of 12–128 characters.'});
   if(body.password===body.current_password)return reply(400,{error:'Choose a different password.'});
   const verifier=createClient(url,anonKey,{auth:{persistSession:false,autoRefreshToken:false}});
   const {data:verified,error}=await verifier.auth.signInWithPassword({email:user.email!,password:String(body.current_password||'')});
   if(error||verified.user?.id!==user.id)return reply(400,{error:'Current password is incorrect.'});
   // Revoke only the extra verification session. Default global sign-out would also revoke the caller.
   await verifier.auth.signOut({scope:'local'});
   const {error:updateError}=await service.auth.admin.updateUserById(user.id,{password:body.password});check(updateError);
   const {error:profileError}=await service.from('profiles').update({must_change_password:false}).eq('id',user.id);check(profileError);
   const {error:logError}=await service.from('admin_activity').insert({actor_id:user.id,action:'account:password-changed',target_id:user.id});check(logError);
   return reply(200,{ok:true});
  }
  if(actor.role!=='admin'||actor.must_change_password)return reply(403,{error:'Admin access required'});
  if(!['create-candidate','reset-password','set-active'].includes(body.action))return reply(400,{error:'Unknown action'});
  if(body.action==='create-candidate'){
   if(body.identity_verified!==true)return reply(400,{error:'Verify eligibility, consent and email ownership first.'});
   if(typeof body.password!=='string'||body.password.length<12||body.password.length>128)return reply(400,{error:'Use a temporary password of 12–128 characters.'});
   if(typeof body.full_name!=='string'||!body.full_name.trim()||body.full_name.length>120)return reply(400,{error:'Candidate name is required.'});
   if(typeof body.email!=='string'||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(body.email))return reply(400,{error:'A valid email is required.'});
   const version=crypto.randomUUID();
   const {data,error}=await service.auth.admin.createUser({email:body.email.trim().toLowerCase(),password:body.password,email_confirm:true,user_metadata:{full_name:body.full_name.trim()},app_metadata:{approved:true,access_version:version}});check(error);
   const {error:logError}=await service.from('admin_activity').insert({actor_id:user.id,action:'candidate:created',target_id:data.user!.id});check(logError);
   return reply(200,{ok:true,user_id:data.user!.id});
  }
  if(typeof body.user_id!=='string'||body.user_id===user.id)return reply(400,{error:'Select a candidate account.'});
  const {data:target,error:targetError}=await service.from('profiles').select('id,role').eq('id',body.user_id).single();if(targetError||target?.role!=='candidate')return reply(400,{error:'Candidate not found'});
  if(body.action==='reset-password'){
   if(body.identity_verified!==true)return reply(400,{error:'Verify candidate identity first.'});
   if(typeof body.password!=='string'||body.password.length<12||body.password.length>128)return reply(400,{error:'Use a temporary password of 12–128 characters.'});
   const version=crypto.randomUUID();
   // Lock and rotate the DB version first: even a partially failed reset stays locked.
   const {error:lockError}=await service.from('profiles').update({must_change_password:true,access_version:version}).eq('id',target.id);check(lockError);
   const {error:revokeError}=await service.rpc('revoke_candidate_sessions',{target_user:target.id});check(revokeError);
   const {error:updateError}=await service.auth.admin.updateUserById(target.id,{password:body.password,app_metadata:{access_version:version}});check(updateError);
  }else{
   if(typeof body.active!=='boolean')return reply(400,{error:'Active must be true or false.'});
   // Rotate access version on both pause and resume, invalidating earlier access tokens.
   const version=crypto.randomUUID();
   const {error}=await service.from('profiles').update({active:body.active,access_version:version}).eq('id',target.id);check(error);
   const {error:revokeError}=await service.rpc('revoke_candidate_sessions',{target_user:target.id});check(revokeError);
   const {error:updateError}=await service.auth.admin.updateUserById(target.id,{app_metadata:{access_version:version}});check(updateError);
  }
  const {error:logError}=await service.from('admin_activity').insert({actor_id:user.id,action:body.action,target_id:target.id});check(logError);
  return reply(200,{ok:true});
 }catch(e){
  // Do not log request bodies or credentials.
  const message=e instanceof Error?e.message:'Request failed';
  return reply(400,{error:message});
 }
});
