-- Student Portal V4 Secure Migration
-- IMPORTANT: Review before running in Supabase SQL Editor.

create extension if not exists pgcrypto;

-- =========================================================
-- 1. Student profile security columns
-- =========================================================

alter table public.student_profiles
  add column if not exists profile_locked boolean not null default false,
  add column if not exists profile_complete boolean not null default false,
  add column if not exists regular_student boolean not null default false,
  add column if not exists email_update_count integer not null default 0,
  add column if not exists class_update_count integer not null default 0,
  add column if not exists session_update_count integer not null default 0,
  add column if not exists last_profile_update_at timestamptz;

-- =========================================================
-- 2. Audit tables
-- =========================================================

create table if not exists public.student_profile_audit (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.student_profiles(id) on delete cascade,
  auth_user_id uuid not null,
  action text not null,
  field_name text,
  old_value text,
  new_value text,
  created_at timestamptz not null default now()
);

create table if not exists public.audit_logs (
  id bigint generated always as identity primary key,
  actor_user_id uuid,
  actor_role text,
  action text not null,
  entity_type text,
  entity_id text,
  detail jsonb not null default '{}'::jsonb,
  ip_hash text,
  created_at timestamptz not null default now()
);

-- =========================================================
-- 3. School groups
-- =========================================================

create table if not exists public.school_groups (
  id uuid primary key default gen_random_uuid(),
  class_level text not null check (class_level in ('9','10','11','12')),
  platform text not null check (platform in ('whatsapp','telegram')),
  group_name text not null,
  group_url text,
  enabled boolean not null default false,
  updated_at timestamptz not null default now(),
  unique(class_level, platform)
);

-- =========================================================
-- 4. Website CMS
-- =========================================================

create table if not exists public.site_content (
  key text primary key,
  value text not null default '',
  updated_by uuid,
  updated_at timestamptz not null default now()
);

create table if not exists public.site_media (
  id uuid primary key default gen_random_uuid(),
  slot_key text not null unique,
  storage_path text not null,
  public_url text,
  alt_text text not null default '',
  updated_by uuid,
  updated_at timestamptz not null default now()
);

-- =========================================================
-- 5. Staff profiles / RBAC
-- =========================================================

create table if not exists public.staff_profiles (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique,
  full_name text not null,
  email text,
  role text not null check (
    role in ('teacher','clerk','principal','headmaster','admin')
  ),
  assigned_classes text[] not null default '{}',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- =========================================================
-- 6. Staff/admin helper
-- =========================================================

create or replace function public.is_staff_or_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.staff_profiles
    where auth_user_id = auth.uid()
      and active = true
  );
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.staff_profiles
    where auth_user_id = auth.uid()
      and active = true
      and role = 'admin'
  );
$$;

-- =========================================================
-- 7. Student profile audit trigger
-- =========================================================

create or replace function public.log_student_profile_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin

  if old.full_name is distinct from new.full_name then
    insert into public.student_profile_audit
      (student_id, auth_user_id, action, field_name, old_value, new_value)
    values
      (new.id, new.auth_user_id, 'PROFILE_UPDATE',
       'full_name', old.full_name, new.full_name);
  end if;

  if old.class_level is distinct from new.class_level then
    insert into public.student_profile_audit
      (student_id, auth_user_id, action, field_name, old_value, new_value)
    values
      (new.id, new.auth_user_id, 'CLASS_CHANGE',
       'class_level', old.class_level::text, new.class_level::text);
  end if;

  if old.academic_session is distinct from new.academic_session then
    insert into public.student_profile_audit
      (student_id, auth_user_id, action, field_name, old_value, new_value)
    values
      (new.id, new.auth_user_id, 'SESSION_CHANGE',
       'academic_session', old.academic_session, new.academic_session);
  end if;

  return new;
end;
$$;

drop trigger if exists trg_student_profile_audit
on public.student_profiles;

create trigger trg_student_profile_audit
after update on public.student_profiles
for each row
execute function public.log_student_profile_change();

-- =========================================================
-- 8. Secure student profile update
-- =========================================================

create or replace function public.student_update_profile(
  p_full_name text,
  p_father_name text,
  p_mother_name text,
  p_date_of_birth date,
  p_gender text,
  p_class_level text,
  p_stream text,
  p_academic_session text,
  p_address text
) returns public.student_profiles
language plpgsql security definer set search_path=public
as $$
declare
  s public.student_profiles;
  class_changed boolean;
  completing boolean;
begin
  select * into s from public.student_profiles
  where auth_user_id=auth.uid()
  for update;

  if not found then raise exception 'Student profile not found'; end if;
  if s.profile_locked then raise exception 'PROFILE_LOCKED'; end if;
  if p_class_level not in ('9','10','11','12') then raise exception 'INVALID_CLASS'; end if;

  class_changed := s.class_level is not null and s.class_level <> p_class_level;
  completing := not coalesce(s.profile_complete,false);

  if class_changed and s.class_update_count >= 2 then
    update public.student_profiles set profile_locked=true where id=s.id;
    raise exception 'PROFILE_LOCKED';
  end if;

  update public.student_profiles
  set full_name = nullif(trim(p_full_name),''),
      father_name = nullif(trim(p_father_name),''),
      mother_name = nullif(trim(p_mother_name),''),
      date_of_birth = p_date_of_birth,
      gender = nullif(trim(p_gender),''),
      class_level = p_class_level,
      stream = nullif(trim(p_stream),''),
      academic_session = nullif(trim(p_academic_session),''),
      address = nullif(trim(p_address),''),
      class_update_count = class_update_count + case when class_changed then 1 else 0 end,
      profile_complete = (
        nullif(trim(p_full_name),'') is not null and
        nullif(trim(p_father_name),'') is not null and
        p_class_level is not null and
        p_academic_session is not null
      ),
      regular_student = (
        nullif(trim(p_full_name),'') is not null and
        nullif(trim(p_father_name),'') is not null and
        p_class_level is not null and
        p_academic_session is not null
      ),
      last_profile_update_at = now(),
      profile_locked = case when class_changed and (class_update_count + 1) >= 2 then true else profile_locked end,
      updated_at = now()
  where id=s.id
  returning * into s;

  return s;
end $$;


-- =========================================================
-- V4.2 SCHOOL STAFF AUTHORIZATION
-- Real authentication/6-digit Email OTP is handled by
-- Supabase Auth in the frontend.
-- Staff accounts must be pre-authorized by Admin.
-- =========================================================

alter table public.staff_profiles
  add column if not exists staff_id text;

create unique index if not exists staff_profiles_staff_id_unique
on public.staff_profiles (lower(staff_id))
where staff_id is not null;

create unique index if not exists staff_profiles_email_unique
on public.staff_profiles (lower(email))
where email is not null;

-- ---------------------------------------------------------
-- Check whether a Staff ID + Email is pre-authorized.
-- This function intentionally returns only a boolean.
-- It does NOT expose staff records.
-- ---------------------------------------------------------

create or replace function public.staff_registration_allowed(
  p_staff_id text,
  p_email text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  return exists (
    select 1
    from public.staff_profiles
    where lower(trim(staff_id)) = lower(trim(p_staff_id))
      and lower(trim(email)) = lower(trim(p_email))
      and active = true
      and auth_user_id is null
  );
end;
$$;

-- ---------------------------------------------------------
-- After Supabase Email OTP verification, bind the
-- authenticated account to the pre-authorized staff record.
-- The authenticated user's email must match the record.
-- ---------------------------------------------------------

create or replace function public.claim_staff_account(
  p_staff_id text
)
returns public.staff_profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.staff_profiles;
  current_email text;
begin

  select lower(trim(email))
  into current_email
  from auth.users
  where id = auth.uid()
    and email_confirmed_at is not null;

  if current_email is null then
    raise exception 'EMAIL_NOT_VERIFIED';
  end if;

  select *
  into s
  from public.staff_profiles
  where lower(trim(staff_id)) = lower(trim(p_staff_id))
    and lower(trim(email)) = current_email
    and active = true
    and auth_user_id is null
  for update;

  if not found then
    raise exception 'STAFF_NOT_AUTHORIZED';
  end if;

  update public.staff_profiles
  set
    auth_user_id = auth.uid(),
    updated_at = now()
  where id = s.id
  returning *
  into s;

  insert into public.audit_logs
    (actor_user_id, actor_role, action, entity_type, entity_id, detail)
  values
    (
      auth.uid(),
      s.role,
      'STAFF_ACCOUNT_CLAIMED',
      'staff',
      s.id::text,
      jsonb_build_object(
        'staff_id', s.staff_id
      )
    );

  return s;
end;
$$;

-- ---------------------------------------------------------
-- Staff can execute only the safe registration functions.
-- ---------------------------------------------------------

revoke all on function public.staff_registration_allowed(text,text)
from public;

grant execute on function public.staff_registration_allowed(text,text)
to anon, authenticated;

revoke all on function public.claim_staff_account(text)
from public;

grant execute on function public.claim_staff_account(text)
to authenticated;

-- ---------------------------------------------------------
-- Staff profile read access
-- ---------------------------------------------------------

drop policy if exists "staff profile self select"
on public.staff_profiles;

create policy "staff profile self select"
on public.staff_profiles
for select
to authenticated
using (
  auth_user_id = auth.uid()
  or public.is_admin()
);

-- ---------------------------------------------------------
-- Staff profile mutations are NOT allowed directly.
-- Admin/server-side functions will handle them.
-- ---------------------------------------------------------

revoke insert, update, delete
on public.staff_profiles
from anon, authenticated;

-- =========================================================
-- END V4.2 STAFF AUTHORIZATION
-- =========================================================

-- =========================================================
-- V4.3 FINAL PATCH
-- Student self-registration + secure email-change limits
-- =========================================================

-- ---------------------------------------------------------
-- 1. Existing students keep their admission numbers.
-- New self-registering students can start without one.
-- NULL is allowed only for new/unassigned records.
-- ---------------------------------------------------------

alter table public.student_profiles
  alter column admission_no drop not null;

-- ---------------------------------------------------------
-- 2. Index for Auth-linked student lookup
-- ---------------------------------------------------------

create unique index if not exists
student_profiles_auth_user_id_unique
on public.student_profiles(auth_user_id)
where auth_user_id is not null;

-- ---------------------------------------------------------
-- 3. Create a verified student's profile.
-- This is called AFTER the real Supabase Email OTP
-- has been successfully verified.
-- ---------------------------------------------------------

create or replace function public.create_student_profile(
  p_full_name text,
  p_class_level text,
  p_academic_session text
)
returns public.student_profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  u auth.users;
  s public.student_profiles;
begin

  select *
  into u
  from auth.users
  where id = auth.uid()
    and email_confirmed_at is not null;

  if not found then
    raise exception 'EMAIL_NOT_VERIFIED';
  end if;

  if nullif(trim(p_full_name), '') is null then
    raise exception 'NAME_REQUIRED';
  end if;

  if p_class_level not in ('9','10','11','12') then
    raise exception 'INVALID_CLASS';
  end if;

  if nullif(trim(p_academic_session), '') is null then
    raise exception 'SESSION_REQUIRED';
  end if;

  -- If this Auth account already has a profile,
  -- return the existing profile instead of creating another one.
  select *
  into s
  from public.student_profiles
  where auth_user_id = u.id
  limit 1;

  if found then
    return s;
  end if;

  insert into public.student_profiles (
    auth_user_id,
    class_level,
    academic_session,
    full_name,
    email,
    status,
    portal_enabled,
    profile_complete,
    regular_student,
    updated_at
  )
  values (
    u.id,
    p_class_level,
    trim(p_academic_session),
    trim(p_full_name),
    lower(trim(u.email)),
    'active',
    true,
    true,
    true,
    now()
  )
  returning *
  into s;

  insert into public.audit_logs (
    actor_user_id,
    actor_role,
    action,
    entity_type,
    entity_id,
    detail
  )
  values (
    u.id,
    'student',
    'STUDENT_PROFILE_CREATED',
    'student',
    s.id::text,
    jsonb_build_object(
      'class_level', s.class_level,
      'academic_session', s.academic_session
    )
  );

  return s;
end;
$$;

revoke all on function public.create_student_profile(text,text,text)
from public;

grant execute on function public.create_student_profile(text,text,text)
to authenticated;

-- ---------------------------------------------------------
-- 4. Real email-change protection.
--
-- Supabase Auth performs the actual email change.
-- This trigger:
--   - blocks changes after 2 completed changes
--   - blocks changes on locked profiles
--   - increments the counter only when the Auth email
--     actually changes
-- ---------------------------------------------------------

create or replace function public.guard_student_email_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.student_profiles;
begin

  if old.email is distinct from new.email then

    select *
    into s
    from public.student_profiles
    where auth_user_id = old.id
    for update;

    if found then

      -- Initial email synchronization is not counted.
      if old.email is not null then

        if s.profile_locked then
          raise exception 'PROFILE_LOCKED';
        end if;

        if s.email_update_count >= 2 then
          update public.student_profiles
          set profile_locked = true,
              updated_at = now()
          where id = s.id;

          raise exception 'EMAIL_CHANGE_LIMIT_REACHED';
        end if;

      end if;

    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_student_email_change
on auth.users;

create trigger trg_guard_student_email_change
before update of email on auth.users
for each row
execute function public.guard_student_email_change();

-- ---------------------------------------------------------
-- 5. Synchronize confirmed Auth email into the student
-- profile and count only real email changes.
-- ---------------------------------------------------------

create or replace function public.sync_student_email_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.student_profiles;
begin

  if old.email is distinct from new.email then

    select *
    into s
    from public.student_profiles
    where auth_user_id = new.id
    for update;

    if found then

      update public.student_profiles
      set
        email = lower(trim(new.email)),
        email_update_count =
          case
            when old.email is null then email_update_count
            else email_update_count + 1
          end,
        profile_locked =
          case
            when old.email is not null
                 and (email_update_count + 1) >= 2
            then true
            else profile_locked
          end,
        updated_at = now()
      where id = s.id;

      insert into public.audit_logs (
        actor_user_id,
        actor_role,
        action,
        entity_type,
        entity_id,
        detail
      )
      values (
        new.id,
        'student',
        'EMAIL_CHANGED',
        'student',
        s.id::text,
        jsonb_build_object(
          'attempt',
          case
            when old.email is null then 0
            else s.email_update_count + 1
          end
        )
      );

    end if;

  end if;

  return new;
end;
$$;

drop trigger if exists trg_sync_student_email
on auth.users;

create trigger trg_sync_student_email
after update of email on auth.users
for each row
execute function public.sync_student_email_change();

-- ---------------------------------------------------------
-- 6. Email reservation function no longer consumes a
-- chance. It only checks whether a change is allowed.
-- ---------------------------------------------------------

create or replace function public.reserve_email_change()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.student_profiles;
begin

  select *
  into s
  from public.student_profiles
  where auth_user_id = auth.uid()
  for update;

  if not found then
    raise exception 'Student profile not found';
  end if;

  if s.profile_locked then
    raise exception 'PROFILE_LOCKED';
  end if;

  if s.email_update_count >= 2 then
    update public.student_profiles
    set profile_locked = true,
        updated_at = now()
    where id = s.id;

    raise exception 'EMAIL_CHANGE_LIMIT_REACHED';
  end if;

  return jsonb_build_object(
    'allowed', true,
    'used', s.email_update_count,
    'remaining', 2 - s.email_update_count
  );
end;
$$;

revoke all on function public.reserve_email_change()
from public;

grant execute on function public.reserve_email_change()
to authenticated;

-- ---------------------------------------------------------
-- 7. Staff authorization must not be enumerable publicly.
-- It will be checked through a protected server endpoint.
-- ---------------------------------------------------------

revoke all on function public.staff_registration_allowed(text,text)
from anon, authenticated;

-- Staff account claiming remains available only after
-- Supabase authentication + email verification.

-- ---------------------------------------------------------
-- 8. Admin unlock remains admin-only.
-- ---------------------------------------------------------

revoke all on function public.admin_unlock_student(uuid)
from public;

grant execute on function public.admin_unlock_student(uuid)
to authenticated;

-- =========================================================
-- END V4.3 FINAL PATCH
-- =========================================================
