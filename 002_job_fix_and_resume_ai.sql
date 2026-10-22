-- UPGRADE an existing v1 installation. Safe to rerun. Do not rerun 001.
-- The save_job RPC signature remains unchanged, so existing frontends keep working.
begin;
create or replace function public.save_job(job_id uuid,payload jsonb,contact jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
 if not public.is_admin() then raise exception 'Admin access required';end if;
 if coalesce((payload->>'source_verified')::boolean,false)=false then raise exception 'Verify the source first';end if;
 if save_job.job_id is not null and not exists(select 1 from public.jobs j where j.id=save_job.job_id) then raise exception 'Job not found';end if;
 result=coalesce(save_job.job_id,gen_random_uuid());
 insert into public.jobs(id,title,company,city,category,description,skills,mandatory_skills,experience_min,experience_max,salary_min,salary_max,work_mode,employment_type,status,closes_on,freshers,career_break,source_verified,created_by)
 values(result,trim(payload->>'title'),trim(payload->>'company'),trim(payload->>'city'),trim(payload->>'category'),trim(payload->>'description'),array(select jsonb_array_elements_text(coalesce(payload->'skills','[]'::jsonb))),array(select jsonb_array_elements_text(coalesce(payload->'mandatory_skills','[]'::jsonb))),(payload->>'experience_min')::numeric,(payload->>'experience_max')::numeric,(payload->>'salary_min')::numeric,(payload->>'salary_max')::numeric,payload->>'work_mode',payload->>'employment_type',payload->>'status',(payload->>'closes_on')::date,coalesce((payload->>'freshers')::boolean,false),coalesce((payload->>'career_break')::boolean,false),true,auth.uid())
 on conflict(id) do update set title=excluded.title,company=excluded.company,city=excluded.city,category=excluded.category,description=excluded.description,skills=excluded.skills,mandatory_skills=excluded.mandatory_skills,experience_min=excluded.experience_min,experience_max=excluded.experience_max,salary_min=excluded.salary_min,salary_max=excluded.salary_max,work_mode=excluded.work_mode,employment_type=excluded.employment_type,status=excluded.status,closes_on=excluded.closes_on,freshers=excluded.freshers,career_break=excluded.career_break,source_verified=excluded.source_verified;
 insert into public.job_contacts(job_id,recipient_email,source) values(result,trim(contact->>'recipient_email'),trim(contact->>'source')) on conflict on constraint job_contacts_pkey do update set recipient_email=excluded.recipient_email,source=excluded.source;
 insert into public.admin_activity(actor_id,action,target_id) values(auth.uid(),'job:saved',result);
 return result;
end;$$;

-- Add separate skills without deleting existing manually entered profile data.
alter table public.profiles add column if not exists primary_skills text[] not null default '{}';
alter table public.profiles add column if not exists other_skills text[] not null default '{}';
alter table public.profiles add column if not exists resume_summary text not null default '';
update public.profiles set primary_skills=skills where cardinality(primary_skills)=0 and cardinality(other_skills)=0 and cardinality(skills)>0;
-- Preserve old clients: old skills edits become the primary list; new clients send all 3 lists.
create or replace function public.sync_profile_skills() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='UPDATE' and not (new.skills @> old.skills and new.skills <@ old.skills) and new.primary_skills is not distinct from old.primary_skills and new.other_skills is not distinct from old.other_skills then
  new.primary_skills=new.skills;new.other_skills='{}';
 else
  select coalesce(array_agg(value order by value),'{}') into new.skills from
   (select distinct trim(s) as value from unnest(new.primary_skills||new.other_skills) s where length(trim(s))>0) x;
 end if;
 if cardinality(new.primary_skills)>20 or cardinality(new.other_skills)>30 or length(new.resume_summary)>600 then raise exception 'Too many skills or summary too long';end if;
 if exists(select 1 from unnest(new.skills) s where length(s)>80) then raise exception 'Skill names must be at most 80 characters';end if;
 return new;
end;$$;
drop trigger if exists sync_profile_skills on public.profiles;
create trigger sync_profile_skills before update of skills,primary_skills,other_skills,resume_summary on public.profiles for each row execute function public.sync_profile_skills();
revoke execute on function public.sync_profile_skills() from public,anon,authenticated;
grant update(primary_skills,other_skills,resume_summary) on public.profiles to authenticated;

-- A server-side, atomic budget guard. No CV text or AI output is stored here.
create table if not exists public.resume_scan_usage (
 user_id uuid not null references public.profiles(id) on delete cascade,
 scan_date date not null, calls integer not null default 0 check(calls between 0 and 3),
 primary key(user_id,scan_date)
);
alter table public.resume_scan_usage enable row level security;
revoke all on public.resume_scan_usage from anon,authenticated;
create or replace function public.reserve_resume_scan(scan_user uuid) returns void language plpgsql security definer set search_path='' as $$
declare today date=(now() at time zone 'Asia/Kolkata')::date; total_calls integer;
begin
 if not exists(select 1 from public.profiles p where p.id=scan_user and p.active and not p.must_change_password) then raise exception 'Account unavailable';end if;
 perform pg_catalog.pg_advisory_xact_lock(70952143);
 select coalesce(sum(calls),0) into total_calls from public.resume_scan_usage where scan_date=today;
 if total_calls>=100 then raise exception 'Community AI daily limit reached. Please try tomorrow or enter skills manually.';end if;
 insert into public.resume_scan_usage as usage(user_id,scan_date,calls) values(scan_user,today,1)
 on conflict on constraint resume_scan_usage_pkey do update set calls=usage.calls+1 where usage.calls<3;
 if not found then raise exception 'Your 3 daily AI scans are used. Please try tomorrow or enter skills manually.';end if;
end;$$;
revoke execute on function public.reserve_resume_scan(uuid) from public,anon,authenticated;
grant execute on function public.reserve_resume_scan(uuid) to service_role;
notify pgrst, 'reload schema';
commit;
