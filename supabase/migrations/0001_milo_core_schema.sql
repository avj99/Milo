-- Core schema for Milo: Household -> Member -> Dog -> Product -> LogEntry

create table public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  invite_code text not null unique,
  created_at timestamptz not null default now()
);

-- A person in a household, linked to their auth user.
create table public.members (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null default 'Member',
  initials text not null default 'M',
  palette text not null default 'you',
  created_at timestamptz not null default now(),
  unique (household_id, user_id)
);
create index members_user_id_idx on public.members(user_id);
create index members_household_id_idx on public.members(household_id);

create table public.dogs (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  name text not null,
  emoji text not null default '🐶',
  breed text,
  age_months int not null default 24,
  sex text not null default 'female' check (sex in ('female','male')),
  neutered boolean not null default true,
  weight_kg numeric(6,2) not null default 10,
  ideal_weight_kg numeric(6,2) not null default 10,
  body_condition int not null default 5 check (body_condition between 1 and 9),
  life_stage text not null default 'neuteredAdult',
  activity int not null default 1 check (activity between 0 and 2),
  target_override int,
  created_at timestamptz not null default now()
);
create index dogs_household_id_idx on public.dogs(household_id);

create table public.dog_allergens (
  id uuid primary key default gen_random_uuid(),
  dog_id uuid not null references public.dogs(id) on delete cascade,
  canonical text not null,
  severity text not null default 'hard' check (severity in ('hard','soft')),
  created_at timestamptz not null default now(),
  unique (dog_id, canonical)
);
create index dog_allergens_dog_id_idx on public.dog_allergens(dog_id);

-- The food itself: household-scoped and reusable.
create table public.products (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  name text not null,
  brand text not null default '',
  emoji text not null default '🍖',
  category text not null default 'meal' check (category in ('meal','treat','addIn')),
  kcal_per_unit int not null default 0,
  portion_basis text not null default 'serving',
  ingredients text[] not null default '{}',
  verified boolean not null default false,
  is_estimate boolean not null default false,
  photo_url text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create index products_household_id_idx on public.products(household_id);

-- One product -> one dog at a time, with who logged it.
create table public.log_entries (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  dog_id uuid not null references public.dogs(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  portion_count int not null default 1,
  kcal int not null default 0,
  flagged_allergen boolean not null default false,
  logged_by uuid references auth.users(id),
  logged_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index log_entries_household_id_idx on public.log_entries(household_id);
create index log_entries_dog_id_idx on public.log_entries(dog_id);
create index log_entries_logged_at_idx on public.log_entries(logged_at desc);
