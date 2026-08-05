-- Britt's OS — initial schema
-- PRD §3 Data Model. Postgres via Supabase.
-- Conventions: every table has id uuid pk default gen_random_uuid(), created_at, updated_at (timestamptz).
-- All timestamps stored UTC, rendered America/Chicago in the app layer.

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- updated_at trigger helper
-- ---------------------------------------------------------------------------
create or replace function set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

-- ---------------------------------------------------------------------------
-- ENUMS
-- ---------------------------------------------------------------------------
create type deal_side as enum ('buyer', 'seller', 'both');

create type deal_status as enum (
  'active_search', 'listing_prep', 'active_listing', 'under_contract',
  'inspection', 'appraisal', 'financing', 'clear_to_close', 'closing',
  'sold', 'dead'
);

create type financing_type as enum ('conventional', 'fha', 'va', 'usda', 'cash');

create type deal_health as enum ('green', 'amber', 'red');

create type task_anchor as enum (
  'contract', 'inspection', 'appraisal', 'financing', 'closing',
  'list_date', 'manual'
);

create type task_status as enum ('open', 'done', 'skipped');

create type task_priority as enum ('low', 'normal', 'high');

create type appt_source as enum ('calendly', 'google', 'showingtime', 'manual');

create type appt_type as enum (
  'showing', 'listing_appt', 'buyer_consult', 'closing', 'inspection',
  'photo_shoot', 'other'
);

create type appt_status as enum ('scheduled', 'completed', 'cancelled', 'no_show');

create type content_pillar as enum (
  'area_guides', 'pros_cons', 'gut_check', 'cost_of_living', 'livestream'
);

create type content_format as enum (
  'youtube_long', 'reel', 'livestream', 'email', 'blog', 'carousel', 'gbp_post'
);

create type content_status as enum (
  'idea', 'scripted', 'filmed', 'editing', 'scheduled', 'published'
);

create type content_source as enum (
  'deal', 'contact_question', 'listing', 'market_data', 'manual'
);

create type vendor_category as enum (
  'lender', 'title', 'inspector', 'photographer', 'stager', 'contractor', 'other'
);

create type document_category as enum (
  'contract', 'disclosure', 'inspection_report', 'appraisal', 'photos', 'other'
);

create type notification_channel as enum ('email', 'sms', 'in_app');

-- ---------------------------------------------------------------------------
-- contacts — mirror of Follow Up Boss. The OS does not own this data.
-- ---------------------------------------------------------------------------
create table contacts (
  id uuid primary key default gen_random_uuid(),
  fub_person_id bigint unique not null,
  first_name text,
  last_name text,
  emails jsonb not null default '[]',          -- [{value, type, is_primary}]
  phones jsonb not null default '[]',          -- [{value, type, is_primary}]
  stage text,                                  -- Lead, Hot, Nurture, Active Client, Past Client
  source text,                                 -- Ylopo, Google, Meta, Referral, Sphere, YouTube, Open House
  tags text[] not null default '{}',
  assigned_pond text,
  fub_created_at timestamptz,
  last_inbound_at timestamptz,
  last_outbound_at timestamptz,
  lifetime_value numeric not null default 0,
  lead_score int not null default 0,           -- 0..100, recomputed nightly + on webhook
  is_archived boolean not null default false,
  synced_at timestamptz,
  fub_raw jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- needs_response: last_inbound_at is later than last_outbound_at. Powers half the dashboard.
alter table contacts
  add column needs_response boolean
  generated always as (
    last_inbound_at is not null
    and (last_outbound_at is null or last_inbound_at > last_outbound_at)
  ) stored;

create index contacts_needs_response_idx on contacts (needs_response) where needs_response;
create index contacts_lead_score_idx on contacts (lead_score desc);
create index contacts_stage_idx on contacts (stage);

create trigger contacts_updated_at before update on contacts
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------------------
-- properties — reusable. Deduped on mls_number, else normalized address hash.
-- ---------------------------------------------------------------------------
create table properties (
  id uuid primary key default gen_random_uuid(),
  mls_number text unique,
  address_line1 text,
  city text,
  state text,
  zip text,
  address_hash text unique,                    -- normalized lowercase street + zip
  county text,                                 -- Montgomery, Autauga, Elmore, Lee
  latitude numeric,
  longitude numeric,
  beds numeric,
  baths numeric,
  sqft numeric,
  lot_size numeric,
  year_built numeric,
  subdivision text,
  school_district text,
  photos jsonb not null default '[]',
  mls_raw jsonb,
  last_synced_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger properties_updated_at before update on properties
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------------------
-- vendors
-- ---------------------------------------------------------------------------
create table vendors (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  company text,
  category vendor_category not null default 'other',
  phone text,
  email text,
  rating int check (rating between 1 and 5),
  notes text,
  is_preferred boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger vendors_updated_at before update on vendors
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------------------
-- deals — the center of the model. One row per transaction side.
-- ---------------------------------------------------------------------------
create table deals (
  id uuid primary key default gen_random_uuid(),
  contact_id uuid not null references contacts(id) on delete cascade,
  property_id uuid references properties(id) on delete set null,
  side deal_side not null,
  status deal_status not null default 'active_search',
  contract_date date,
  inspection_deadline date,
  appraisal_deadline date,
  financing_deadline date,
  closing_date date,
  sale_price numeric,
  commission_rate numeric not null default 0.03,   -- [CUSTOMIZE]
  financing_type financing_type,
  lender_vendor_id uuid references vendors(id) on delete set null,
  title_vendor_id uuid references vendors(id) on delete set null,
  inspector_vendor_id uuid references vendors(id) on delete set null,
  brokerage_file_url text,
  notes text,
  dead_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- gross_commission computed
alter table deals
  add column gross_commission numeric
  generated always as (coalesce(sale_price, 0) * coalesce(commission_rate, 0)) stored;

create index deals_status_idx on deals (status);
create index deals_contact_idx on deals (contact_id);
create index deals_closing_idx on deals (closing_date);

create trigger deals_updated_at before update on deals
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------------------
-- listings — extends a seller-side deal with listing tracking.
-- ---------------------------------------------------------------------------
create table listings (
  id uuid primary key default gen_random_uuid(),
  deal_id uuid not null references deals(id) on delete cascade,
  property_id uuid references properties(id) on delete set null,
  list_date date,
  list_price numeric,
  current_price numeric,
  price_history jsonb not null default '[]',      -- [{date, price, reason}]
  mls_status text,
  showing_count_7d int not null default 0,
  showing_count_total int not null default 0,
  unread_feedback_count int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index listings_deal_idx on listings (deal_id);

create trigger listings_updated_at before update on listings
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------------------
-- task_templates + items — templates are data, not code.
-- ---------------------------------------------------------------------------
create table task_templates (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  side deal_side not null,
  financing_type financing_type,                  -- nullable = matches any
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger task_templates_updated_at before update on task_templates
  for each row execute function set_updated_at();

create table task_template_items (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references task_templates(id) on delete cascade,
  title text not null,
  description text,
  anchor_type task_anchor not null default 'manual',
  offset_days int not null default 0,
  priority task_priority not null default 'normal',
  sort_order int not null default 0,
  default_pinned boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index task_template_items_template_idx on task_template_items (template_id);

create trigger task_template_items_updated_at before update on task_template_items
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------------------
-- tasks — the workhorse.
-- ---------------------------------------------------------------------------
create table tasks (
  id uuid primary key default gen_random_uuid(),
  deal_id uuid references deals(id) on delete cascade,
  contact_id uuid references contacts(id) on delete cascade,
  title text not null,
  description text,
  due_date date,
  due_time time,
  anchor_type task_anchor,
  anchor_offset_days int,
  is_pinned boolean not null default false,        -- holds date when anchor moves
  status task_status not null default 'open',
  priority task_priority not null default 'normal',
  template_item_id uuid references task_template_items(id) on delete set null,
  is_client_visible boolean not null default false,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index tasks_deal_idx on tasks (deal_id);
create index tasks_contact_idx on tasks (contact_id);
create index tasks_due_idx on tasks (due_date) where status = 'open';
create index tasks_status_idx on tasks (status);

create trigger tasks_updated_at before update on tasks
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------------------
-- appointments
-- ---------------------------------------------------------------------------
create table appointments (
  id uuid primary key default gen_random_uuid(),
  contact_id uuid references contacts(id) on delete set null,
  property_id uuid references properties(id) on delete set null,
  deal_id uuid references deals(id) on delete cascade,
  external_id text,
  source appt_source not null default 'manual',
  type appt_type not null default 'other',
  starts_at timestamptz not null,
  ends_at timestamptz,
  location text,
  notes text,
  status appt_status not null default 'scheduled',
  feedback text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (source, external_id)
);

create index appointments_starts_idx on appointments (starts_at);
create index appointments_deal_idx on appointments (deal_id);

create trigger appointments_updated_at before update on appointments
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------------------
-- content_items — first-class.
-- ---------------------------------------------------------------------------
create table content_items (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  pillar content_pillar,
  format content_format,
  status content_status not null default 'idea',
  target_publish_date date,
  hook text,
  notes text,
  source_type content_source,
  source_deal_id uuid references deals(id) on delete set null,
  source_contact_id uuid references contacts(id) on delete set null,
  canva_url text,
  published_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index content_items_status_idx on content_items (status);
create index content_items_publish_idx on content_items (target_publish_date);

create trigger content_items_updated_at before update on content_items
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------------------
-- documents
-- ---------------------------------------------------------------------------
create table documents (
  id uuid primary key default gen_random_uuid(),
  deal_id uuid references deals(id) on delete cascade,
  name text not null,
  category document_category not null default 'other',
  storage_path text,
  file_size bigint,
  uploaded_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index documents_deal_idx on documents (deal_id);

-- ---------------------------------------------------------------------------
-- Supporting tables
-- ---------------------------------------------------------------------------
create table activity_log (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null,
  entity_id uuid,
  action text not null,
  actor text not null default 'system',           -- 'system' | 'britt'
  payload jsonb,
  occurred_at timestamptz not null default now()
);

create index activity_log_entity_idx on activity_log (entity_type, entity_id);
create index activity_log_occurred_idx on activity_log (occurred_at desc);

create table notifications (
  id uuid primary key default gen_random_uuid(),
  type text not null,
  channel notification_channel not null,
  payload jsonb,
  scheduled_for timestamptz,
  sent_at timestamptz,
  status text not null default 'pending',
  dedupe_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (dedupe_key)
);

create trigger notifications_updated_at before update on notifications
  for each row execute function set_updated_at();

create table sync_state (
  id uuid primary key default gen_random_uuid(),
  integration text unique not null,
  cursor text,                                     -- last modification timestamp seen
  last_run_at timestamptz,
  last_success_at timestamptz,
  error_count int not null default 0,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger sync_state_updated_at before update on sync_state
  for each row execute function set_updated_at();

-- settings — single row.
create table settings (
  id uuid primary key default gen_random_uuid(),
  business_hours jsonb not null default '{"start":"08:00","end":"18:00"}',
  quiet_hours jsonb not null default '{"start":"21:00","end":"06:00"}',
  default_commission_rate numeric not null default 0.03,
  notification_prefs jsonb not null default '{}',
  market_thresholds jsonb not null default '{"dom_median":45}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger settings_updated_at before update on settings
  for each row execute function set_updated_at();

insert into settings default values;
