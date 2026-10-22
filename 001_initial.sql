-- Sadharmik Jobs v1. Run on a NEW Supabase project. No dependency on other apps.
begin;
create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 email text not null, full_name text not null default '',
 role text not null default 'candidate' check(role in ('candidate','admin')),
 active boolean not null default false, must_change_password boolean not null default true,
 access_version text not null default gen_random_uuid()::text,
 phone text not null default '',city text not null default '',roles text not null default '',
 skills text[] not null default '{}', experience numeric check(experience between 0 and 70),
 current_ctc numeric check(current_ctc between 0 and 1000),expected_ctc numeric check(expected_ctc between 0 and 1000),
 cities text not null default '',employment_status text not null default 'Looking for work' check(employment_status in ('Fresher','Working','Looking for work','Returning after a break')),
 notice_period text not null default 'Immediately' check(notice_period in ('Immediately','15 days','30 days','60 days','90 days')),
 work_mode text not null default 'Any' check(work_mode in ('Any','Office','Remote','Hybrid')),
 employment_type text not null default 'Full-time' check(employment_type in ('Full-time','Part-time','Contract')),
 relocate boolean not null default false, urgent boolean not null default false,
 alerts text not null default 'weekly' check(alerts in ('daily','weekly','off')),consent boolean not null default false,
 cv_path text,cv_name text, created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(length(full_name)<=120 and length(phone)<=16 and length(city)<=100 and length(roles)<=250 and length(cities)<=250),
 check(cardinality(skills)<=100)
);
create table public.jobs (
 id uuid primary key default gen_random_uuid(), title text not null check(length(title) between 1 and 150),
 company text not null check(length(company) between 1 and 150),city text not null check(length(city) between 1 and 100),
 category text not null check(length(category) between 1 and 100),description text not null check(length(description) between 1 and 8000),
 skills text[] not null default '{}',mandatory_skills text[] not null default '{}',
 experience_min numeric not null default 0 check(experience_min between 0 and 70),experience_max numeric check(experience_max between 0 and 70),
 salary_min numeric check(salary_min between 0 and 1000),salary_max numeric check(salary_max between 0 and 1000),
 work_mode text not null check(work_mode in ('Office','Remote','Hybrid')),
 employment_type text not null check(employment_type in ('Full-time','Part-time','Contract')),
 status text not null default 'draft' check(status in ('draft','published','closed')),
 closes_on date, freshers boolean not null default false,career_break boolean not null default false,
 source_verified boolean not null default false,
 created_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(experience_max is null or experience_max>=experience_min),check(salary_max is null or salary_min is null or salary_max>=salary_min),
 check(cardinality(skills)<=100 and cardinality(mandatory_skills)<=100),check(status<>'published' or source_verified)
);
-- Contacts are separated so even API requests cannot reveal employer emails to candidates.
create table public.job_contacts (
 job_id uuid primary key references public.jobs(id) on delete cascade,
 recipient_email text not null check(recipient_email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),
 source text not null check(length(source) between 1 and 250)
);
create table public.applications (
 id uuid primary key default gen_random_uuid(),job_id uuid not null references public.jobs(id),
 candidate_id uuid not null references public.profiles(id) on delete cascade,
 profile_snapshot jsonb not null,job_snapshot jsonb not null,cv_path text,
 status text not null default 'applied' check(status in ('applied','under_review','interview','selected','not_selected','withdrawn')),
 email_status text not null default 'disabled' check(email_status='disabled'),
 consent_at timestamptz not null default now(),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(job_id,candidate_id)
);
create table public.admin_activity (
 id bigint generated always as identity primary key,actor_id uuid references public.profiles(id) on delete set null,
 action text not null,target_id uuid,created_at timestamptz not null default now()
);
create index jobs_status_date on public.jobs(status,closes_on);
create index applications_candidate on public.applications(candidate_id,created_at desc);
create index applications_job on public.applications(job_id,created_at desc);
create index profiles_role on public.profiles(role);

create function public.handle_new_user() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.profiles(id,email,full_name,role,active,must_change_password,access_version)
 values(new.id,new.email,left(coalesce(new.raw_user_meta_data->>'full_name',''),120),'candidate',
 coalesce((new.raw_app_meta_data->>'approved')::boolean,false),true,coalesce(new.raw_app_meta_data->>'access_version',gen_random_uuid()::text));
 return new;
end;$$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();
create function public.is_ready() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p where p.id=auth.uid() and p.active and not p.must_change_password
 and p.access_version=(auth.jwt()->'app_metadata'->>'access_version'));
$$;
create function public.is_admin() returns boolean language sql stable security definer set search_path='' as $$
 select public.is_ready() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin');
$$;
create function public.touch_row() returns trigger language plpgsql set search_path='' as $$begin new.updated_at=now();return new;end;$$;
create trigger profiles_touch before update on public.profiles for each row execute function public.touch_row();
create trigger jobs_touch before update on public.jobs for each row execute function public.touch_row();
create trigger applications_touch before update on public.applications for each row execute function public.touch_row();
-- Validate path ownership AND object existence; never trust a client-supplied CV path.
create function public.validate_profile_cv() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.cv_path is not null and (new.cv_path not like new.id::text||'/%' or not exists(select 1 from storage.objects where bucket_id='cvs' and name=new.cv_path)) then
 raise exception 'Invalid CV reference';end if;
 return new;
end;$$;
create trigger profile_cv before insert or update of cv_path on public.profiles for each row execute function public.validate_profile_cv();

alter table public.profiles enable row level security;
alter table public.jobs enable row level security;
alter table public.job_contacts enable row level security;
alter table public.applications enable row level security;
alter table public.admin_activity enable row level security;
create policy profile_read on public.profiles for select to authenticated using(id=auth.uid() or public.is_admin());
create policy profile_edit on public.profiles for update to authenticated using(id=auth.uid() and public.is_ready()) with check(id=auth.uid() and public.is_ready());
create policy jobs_read on public.jobs for select to authenticated using(public.is_admin() or (public.is_ready() and status='published' and (closes_on is null or closes_on>=(now() at time zone 'Asia/Kolkata')::date)));
create policy contacts_read on public.job_contacts for select to authenticated using(public.is_admin());
create policy application_read on public.applications for select to authenticated using(public.is_ready() and (candidate_id=auth.uid() or public.is_admin()));
create policy activity_read on public.admin_activity for select to authenticated using(public.is_admin());
revoke all on public.profiles,public.jobs,public.job_contacts,public.applications,public.admin_activity from anon,authenticated;
grant select on public.profiles,public.jobs,public.job_contacts,public.applications,public.admin_activity to authenticated;
grant update(full_name,phone,city,roles,skills,experience,current_ctc,expected_ctc,cities,employment_status,notice_period,work_mode,employment_type,relocate,urgent,alerts,consent,cv_path,cv_name) on public.profiles to authenticated;

-- Service-only reset helper revokes existing refresh sessions as well as rotating access tokens.
create function public.revoke_candidate_sessions(target_user uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.profiles where id=target_user and role='candidate') then raise exception 'Candidate not found';end if;
 delete from auth.refresh_tokens where user_id=target_user::text;
 delete from auth.sessions where user_id=target_user;
end;$$;
revoke execute on function public.revoke_candidate_sessions(uuid) from public,anon,authenticated;
grant execute on function public.revoke_candidate_sessions(uuid) to service_role;
create function public.normal_skill(value text) returns text language sql immutable set search_path='' as $$
 select case lower(trim(regexp_replace(value,'\s+',' ','g')))
 when 'ms excel' then 'excel' when 'microsoft excel' then 'excel' when 'tally prime' then 'tally' when 'tally erp' then 'tally'
 when 'accounts' then 'accounting' when 'customer support' then 'customer service' when 'human resources' then 'hr' when 'js' then 'javascript'
 else lower(trim(regexp_replace(value,'\s+',' ','g'))) end;
$$;
revoke execute on function public.normal_skill(text) from public,anon;
grant execute on function public.normal_skill(text) to authenticated;
-- All application writes are atomic and checked on the server.
create function public.apply_to_job(target_job uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare p public.profiles; j public.jobs; result uuid; missing integer;
begin
 if not public.is_ready() then raise exception 'Please sign in and set your own password';end if;
 select * into p from public.profiles where id=auth.uid();
 if p.role<>'candidate' then raise exception 'Only candidates can apply';end if;
 if not p.consent or p.phone !~ '^\+?[0-9]{10,15}$' or length(trim(p.full_name))=0 or length(trim(p.roles))=0 or length(trim(p.cities))=0 or cardinality(p.skills)=0 or p.experience is null then raise exception 'Complete and save your profile with consent before applying';end if;
 select * into j from public.jobs where id=target_job for share;
 if not found or j.status<>'published' or (j.closes_on is not null and j.closes_on<(now() at time zone 'Asia/Kolkata')::date) then raise exception 'This opening is closed';end if;
 select count(*) into missing from unnest(j.mandatory_skills) s where not exists(select 1 from unnest(p.skills) ps where public.normal_skill(ps)=public.normal_skill(s));
 if missing>0 then raise exception 'Required skills are missing from your profile';end if;
 insert into public.applications(job_id,candidate_id,profile_snapshot,job_snapshot,cv_path)
 values(j.id,p.id,jsonb_build_object('full_name',p.full_name,'email',p.email,'phone',p.phone,'city',p.city,'roles',p.roles,'skills',p.skills,'experience',p.experience,'current_ctc',p.current_ctc,'expected_ctc',p.expected_ctc,'cities',p.cities,'notice_period',p.notice_period,'employment_status',p.employment_status,'work_mode',p.work_mode,'employment_type',p.employment_type,'cv_name',p.cv_name),jsonb_build_object('title',j.title,'company',j.company,'city',j.city),p.cv_path) returning id into result;
 return result;
exception when unique_violation then raise exception 'You have already applied to this opening';
end;$$;
create function public.withdraw_application(application_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_ready() then raise exception 'Unauthorised';end if;
 update public.applications set status='withdrawn' where id=application_id and candidate_id=auth.uid() and status<>'withdrawn';
 if not found then raise exception 'Application not found or already withdrawn';end if;
end;$$;
create function public.set_application_status(application_id uuid,next_status text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Admin access required';end if;
 if next_status not in ('applied','under_review','interview','selected','not_selected','withdrawn') then raise exception 'Invalid status';end if;
 update public.applications set status=next_status where id=application_id and (status<>'withdrawn' or next_status='withdrawn');
 if not found then raise exception 'Application unavailable or withdrawn by candidate';end if;
 insert into public.admin_activity(actor_id,action,target_id) values(auth.uid(),'application:'||next_status,application_id);
end;$$;
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
-- Functions otherwise default to executable by PUBLIC.
revoke execute on function public.handle_new_user(),public.touch_row(),public.validate_profile_cv() from public,anon,authenticated;
revoke execute on function public.is_ready(),public.is_admin(),public.apply_to_job(uuid),public.withdraw_application(uuid),public.set_application_status(uuid,text),public.save_job(uuid,jsonb,jsonb) from public,anon;
grant execute on function public.is_ready(),public.is_admin(),public.apply_to_job(uuid),public.withdraw_application(uuid),public.set_application_status(uuid,text),public.save_job(uuid,jsonb,jsonb) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('cvs','cvs',false,2097152,array['application/pdf','application/vnd.openxmlformats-officedocument.wordprocessingml.document']);
create policy cv_upload on storage.objects for insert to authenticated with check(bucket_id='cvs' and public.is_ready() and (storage.foldername(name))[1]=auth.uid()::text and lower(storage.extension(name)) in ('pdf','docx'));
create policy cv_read on storage.objects for select to authenticated using(bucket_id='cvs' and public.is_ready() and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));
-- Never delete a CV referenced by an application or the current profile.
create policy cv_remove on storage.objects for delete to authenticated using(bucket_id='cvs' and public.is_ready() and (storage.foldername(name))[1]=auth.uid()::text and not exists(select 1 from public.applications a where a.cv_path=name) and not exists(select 1 from public.profiles p where p.cv_path=name));
commit;
