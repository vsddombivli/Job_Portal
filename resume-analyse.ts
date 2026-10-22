import {createClient} from 'npm:@supabase/supabase-js@2.49.8';
import {createResumeHandler} from './handler.js';
const service=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
Deno.serve(createResumeHandler({service,apiKey:Deno.env.get('ANTHROPIC_API_KEY'),model:Deno.env.get('ANTHROPIC_MODEL')||'claude-haiku-4-5-20251001',allowedOrigins:(Deno.env.get('ALLOWED_ORIGIN')||'').split(',').map(x=>x.trim()).filter(Boolean)}));
