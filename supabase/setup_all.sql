-- ============================================================
-- Britt's OS — complete database setup (paste into Supabase SQL Editor)
-- Runs: schema  +  task templates  +  sample data, in order.
-- Safe to run once on an empty project.
-- ============================================================

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

-- Britt's OS — starter task templates (PRD §5.4)
-- These are real starting points, editable in the UI later.

-- Buyer, Under Contract, Financed --------------------------------------------
with t as (
  insert into task_templates (name, side, financing_type, is_active)
  values ('Buyer — Under Contract (Financed)', 'buyer', 'conventional', true)
  returning id
)
insert into task_template_items (template_id, title, anchor_type, offset_days, priority, sort_order, default_pinned)
select t.id, x.title, x.anchor::task_anchor, x.offset_days, x.priority::task_priority, x.sort_order, false
from t, (values
  ('Send executed contract to client and lender', 'contract', 0, 'high', 1),
  ('Confirm earnest money delivered', 'contract', 1, 'high', 2),
  ('Order inspection', 'contract', 1, 'high', 3),
  ('Confirm lender has full file', 'contract', 2, 'normal', 4),
  ('Check inspection scheduled', 'contract', 3, 'normal', 5),
  ('Attend inspection', 'inspection', 0, 'high', 6),
  ('Review inspection report with client', 'inspection', 1, 'high', 7),
  ('Submit repair request', 'inspection', 2, 'high', 8),
  ('Confirm repair agreement executed', 'inspection', 4, 'high', 9),
  ('Confirm appraisal ordered', 'contract', 5, 'normal', 10),
  ('Follow up on appraisal result', 'appraisal', 1, 'high', 11),
  ('Lender check-in, conditions cleared?', 'financing', -7, 'high', 12),
  ('Confirm clear to close', 'financing', 0, 'high', 13),
  ('Send utilities transfer reminder', 'closing', -7, 'normal', 14),
  ('Order home warranty if applicable', 'closing', -7, 'low', 15),
  ('Confirm closing time and location with title', 'closing', -3, 'high', 16),
  ('Send wire fraud warning to client', 'closing', -3, 'high', 17),
  ('Schedule final walkthrough', 'closing', -2, 'high', 18),
  ('Final walkthrough', 'closing', -1, 'high', 19),
  ('Confirm closing disclosure reviewed', 'closing', -1, 'normal', 20),
  ('Attend closing', 'closing', 0, 'high', 21),
  ('Post-close: closing gift delivered', 'closing', 2, 'normal', 22),
  ('Post-close: ask for review', 'closing', 7, 'normal', 23),
  ('Post-close: film testimonial ask', 'closing', 10, 'low', 24),
  ('Add to past client nurture', 'closing', 14, 'normal', 25)
) as x(title, anchor, offset_days, priority, sort_order);

-- Buyer, Cash ----------------------------------------------------------------
with t as (
  insert into task_templates (name, side, financing_type, is_active)
  values ('Buyer — Cash', 'buyer', 'cash', true)
  returning id
)
insert into task_template_items (template_id, title, anchor_type, offset_days, priority, sort_order, default_pinned)
select t.id, x.title, x.anchor::task_anchor, x.offset_days, x.priority::task_priority, x.sort_order, false
from t, (values
  ('Send executed contract to client', 'contract', 0, 'high', 1),
  ('Confirm earnest money delivered', 'contract', 1, 'high', 2),
  ('Order inspection', 'contract', 1, 'high', 3),
  ('Attend inspection', 'inspection', 0, 'high', 4),
  ('Review inspection report with client', 'inspection', 1, 'high', 5),
  ('Submit repair request', 'inspection', 2, 'high', 6),
  ('Confirm proof of funds to title', 'contract', 3, 'normal', 7),
  ('Confirm closing time and location with title', 'closing', -3, 'high', 8),
  ('Send wire fraud warning to client', 'closing', -3, 'high', 9),
  ('Schedule final walkthrough', 'closing', -2, 'high', 10),
  ('Final walkthrough', 'closing', -1, 'high', 11),
  ('Attend closing', 'closing', 0, 'high', 12),
  ('Post-close: closing gift delivered', 'closing', 2, 'normal', 13),
  ('Post-close: ask for review', 'closing', 7, 'normal', 14)
) as x(title, anchor, offset_days, priority, sort_order);

-- Buyer, VA / FHA ------------------------------------------------------------
with t as (
  insert into task_templates (name, side, financing_type, is_active)
  values ('Buyer — VA / FHA', 'buyer', 'va', true)
  returning id
)
insert into task_template_items (template_id, title, anchor_type, offset_days, priority, sort_order, default_pinned)
select t.id, x.title, x.anchor::task_anchor, x.offset_days, x.priority::task_priority, x.sort_order, false
from t, (values
  ('Send executed contract to client and lender', 'contract', 0, 'high', 1),
  ('Confirm earnest money delivered', 'contract', 1, 'high', 2),
  ('Order inspection', 'contract', 1, 'high', 3),
  ('Confirm appraisal ordered by correct assigned appraiser', 'contract', 3, 'high', 4),
  ('Attend inspection', 'inspection', 0, 'high', 5),
  ('Review inspection report with client', 'inspection', 1, 'high', 6),
  ('Submit repair request', 'inspection', 2, 'high', 7),
  ('Review appraisal repair requirements', 'appraisal', 1, 'high', 8),
  ('Confirm termite / pest letter ordered', 'closing', -10, 'high', 9),
  ('Lender check-in, conditions cleared?', 'financing', -7, 'high', 10),
  ('Confirm clear to close', 'financing', 0, 'high', 11),
  ('Confirm closing time and location with title', 'closing', -3, 'high', 12),
  ('Send wire fraud warning to client', 'closing', -3, 'high', 13),
  ('Final walkthrough', 'closing', -1, 'high', 14),
  ('Attend closing', 'closing', 0, 'high', 15),
  ('Post-close: closing gift delivered', 'closing', 2, 'normal', 16),
  ('Post-close: ask for review', 'closing', 7, 'normal', 17)
) as x(title, anchor, offset_days, priority, sort_order);

-- Seller, Listing Live -------------------------------------------------------
with t as (
  insert into task_templates (name, side, financing_type, is_active)
  values ('Seller — Listing Live', 'seller', null, true)
  returning id
)
insert into task_template_items (template_id, title, anchor_type, offset_days, priority, sort_order, default_pinned)
select t.id, x.title, x.anchor::task_anchor, x.offset_days, x.priority::task_priority, x.sort_order, false
from t, (values
  ('Photos scheduled', 'list_date', -7, 'high', 1),
  ('Sign installed', 'list_date', -2, 'normal', 2),
  ('Listing entered in MLS, proofread twice', 'list_date', -1, 'high', 3),
  ('Listing live, verify syndication to Zillow and Realtor', 'list_date', 0, 'high', 4),
  ('Post listing to social, all channels', 'list_date', 0, 'normal', 5),
  ('Send just-listed to sphere', 'list_date', 1, 'normal', 6),
  ('Open house scheduled', 'list_date', 3, 'normal', 7),
  ('First seller update call', 'list_date', 7, 'high', 8),
  ('Weekly seller update', 'list_date', 14, 'normal', 9),
  ('Showing feedback review with seller', 'list_date', 14, 'normal', 10),
  ('Price and position review', 'list_date', 21, 'high', 11)
) as x(title, anchor, offset_days, priority, sort_order);

-- Seller, Under Contract -----------------------------------------------------
with t as (
  insert into task_templates (name, side, financing_type, is_active)
  values ('Seller — Under Contract', 'seller', null, true)
  returning id
)
insert into task_template_items (template_id, title, anchor_type, offset_days, priority, sort_order, default_pinned)
select t.id, x.title, x.anchor::task_anchor, x.offset_days, x.priority::task_priority, x.sort_order, false
from t, (values
  ('Confirm earnest money received', 'contract', 1, 'high', 1),
  ('Prepare for inspection access', 'inspection', -1, 'normal', 2),
  ('Respond to repair request', 'inspection', 3, 'high', 3),
  ('Confirm appraisal access', 'appraisal', -1, 'normal', 4),
  ('Confirm buyer financing progress', 'financing', -7, 'normal', 5),
  ('Order payoff', 'closing', -7, 'high', 6),
  ('Confirm closing figures', 'closing', -2, 'high', 7),
  ('Attend closing', 'closing', 0, 'high', 8)
) as x(title, anchor, offset_days, priority, sort_order);

-- Britt's OS — sample data seed (generated). Run after 0001_init.sql + 0002_templates_seed.sql.
begin;

-- contacts
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('0d4be804-1251-4b16-b3f5-8747c03c4d3a', 1000, 'Marcus', 'Bell', '[{"value":"marcus.bell@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1000","is_primary":true}]'::jsonb, 'Hot', 'Referral', '{}', '2026-05-14T09:00:00.000Z', '2026-08-12T08:00:00.000Z', '2026-08-09T10:00:00.000Z', 0, 86, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('699cc395-785a-403a-972c-683adca95e3c', 1001, 'Dana', 'Whitfield', '[{"value":"dana.whitfield@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1001","is_primary":true}]'::jsonb, 'Hot', 'YouTube', '{}', '2026-05-13T09:00:00.000Z', '2026-08-12T09:00:00.000Z', '2026-08-07T10:00:00.000Z', 0, 88, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('7ac2e4ec-b357-4c90-a45c-564d9b174cab', 1002, 'Priya', 'Nair', '[{"value":"priya.nair@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1002","is_primary":true}]'::jsonb, 'Active Client', 'Sphere', '{}', '2026-05-12T09:00:00.000Z', '2026-08-11T10:00:00.000Z', '2026-08-08T10:00:00.000Z', 0, 82, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('a4d7f324-30f6-4f63-b9ef-89e026a17530', 1003, 'Travis', 'Boone', '[{"value":"travis.boone@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1003","is_primary":true}]'::jsonb, 'Hot', 'Open House', '{}', '2026-05-11T09:00:00.000Z', '2026-08-10T11:00:00.000Z', '2026-08-02T10:00:00.000Z', 0, 80, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('6021bd36-ae2a-4381-8408-f534e41102b7', 1004, 'Latoya', 'Simmons', '[{"value":"latoya.simmons@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1004","is_primary":true}]'::jsonb, 'Active Client', 'Referral', '{}', '2026-05-10T09:00:00.000Z', '2026-08-09T12:00:00.000Z', '2026-08-09T10:00:00.000Z', 0, 67, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('f14341ae-4808-40d4-8e03-d6cb8958a2ac', 1005, 'Grant', 'Holloway', '[{"value":"grant.holloway@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1005","is_primary":true}]'::jsonb, 'Nurture', 'Ylopo', '{}', '2026-05-09T09:00:00.000Z', '2026-08-06T13:00:00.000Z', '2026-08-10T10:00:00.000Z', 0, 35, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('4eeb17fd-f77c-4715-ac0b-8390e846762b', 1006, 'Bethany', 'Cruz', '[{"value":"bethany.cruz@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1006","is_primary":true}]'::jsonb, 'New Lead', 'Meta', '{}', '2026-08-06T09:00:00.000Z', '2026-08-10T14:00:00.000Z', '2026-08-11T10:00:00.000Z', 0, 37, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('9a2d7959-c5b6-46e8-9396-3eccf7f335ff', 1007, 'Sean', 'Delacroix', '[{"value":"sean.delacroix@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1007","is_primary":true}]'::jsonb, 'Hot', 'Referral', '{}', '2026-05-07T09:00:00.000Z', null, null, 0, 44, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('e80fd06b-4da8-4c52-a4e1-14d0673878c2', 1008, 'Imani', 'Rhodes', '[{"value":"imani.rhodes@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1008","is_primary":true}]'::jsonb, 'Active Client', 'Sphere', '{}', '2026-05-06T09:00:00.000Z', '2026-08-03T08:00:00.000Z', '2026-07-29T10:00:00.000Z', 0, 58, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('6e2bfaa9-5359-481d-8e59-4064a023018e', 1009, 'Colton', 'Reyes', '[{"value":"colton.reyes@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1009","is_primary":true}]'::jsonb, 'New Lead', 'Google', '{}', '2026-08-10T09:00:00.000Z', '2026-08-11T09:00:00.000Z', '2026-08-10T10:00:00.000Z', 0, 63, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('2e57401f-af54-4147-995e-676cc52df5f6', 1010, 'Renee', 'Abbott', '[{"value":"renee.abbott@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1010","is_primary":true}]'::jsonb, 'Nurture', 'YouTube', '{}', '2026-05-04T09:00:00.000Z', '2026-07-31T10:00:00.000Z', '2026-08-09T10:00:00.000Z', 0, 29, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('54479a15-9638-4cc1-9aa7-11d16f410074', 1011, 'Deshawn', 'Pope', '[{"value":"deshawn.pope@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1011","is_primary":true}]'::jsonb, 'Past Client', 'Referral', '{}', '2026-05-03T09:00:00.000Z', null, null, 9600, 33, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('a56c6714-7033-40e2-981c-4a3277f93f75', 1012, 'Kaylee', 'Monroe', '[{"value":"kaylee.monroe@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1012","is_primary":true}]'::jsonb, 'Hot', 'Open House', '{}', '2026-05-02T09:00:00.000Z', '2026-08-12T12:00:00.000Z', '2026-08-04T10:00:00.000Z', 0, 81, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('eb829db3-5790-45b4-8b94-38f6a7fb2a86', 1013, 'Victor', 'Ianelli', '[{"value":"victor.ianelli@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1013","is_primary":true}]'::jsonb, 'Active Client', 'Ylopo', '{}', '2026-05-01T09:00:00.000Z', '2026-08-08T13:00:00.000Z', '2026-08-11T10:00:00.000Z', 0, 41, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('daf87e74-b3c6-4878-a891-2ed3ae86187b', 1014, 'Nadia', 'Frost', '[{"value":"nadia.frost@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1014","is_primary":true}]'::jsonb, 'New Lead', 'Meta', '{}', '2026-08-12T09:00:00.000Z', '2026-08-10T14:00:00.000Z', null, 0, 67, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('63094b93-1682-4bef-995e-bfa7d754f447', 1015, 'Bryce', 'Calloway', '[{"value":"bryce.calloway@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1015","is_primary":true}]'::jsonb, 'Nurture', 'Google', '{}', '2026-04-29T09:00:00.000Z', '2026-07-03T15:00:00.000Z', '2026-08-08T10:00:00.000Z', 0, 19, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('3a6da87c-0b03-48a8-ae87-6547525279d4', 1016, 'Selena', 'Ortega', '[{"value":"selena.ortega@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1016","is_primary":true}]'::jsonb, 'Hot', 'Referral', '{}', '2026-04-28T09:00:00.000Z', '2026-08-12T08:00:00.000Z', '2026-08-11T10:00:00.000Z', 0, 86, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('dd87d1ee-4d6b-4548-a4bb-52a33e1bc42e', 1017, 'Omar', 'Haddad', '[{"value":"omar.haddad@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1017","is_primary":true}]'::jsonb, 'Active Client', 'Sphere', '{}', '2026-04-27T09:00:00.000Z', '2026-08-07T09:00:00.000Z', '2026-08-06T10:00:00.000Z', 0, 71, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('4c89f514-80cb-4f7e-9010-19babaeb2257', 1018, 'Kelsey', 'Vance', '[{"value":"kelsey.vance@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1018","is_primary":true}]'::jsonb, 'Past Client', 'Sphere', '{}', '2026-04-26T09:00:00.000Z', null, null, 11200, 25, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('e92ee1a5-b21b-4e27-bd66-52115578e209', 1019, 'Trent', 'Buford', '[{"value":"trent.buford@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1019","is_primary":true}]'::jsonb, 'New Lead', 'Ylopo', '{}', '2026-08-07T09:00:00.000Z', '2026-08-11T11:00:00.000Z', '2026-08-12T10:00:00.000Z', 0, 41, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('590edb4c-cc5f-4705-aa3a-5e2daaa5a538', 1020, 'Alicia', 'Kwan', '[{"value":"alicia.kwan@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1020","is_primary":true}]'::jsonb, 'Nurture', 'YouTube', '{}', '2026-04-24T09:00:00.000Z', '2026-07-28T12:00:00.000Z', '2026-08-07T10:00:00.000Z', 0, 33, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('c9a4809f-c288-4906-9837-4c3e3b75f9a1', 1021, 'Gabe', 'Sutter', '[{"value":"gabe.sutter@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1021","is_primary":true}]'::jsonb, 'Hot', 'Open House', '{}', '2026-04-23T09:00:00.000Z', '2026-08-09T13:00:00.000Z', '2026-07-31T10:00:00.000Z', 0, 69, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('1f081dc0-c4a3-424a-a7a5-dcf26d82495d', 1022, 'Monique', 'Dill', '[{"value":"monique.dill@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1022","is_primary":true}]'::jsonb, 'Active Client', 'Referral', '{}', '2026-04-22T09:00:00.000Z', '2026-08-04T14:00:00.000Z', '2026-08-10T10:00:00.000Z', 0, 41, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('074a7459-b010-41f2-9fdd-a09a76ce64b1', 1023, 'Parker', 'Ellison', '[{"value":"parker.ellison@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1023","is_primary":true}]'::jsonb, 'New Lead', 'Google', '{}', '2026-08-10T09:00:00.000Z', '2026-08-12T15:00:00.000Z', '2026-08-12T10:00:00.000Z', 0, 76, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('a248d8c6-660d-44d3-94a7-542d3ee8ea16', 1024, 'Rosa', 'Benitez', '[{"value":"rosa.benitez@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1024","is_primary":true}]'::jsonb, 'Nurture', 'Meta', '{}', '2026-04-20T09:00:00.000Z', '2026-07-21T08:00:00.000Z', '2026-08-06T10:00:00.000Z', 0, 19, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('3b3723b3-b1d8-4b6d-be73-53cda3a82958', 1025, 'Chad', 'Mercer', '[{"value":"chad.mercer@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1025","is_primary":true}]'::jsonb, 'Past Client', 'Referral', '{}', '2026-04-19T09:00:00.000Z', null, null, 8700, 29, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('26046a11-57fc-4ae6-888f-9dd80af8b2f7', 1026, 'Yasmin', 'Attah', '[{"value":"yasmin.attah@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1026","is_primary":true}]'::jsonb, 'Hot', 'Sphere', '{}', '2026-04-18T09:00:00.000Z', '2026-08-12T10:00:00.000Z', '2026-08-10T10:00:00.000Z', 0, 94, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('02a61107-ac96-4a7e-85ff-7c85e1ff1e65', 1027, 'Blake', 'Fontaine', '[{"value":"blake.fontaine@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1027","is_primary":true}]'::jsonb, 'Active Client', 'Ylopo', '{}', '2026-04-17T09:00:00.000Z', '2026-08-01T11:00:00.000Z', '2026-08-09T10:00:00.000Z', 0, 29, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('c343b1f8-757a-46ee-bba0-db35f9fb3a53', 1028, 'Erin', 'Gallagher', '[{"value":"erin.gallagher@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1028","is_primary":true}]'::jsonb, 'New Lead', 'YouTube', '{}', '2026-08-12T09:00:00.000Z', '2026-08-11T12:00:00.000Z', '2026-08-12T10:00:00.000Z', 0, 47, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('17c6c418-290b-4db8-86bc-e0b6525a48f8', 1029, 'Damon', 'Wexler', '[{"value":"damon.wexler@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1029","is_primary":true}]'::jsonb, 'Nurture', 'Google', '{}', '2026-04-15T09:00:00.000Z', '2026-07-25T13:00:00.000Z', '2026-08-05T10:00:00.000Z', 0, 26, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('6db41e0e-5093-4a0a-81fc-d33190872a13', 1030, 'Sofia', 'Marchetti', '[{"value":"sofia.marchetti@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1030","is_primary":true}]'::jsonb, 'Hot', 'Referral', '{}', '2026-04-14T09:00:00.000Z', '2026-08-10T14:00:00.000Z', '2026-08-03T10:00:00.000Z', 0, 85, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('161ebcb8-18d5-4bfa-a691-dd209802e9e7', 1031, 'Ty', 'Robinson', '[{"value":"ty.robinson@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1031","is_primary":true}]'::jsonb, 'Active Client', 'Open House', '{}', '2026-04-13T09:00:00.000Z', '2026-08-06T15:00:00.000Z', '2026-08-07T10:00:00.000Z', 0, 44, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('0ec4e713-c6b6-4e0c-9769-84fbfdb8849d', 1032, 'Hannah', 'Beaumont', '[{"value":"hannah.beaumont@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1032","is_primary":true}]'::jsonb, 'Past Client', 'Sphere', '{}', '2026-04-12T09:00:00.000Z', null, null, 10400, 33, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('acc097a2-349e-4d8c-a6f8-b7f9291b094a', 1033, 'Jamal', 'Ferris', '[{"value":"jamal.ferris@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1033","is_primary":true}]'::jsonb, 'New Lead', 'Meta', '{}', '2026-08-07T09:00:00.000Z', '2026-08-09T09:00:00.000Z', '2026-08-10T10:00:00.000Z', 0, 30, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('c278a7da-4366-4ec5-8d9b-c0841a79c162', 1034, 'Court', 'Nyland', '[{"value":"court.nyland@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1034","is_primary":true}]'::jsonb, 'Nurture', 'Ylopo', '{}', '2026-04-10T09:00:00.000Z', '2026-07-10T10:00:00.000Z', '2026-08-04T10:00:00.000Z', 0, 22, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('d2808d9e-89b3-4ddf-8c94-9edd57b5e5b2', 1035, 'Bianca', 'Loomis', '[{"value":"bianca.loomis@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1035","is_primary":true}]'::jsonb, 'Hot', 'YouTube', '{}', '2026-04-09T09:00:00.000Z', '2026-08-12T11:00:00.000Z', '2026-08-06T10:00:00.000Z', 0, 92, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('b1c52ad7-41b4-4837-94db-f5e44466baa3', 1036, 'Wes', 'Pryor', '[{"value":"wes.pryor@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1036","is_primary":true}]'::jsonb, 'Active Client', 'Referral', '{}', '2026-04-08T09:00:00.000Z', '2026-08-05T12:00:00.000Z', '2026-08-11T10:00:00.000Z', 0, 37, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('28b7ac79-3590-4637-ac02-167ed69c739a', 1037, 'Denise', 'Alcorn', '[{"value":"denise.alcorn@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1037","is_primary":true}]'::jsonb, 'New Lead', 'Google', '{}', '2026-08-10T09:00:00.000Z', '2026-08-10T13:00:00.000Z', '2026-08-11T10:00:00.000Z', 0, 41, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('a83c2f53-0a98-4d22-814f-407119090836', 1038, 'Rafael', 'Cordova', '[{"value":"rafael.cordova@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1038","is_primary":true}]'::jsonb, 'Nurture', 'Sphere', '{}', '2026-04-06T09:00:00.000Z', '2026-07-17T14:00:00.000Z', '2026-08-03T10:00:00.000Z', 0, 34, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('8cf123bc-5268-4e8d-a7f9-6817fa12b947', 1039, 'Kim', 'Stanhope', '[{"value":"kim.stanhope@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1039","is_primary":true}]'::jsonb, 'Past Client', 'Referral', '{}', '2026-04-05T09:00:00.000Z', null, null, 12900, 25, false, '2026-08-12T09:00:00.000Z') on conflict (fub_person_id) do nothing;

-- properties
insert into properties (id, mls_number, address_line1, city, state, zip, county, beds, baths, sqft, subdivision) values ('d03eaf80-8fbd-4ca0-ae8b-8d1f5bacacdb', 'MGM100234', '1234 Elm Street', 'Montgomery', 'AL', '36104', 'Montgomery', 4, 3, 2450, 'Cloverdale') on conflict (mls_number) do nothing;
insert into properties (id, mls_number, address_line1, city, state, zip, county, beds, baths, sqft, subdivision) values ('a79547de-66dd-440d-b9f0-6885fe6cd163', 'MGM100891', '88 Ryan Ridge', 'Pike Road', 'AL', '36064', 'Montgomery', 5, 4, 3200, 'The Waters') on conflict (mls_number) do nothing;
insert into properties (id, mls_number, address_line1, city, state, zip, county, beds, baths, sqft, subdivision) values ('4a982b5d-a1b2-4d2a-85c4-a56bc914bd5f', 'MGM101120', '701 Sturbridge Dr', 'Prattville', 'AL', '36066', 'Montgomery', 4, 3, 2780, 'Sturbridge') on conflict (mls_number) do nothing;
insert into properties (id, mls_number, address_line1, city, state, zip, county, beds, baths, sqft, subdivision) values ('8d0f0053-109e-4d09-bac6-17f103492ed1', 'MGM101455', '215 Halcyon Blvd', 'Montgomery', 'AL', '36117', 'Montgomery', 3, 2, 1850, 'Halcyon') on conflict (mls_number) do nothing;
insert into properties (id, mls_number, address_line1, city, state, zip, county, beds, baths, sqft, subdivision) values ('d9386305-d406-4d4f-9191-d6fa90d5bbb4', 'MGM101788', '3390 Wetumpka Hwy', 'Wetumpka', 'AL', '36092', 'Montgomery', 4, 3, 2600, 'Emerald Mountain') on conflict (mls_number) do nothing;
insert into properties (id, mls_number, address_line1, city, state, zip, county, beds, baths, sqft, subdivision) values ('2875dfd4-cff8-4965-9546-ccdd849f71f8', 'MGM102001', '42 Millbrook Lane', 'Millbrook', 'AL', '36054', 'Montgomery', 3, 2, 1720, 'Deer Creek') on conflict (mls_number) do nothing;
insert into properties (id, mls_number, address_line1, city, state, zip, county, beds, baths, sqft, subdivision) values ('8b6303be-e8bf-433d-9476-923ec5ae4bbe', 'MGM102310', '560 Wynlakes Blvd', 'Montgomery', 'AL', '36117', 'Montgomery', 5, 4, 3600, 'Wynlakes') on conflict (mls_number) do nothing;

-- deals
insert into deals (id, contact_id, property_id, side, status, contract_date, inspection_deadline, appraisal_deadline, financing_deadline, closing_date, sale_price, commission_rate, financing_type) values ('f1f4487c-aabf-4b7b-8151-366d4d625bfa', '0d4be804-1251-4b16-b3f5-8747c03c4d3a', 'd03eaf80-8fbd-4ca0-ae8b-8d1f5bacacdb', 'buyer', 'under_contract', '2026-08-09', '2026-08-16', '2026-08-24', '2026-09-01', '2026-09-08', 389000, 0.03, 'conventional');
insert into deals (id, contact_id, property_id, side, status, contract_date, inspection_deadline, appraisal_deadline, financing_deadline, closing_date, sale_price, commission_rate, financing_type) values ('2c6ee2b3-8a54-4f03-9f87-1ccb8b6fcb8d', '6021bd36-ae2a-4381-8408-f534e41102b7', '4a982b5d-a1b2-4d2a-85c4-a56bc914bd5f', 'buyer', 'inspection', '2026-08-03', '2026-08-13', '2026-08-20', '2026-08-28', '2026-09-03', 315000, 0.03, 'va');
insert into deals (id, contact_id, property_id, side, status, contract_date, inspection_deadline, appraisal_deadline, financing_deadline, closing_date, sale_price, commission_rate, financing_type) values ('eb4e4925-34bf-4fd6-8097-ee5f100abb77', '7ac2e4ec-b357-4c90-a45c-564d9b174cab', 'd9386305-d406-4d4f-9191-d6fa90d5bbb4', 'buyer', 'financing', '2026-07-22', '2026-07-29', '2026-08-06', '2026-08-14', '2026-08-18', 268000, 0.03, 'fha');
insert into deals (id, contact_id, property_id, side, status, contract_date, inspection_deadline, appraisal_deadline, financing_deadline, closing_date, sale_price, commission_rate, financing_type) values ('cb21642b-c1ee-4d84-9596-c84f6e287def', 'e80fd06b-4da8-4c52-a4e1-14d0673878c2', 'a79547de-66dd-440d-b9f0-6885fe6cd163', 'seller', 'active_listing', null, null, null, null, null, 545000, 0.03, null);
insert into deals (id, contact_id, property_id, side, status, contract_date, inspection_deadline, appraisal_deadline, financing_deadline, closing_date, sale_price, commission_rate, financing_type) values ('c6a97fe6-cbc7-4ab7-a80c-399e4d9890df', 'dd87d1ee-4d6b-4548-a4bb-52a33e1bc42e', '8d0f0053-109e-4d09-bac6-17f103492ed1', 'seller', 'under_contract', '2026-08-07', '2026-08-14', '2026-08-22', '2026-08-30', '2026-09-06', 289000, 0.03, 'conventional');
insert into deals (id, contact_id, property_id, side, status, contract_date, inspection_deadline, appraisal_deadline, financing_deadline, closing_date, sale_price, commission_rate, financing_type) values ('a85f8df0-5d6d-4a4d-9bd1-84da3a308334', 'eb829db3-5790-45b4-8b94-38f6a7fb2a86', '8b6303be-e8bf-433d-9476-923ec5ae4bbe', 'seller', 'active_listing', null, null, null, null, null, 615000, 0.03, null);
insert into deals (id, contact_id, property_id, side, status, contract_date, inspection_deadline, appraisal_deadline, financing_deadline, closing_date, sale_price, commission_rate, financing_type) values ('c60a96f9-f54f-418f-942f-a78e9cd2e8bd', '4c89f514-80cb-4f7e-9010-19babaeb2257', '2875dfd4-cff8-4965-9546-ccdd849f71f8', 'buyer', 'sold', '2026-07-03', '2026-07-10', '2026-07-18', '2026-07-25', '2026-07-31', 235000, 0.03, 'usda');

-- listings
insert into listings (id, deal_id, property_id, list_date, list_price, current_price, price_history, mls_status, showing_count_7d, showing_count_total, unread_feedback_count) values ('54be0036-d125-46a7-ac2e-de67928d7057', 'cb21642b-c1ee-4d84-9596-c84f6e287def', 'a79547de-66dd-440d-b9f0-6885fe6cd163', '2026-06-25', 559000, 545000, '[{"date":"2026-06-25","price":559000,"reason":"list"},{"date":"2026-07-25","price":545000,"reason":"reduction"}]'::jsonb, 'Active', 0, 14, 3);
insert into listings (id, deal_id, property_id, list_date, list_price, current_price, price_history, mls_status, showing_count_7d, showing_count_total, unread_feedback_count) values ('0f9325b8-8e60-44c5-97f7-9c81f6f48391', 'a85f8df0-5d6d-4a4d-9bd1-84da3a308334', '8b6303be-e8bf-433d-9476-923ec5ae4bbe', '2026-07-31', 615000, 615000, '[{"date":"2026-07-31","price":615000,"reason":"list"}]'::jsonb, 'Active', 5, 9, 1);
insert into listings (id, deal_id, property_id, list_date, list_price, current_price, price_history, mls_status, showing_count_7d, showing_count_total, unread_feedback_count) values ('ae80402b-4038-4302-b6f7-5a2722211c07', 'c6a97fe6-cbc7-4ab7-a80c-399e4d9890df', '8d0f0053-109e-4d09-bac6-17f103492ed1', '2026-06-13', 299000, 289000, '[{"date":"2026-06-13","price":299000,"reason":"list"},{"date":"2026-07-13","price":289000,"reason":"reduction"}]'::jsonb, 'Under Contract', 0, 22, 0);

-- tasks
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('17e46db1-6b84-4247-a145-424bfd9e6393', 'f1f4487c-aabf-4b7b-8151-366d4d625bfa', '0d4be804-1251-4b16-b3f5-8747c03c4d3a', 'Send executed contract to client and lender', null, '2026-08-09', 'contract', 0, false, 'done', 'high', false, '2026-08-11T09:00:00.000Z');
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('f234ec39-3aa7-4d58-929c-7e5305f18681', 'f1f4487c-aabf-4b7b-8151-366d4d625bfa', '0d4be804-1251-4b16-b3f5-8747c03c4d3a', 'Confirm earnest money delivered', null, '2026-08-10', 'contract', 1, false, 'open', 'high', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('1843cab9-fd1b-4449-947b-aaa9ad792f7f', 'f1f4487c-aabf-4b7b-8151-366d4d625bfa', '0d4be804-1251-4b16-b3f5-8747c03c4d3a', 'Order inspection', null, '2026-08-10', 'contract', 1, false, 'done', 'high', false, '2026-08-11T09:00:00.000Z');
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('58d06933-6184-495b-a5bb-c8419f9e59df', 'f1f4487c-aabf-4b7b-8151-366d4d625bfa', '0d4be804-1251-4b16-b3f5-8747c03c4d3a', 'Check inspection scheduled', null, '2026-08-12', 'contract', 3, false, 'open', 'normal', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('e33fed3b-6cbd-433a-9797-c3106af0b6f3', 'f1f4487c-aabf-4b7b-8151-366d4d625bfa', '0d4be804-1251-4b16-b3f5-8747c03c4d3a', 'Attend inspection', null, '2026-08-16', 'inspection', 0, false, 'open', 'high', true, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('a21b293c-6103-45dc-83f1-91a9d797976d', 'f1f4487c-aabf-4b7b-8151-366d4d625bfa', '0d4be804-1251-4b16-b3f5-8747c03c4d3a', 'Review inspection report with client', null, '2026-08-17', 'inspection', 1, false, 'open', 'high', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('a697032a-d1f7-4090-8498-8010f3faa00d', '2c6ee2b3-8a54-4f03-9f87-1ccb8b6fcb8d', '6021bd36-ae2a-4381-8408-f534e41102b7', 'Confirm appraisal ordered by correct assigned appraiser', null, '2026-08-11', 'contract', 3, false, 'open', 'high', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('7a45cfb4-64db-4ea9-8679-d7e8f199e2d9', '2c6ee2b3-8a54-4f03-9f87-1ccb8b6fcb8d', '6021bd36-ae2a-4381-8408-f534e41102b7', 'Attend inspection', null, '2026-08-13', 'inspection', 0, false, 'open', 'high', true, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('44554c5b-7aed-4676-90d9-155777f231b5', '2c6ee2b3-8a54-4f03-9f87-1ccb8b6fcb8d', '6021bd36-ae2a-4381-8408-f534e41102b7', 'Confirm termite / pest letter ordered', null, '2026-08-24', 'closing', -10, false, 'open', 'high', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('fa913acd-f741-4379-8f93-d54ba102d2d7', 'eb4e4925-34bf-4fd6-8097-ee5f100abb77', '7ac2e4ec-b357-4c90-a45c-564d9b174cab', 'Lender check-in, conditions cleared?', null, '2026-08-07', 'financing', -7, false, 'open', 'high', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('aa8dd8b6-eb43-4147-96d1-9bdc71e12293', 'eb4e4925-34bf-4fd6-8097-ee5f100abb77', '7ac2e4ec-b357-4c90-a45c-564d9b174cab', 'Confirm clear to close', null, '2026-08-14', 'financing', 0, false, 'open', 'high', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('50266a66-79cd-4852-ac88-65a2edcca0ec', 'eb4e4925-34bf-4fd6-8097-ee5f100abb77', '7ac2e4ec-b357-4c90-a45c-564d9b174cab', 'Send wire fraud warning to client', null, '2026-08-15', 'closing', -3, false, 'open', 'high', true, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('0580496b-03fa-4419-acb9-de87939946a7', 'eb4e4925-34bf-4fd6-8097-ee5f100abb77', '7ac2e4ec-b357-4c90-a45c-564d9b174cab', 'Schedule final walkthrough', null, '2026-08-16', 'closing', -2, false, 'open', 'high', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('c7d897ed-19f1-42b2-8ca5-2f156728acd7', 'eb4e4925-34bf-4fd6-8097-ee5f100abb77', '7ac2e4ec-b357-4c90-a45c-564d9b174cab', 'Final walkthrough', null, '2026-08-17', 'closing', -1, false, 'open', 'high', true, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('bea21e95-8226-4c93-9c9d-2bb3d81e4704', 'eb4e4925-34bf-4fd6-8097-ee5f100abb77', '7ac2e4ec-b357-4c90-a45c-564d9b174cab', 'Attend closing', null, '2026-08-18', 'closing', 0, true, 'open', 'high', true, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('f73b2211-7b77-4345-ae5b-de875181293d', 'c6a97fe6-cbc7-4ab7-a80c-399e4d9890df', 'dd87d1ee-4d6b-4548-a4bb-52a33e1bc42e', 'Confirm earnest money received', null, '2026-08-11', 'contract', 1, false, 'open', 'high', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('96f1bb21-a815-4869-88c0-291ba6d11413', 'c6a97fe6-cbc7-4ab7-a80c-399e4d9890df', 'dd87d1ee-4d6b-4548-a4bb-52a33e1bc42e', 'Prepare for inspection access', null, '2026-08-13', 'inspection', -1, false, 'open', 'normal', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('12acc146-c103-4c50-a8e0-8f52cc818d67', 'c6a97fe6-cbc7-4ab7-a80c-399e4d9890df', 'dd87d1ee-4d6b-4548-a4bb-52a33e1bc42e', 'Order payoff', null, '2026-08-30', 'closing', -7, false, 'open', 'high', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('1a073aac-65a8-4835-b556-cc223c100f64', 'cb21642b-c1ee-4d84-9596-c84f6e287def', 'e80fd06b-4da8-4c52-a4e1-14d0673878c2', 'Weekly seller update call', null, '2026-08-12', 'manual', null, false, 'open', 'normal', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('7addfcb3-88c3-4878-b604-b66832a37e81', 'cb21642b-c1ee-4d84-9596-c84f6e287def', 'e80fd06b-4da8-4c52-a4e1-14d0673878c2', 'Price and position review', null, '2026-08-14', 'manual', null, false, 'open', 'high', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('3951175d-5272-412c-816c-4ff854a35c85', 'a85f8df0-5d6d-4a4d-9bd1-84da3a308334', 'eb829db3-5790-45b4-8b94-38f6a7fb2a86', 'First seller update call', null, '2026-08-12', 'list_date', 7, false, 'open', 'high', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('3f495ca2-2ec1-47ac-aec4-515c7a4f1aef', null, '9a2d7959-c5b6-46e8-9396-3eccf7f335ff', 'Call back re: financing pre-approval', null, '2026-08-12', 'manual', null, false, 'open', 'high', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('5726578c-3080-49fe-b559-5e3a05fb3071', null, 'a56c6714-7033-40e2-981c-4a3277f93f75', 'Send Pike Road listings roundup', null, '2026-08-11', 'manual', null, false, 'open', 'normal', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('6b37f996-82b0-4a9d-a341-53b66984f355', null, '3a6da87c-0b03-48a8-ae87-6547525279d4', 'Schedule buyer consult', null, '2026-08-13', 'manual', null, false, 'open', 'normal', false, null);

-- appointments
insert into appointments (id, contact_id, property_id, deal_id, source, type, starts_at, ends_at, location, notes, status, feedback) values ('e0f4fc08-2320-45fe-b786-be0ea3bc93fa', '6021bd36-ae2a-4381-8408-f534e41102b7', '4a982b5d-a1b2-4d2a-85c4-a56bc914bd5f', '2c6ee2b3-8a54-4f03-9f87-1ccb8b6fcb8d', 'showingtime', 'showing', '2026-08-12T11:00:00.000Z', '2026-08-12T11:30:00.000Z', '701 Sturbridge Dr, Prattville', null, 'scheduled', null);
insert into appointments (id, contact_id, property_id, deal_id, source, type, starts_at, ends_at, location, notes, status, feedback) values ('6b7e562c-da1d-446d-9b32-72e528871f15', '3a6da87c-0b03-48a8-ae87-6547525279d4', null, null, 'calendly', 'buyer_consult', '2026-08-12T15:30:00.000Z', '2026-08-12T16:15:00.000Z', 'Zoom', 'Referral from Deshawn', 'scheduled', null);
insert into appointments (id, contact_id, property_id, deal_id, source, type, starts_at, ends_at, location, notes, status, feedback) values ('0d10b539-3ad9-424b-b135-69b2d98a17a2', '0d4be804-1251-4b16-b3f5-8747c03c4d3a', 'd03eaf80-8fbd-4ca0-ae8b-8d1f5bacacdb', 'f1f4487c-aabf-4b7b-8151-366d4d625bfa', 'manual', 'inspection', '2026-08-16T09:00:00.000Z', '2026-08-16T11:00:00.000Z', '1234 Elm Street', null, 'scheduled', null);

-- content_items
insert into content_items (id, title, pillar, format, status, target_publish_date, hook, notes, source_type, source_deal_id, source_contact_id) values ('4b59627d-e87e-4fab-a914-b542903bf048', 'Is Pike Road actually worth the price difference?', 'pros_cons', 'youtube_long', 'scripted', '2026-08-15', 'Everybody says Pike Road is ''worth it.'' Let''s actually run the numbers.', null, 'contact_question', null, 'a56c6714-7033-40e2-981c-4a3277f93f75');
insert into content_items (id, title, pillar, format, status, target_publish_date, hook, notes, source_type, source_deal_id, source_contact_id) values ('4b656c3d-51e2-4cd1-9810-824c7693d89e', '5 Cloverdale streets locals fight to live on', 'area_guides', 'reel', 'filmed', '2026-08-13', 'This one street in Cloverdale never hits the market.', null, 'manual', null, null);
insert into content_items (id, title, pillar, format, status, target_publish_date, hook, notes, source_type, source_deal_id, source_contact_id) values ('f1b381c4-7137-44ed-a9c6-4af1f0e0ba59', 'What $300k actually buys in Prattville right now', 'cost_of_living', 'reel', 'idea', '2026-08-16', 'Three houses, same price, wildly different.', null, 'manual', null, null);
insert into content_items (id, title, pillar, format, status, target_publish_date, hook, notes, source_type, source_deal_id, source_contact_id) values ('76fe8a48-d848-4f16-a130-87541f818dcd', 'August market update — rates, inventory, what it means', 'livestream', 'livestream', 'scheduled', '2026-08-14', 'Live Thursday: where the Montgomery market actually is.', null, 'manual', null, null);
insert into content_items (id, title, pillar, format, status, target_publish_date, hook, notes, source_type, source_deal_id, source_contact_id) values ('5d416742-3dbe-4edc-a20f-a14de8e59425', 'The truth nobody tells you about buying new construction', 'gut_check', 'youtube_long', 'idea', null, 'Builders don''t want you to know this one thing.', null, 'manual', null, null);
insert into content_items (id, title, pillar, format, status, target_publish_date, hook, notes, source_type, source_deal_id, source_contact_id) values ('5ba2b473-e7e8-4474-9cc8-40410a577e84', 'Weekly email — 3 new listings under $350k', 'area_guides', 'email', 'idea', '2026-08-13', null, null, 'manual', null, null);
insert into content_items (id, title, pillar, format, status, target_publish_date, hook, notes, source_type, source_deal_id, source_contact_id) values ('ee81860c-4b56-4e51-86fb-91becf3ba455', 'Wetumpka vs Millbrook: which fits your family?', 'pros_cons', 'carousel', 'editing', '2026-08-12', null, null, 'manual', null, null);
insert into content_items (id, title, pillar, format, status, target_publish_date, hook, notes, source_type, source_deal_id, source_contact_id) values ('f4b1f448-9a4d-4ad9-998e-3377068f0508', 'Property taxes in Montgomery County, explained', 'cost_of_living', 'blog', 'published', '2026-08-06', null, null, 'manual', null, null);
insert into content_items (id, title, pillar, format, status, target_publish_date, hook, notes, source_type, source_deal_id, source_contact_id) values ('8ba2492c-56ef-4178-94f9-aaab3478fef6', 'Why I stopped recommending this popular subdivision', 'gut_check', 'reel', 'idea', null, 'I used to send everyone here. Not anymore.', null, 'manual', null, null);
insert into content_items (id, title, pillar, format, status, target_publish_date, hook, notes, source_type, source_deal_id, source_contact_id) values ('665acb03-ead9-465e-af21-44194363af4f', 'Emerald Mountain area guide', 'area_guides', 'youtube_long', 'published', '2026-07-31', null, null, 'manual', null, null);
insert into content_items (id, title, pillar, format, status, target_publish_date, hook, notes, source_type, source_deal_id, source_contact_id) values ('5ce47fbb-71dd-4a16-b3e6-794757a0c17c', 'Should you buy before you sell? A gut check', 'gut_check', 'reel', 'scripted', '2026-08-17', null, null, 'manual', null, null);
insert into content_items (id, title, pillar, format, status, target_publish_date, hook, notes, source_type, source_deal_id, source_contact_id) values ('7e03e333-87ed-4eb9-a9b3-95e311408b7a', 'Live Q&A: first-time buyer questions', 'livestream', 'livestream', 'published', '2026-08-03', null, null, 'manual', null, null);

commit;
