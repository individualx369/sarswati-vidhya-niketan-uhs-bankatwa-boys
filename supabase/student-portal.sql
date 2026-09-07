-- Student Portal schema
-- Run once in Supabase SQL Editor after schema.sql.
-- Sensitive student records are private and protected by Supabase Auth + RLS.
-- Aadhaar numbers are intentionally NOT stored here.

create table if not exists public.student_profiles (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users(id) on delete set null,
  admission_no text not null unique,
  roll_no text,
  class_level text not null check (class_level in ('9','10','11','12')),
  stream text,
  academic_session text not null,
  full_name text not null,
  father_name text,
  mother_name text,
  date_of_birth date,
  gender text,
  phone text,
  email text,
  address text,
  registration_no text,
  bseb_roll_code text,
  bseb_roll_no text,
  status text not null default 'active' check (status in ('active','inactive','passed_out','transferred')),
  portal_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.student_access_codes (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null unique references public.student_profiles(id) on delete cascade,
  code_hash text not null,
  expires_at timestamptz,
  used_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.student_results (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.student_profiles(id) on delete cascade,
  academic_session text not null,
  exam_type text not null check (exam_type in ('mid_term','quarterly','half_yearly','annual','unit_test','pre_board','other')),
  exam_date date,
  subjects jsonb not null default '[]'::jsonb,
  total_marks numeric,
  obtained_marks numeric,
  percentage numeric,
  grade text,
  remarks text,
  published boolean not null default false,
  created_at timestamptz not null default now(),
  unique(student_id, academic_session, exam_type)
);

create table if not exists public.student_exam_forms (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.student_profiles(id) on delete cascade,
  exam_name text not null,
  session text not null,
  form_start date,
  form_last_date date,
  registration_date date,
  status text not null default 'pending' check (status in ('pending','submitted','verified','rejected','closed')),
  reference_no text,
  remarks text,
  created_at timestamptz not null default now()
);

create table if not exists public.bonafide_documents (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.student_profiles(id) on delete cascade,
  certificate_no text not null unique,
  issue_date date not null default current_date,
  purpose text,
  file_url text,
  generated_by uuid,
  created_at timestamptz not null default now()
);

create table if not exists public.student_notifications (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.student_profiles(id) on delete cascade,
  title text not null,
  body text not null,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.portal_links (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  url text not null,
  category text not null default 'official',
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

alter table public.student_profiles enable row level security;
alter table public.student_access_codes enable row level security;
alter table public.student_results enable row level security;
alter table public.student_exam_forms enable row level security;
alter table public.bonafide_documents enable row level security;
alter table public.student_notifications enable row level security;
alter table public.portal_links enable row level security;

revoke all on public.student_profiles from anon;
revoke all on public.student_access_codes from anon, authenticated;
revoke all on public.student_results from anon;
revoke all on public.student_exam_forms from anon;
revoke all on public.bonafide_documents from anon;
revoke all on public.student_notifications from anon;

create policy "Students read own profile"
  on public.student_profiles for select
  to authenticated
  using (auth.uid() = auth_user_id and portal_enabled = true);

create policy "Students read own results"
  on public.student_results for select
  to authenticated
  using (exists (select 1 from public.student_profiles s where s.id = student_results.student_id and s.auth_user_id = auth.uid() and s.portal_enabled = true) and published = true);

create policy "Students read own exam forms"
  on public.student_exam_forms for select
  to authenticated
  using (exists (select 1 from public.student_profiles s where s.id = student_exam_forms.student_id and s.auth_user_id = auth.uid() and s.portal_enabled = true));

create policy "Students read own bonafide records"
  on public.bonafide_documents for select
  to authenticated
  using (exists (select 1 from public.student_profiles s where s.id = bonafide_documents.student_id and s.auth_user_id = auth.uid() and s.portal_enabled = true));

create policy "Students read own notifications"
  on public.student_notifications for select
  to authenticated
  using (exists (select 1 from public.student_profiles s where s.id = student_notifications.student_id and s.auth_user_id = auth.uid() and s.portal_enabled = true));

create policy "Public reads active official links"
  on public.portal_links for select
  to anon, authenticated
  using (is_active = true);

insert into public.portal_links (title, description, url, category, sort_order)
select * from (values
  ('BSEB Official Portal','बिहार विद्यालय परीक्षा समिति का आधिकारिक पोर्टल','https://www.biharboardonline.org/','bseb',10),
  ('BSEB Secondary Portal','माध्यमिक परीक्षा/रजिस्ट्रेशन से संबंधित आधिकारिक पोर्टल','https://secondary.biharboardonline.org/','bseb',20),
  ('Bihar Post Matric Scholarship','बिहार सरकार का आधिकारिक Post Matric Scholarship पोर्टल','https://pmsonline.bihar.gov.in/','scholarship',30),
  ('PMS Institute Portal','संस्थान/नोडल अधिकारी के लिए आधिकारिक PMS पोर्टल','https://instpmsonline.bihar.gov.in/','scholarship',40)
) as v(title,description,url,category,sort_order)
where not exists (select 1 from public.portal_links p where p.url = v.url);
