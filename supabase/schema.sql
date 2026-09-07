-- School portal database schema
-- Run this in Supabase SQL Editor after the project is created.
-- Public users can read published content. No public INSERT/UPDATE/DELETE policies are created.

create extension if not exists pgcrypto;

create table if not exists public.site_settings (
  id uuid primary key default gen_random_uuid(),
  school_name text not null default 'सरस्वती विद्या निकेतन (मॉडल स्कूल)',
  address text not null default 'उत्क्रमित उच्चतर माध्यमिक विद्यालय, बनकटवा, पूर्वी चंपारण',
  udise_code text not null default '10020400220',
  principal_message text,
  phone text,
  email text,
  updated_at timestamptz not null default now()
);

create table if not exists public.notices (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  published_on date not null default current_date,
  is_published boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.staff (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  designation text not null,
  subject text,
  photo_url text,
  sort_order integer not null default 0,
  is_published boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.achievements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  achievement_date date,
  image_url text,
  is_published boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.gallery (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  image_url text not null,
  alt_text text,
  sort_order integer not null default 0,
  is_published boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.downloads (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  file_url text not null,
  file_type text,
  published_on date not null default current_date,
  is_published boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.site_settings enable row level security;
alter table public.notices enable row level security;
alter table public.staff enable row level security;
alter table public.achievements enable row level security;
alter table public.gallery enable row level security;
alter table public.downloads enable row level security;

-- Public read-only policies for published website content.
create policy "Public can read site settings"
  on public.site_settings for select using (true);

create policy "Public can read published notices"
  on public.notices for select using (is_published = true);

create policy "Public can read published staff"
  on public.staff for select using (is_published = true);

create policy "Public can read published achievements"
  on public.achievements for select using (is_published = true);

create policy "Public can read published gallery"
  on public.gallery for select using (is_published = true);

create policy "Public can read published downloads"
  on public.downloads for select using (is_published = true);

insert into public.site_settings (school_name, address, udise_code)
select 'सरस्वती विद्या निकेतन (मॉडल स्कूल)', 'उत्क्रमित उच्चतर माध्यमिक विद्यालय, बनकटवा, पूर्वी चंपारण', '10020400220'
where not exists (select 1 from public.site_settings);
