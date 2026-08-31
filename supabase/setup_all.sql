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
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('e0bdfff9-7a46-45de-a4c2-db43d459c5b0', 1000, 'Marcus', 'Bell', '[{"value":"marcus.bell@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1000","is_primary":true}]'::jsonb, 'Hot', 'Referral', '{}', '2026-06-02T09:00:00.000Z', '2026-08-31T08:00:00.000Z', '2026-08-28T10:00:00.000Z', 0, 86, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('5347f3fa-cf99-4290-ab00-69f67802cf67', 1001, 'Dana', 'Whitfield', '[{"value":"dana.whitfield@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1001","is_primary":true}]'::jsonb, 'Hot', 'YouTube', '{}', '2026-06-01T09:00:00.000Z', '2026-08-31T09:00:00.000Z', '2026-08-26T10:00:00.000Z', 0, 88, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('b4809110-89e1-4642-9664-d05101040e3d', 1002, 'Priya', 'Nair', '[{"value":"priya.nair@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1002","is_primary":true}]'::jsonb, 'Active Client', 'Sphere', '{}', '2026-05-31T09:00:00.000Z', '2026-08-30T10:00:00.000Z', '2026-08-27T10:00:00.000Z', 0, 82, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('62c42036-85cc-4217-9260-7ceb7b96c3b7', 1003, 'Travis', 'Boone', '[{"value":"travis.boone@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1003","is_primary":true}]'::jsonb, 'Hot', 'Open House', '{}', '2026-05-30T09:00:00.000Z', '2026-08-29T11:00:00.000Z', '2026-08-21T10:00:00.000Z', 0, 80, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('9826c07a-a0d6-4e57-b87f-b9845c89e789', 1004, 'Latoya', 'Simmons', '[{"value":"latoya.simmons@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1004","is_primary":true}]'::jsonb, 'Active Client', 'Referral', '{}', '2026-05-29T09:00:00.000Z', '2026-08-28T12:00:00.000Z', '2026-08-28T10:00:00.000Z', 0, 67, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('7a969a52-9548-4e55-a233-fa59d2548aba', 1005, 'Grant', 'Holloway', '[{"value":"grant.holloway@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1005","is_primary":true}]'::jsonb, 'Nurture', 'Ylopo', '{}', '2026-05-28T09:00:00.000Z', '2026-08-25T13:00:00.000Z', '2026-08-29T10:00:00.000Z', 0, 35, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('bb6a2782-a781-4bd6-9a70-71020ba0e85e', 1006, 'Bethany', 'Cruz', '[{"value":"bethany.cruz@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1006","is_primary":true}]'::jsonb, 'New Lead', 'Meta', '{}', '2026-08-25T09:00:00.000Z', '2026-08-29T14:00:00.000Z', '2026-08-30T10:00:00.000Z', 0, 37, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('de462e69-c783-46a6-83e2-3828b9bd1eec', 1007, 'Sean', 'Delacroix', '[{"value":"sean.delacroix@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1007","is_primary":true}]'::jsonb, 'Hot', 'Referral', '{}', '2026-05-26T09:00:00.000Z', null, null, 0, 44, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('5db8e44f-6cc0-4dcc-b569-8d039a923c25', 1008, 'Imani', 'Rhodes', '[{"value":"imani.rhodes@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1008","is_primary":true}]'::jsonb, 'Active Client', 'Sphere', '{}', '2026-05-25T09:00:00.000Z', '2026-08-22T08:00:00.000Z', '2026-08-17T10:00:00.000Z', 0, 58, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('6e7a5d88-b496-4c88-a418-52aba100cdf2', 1009, 'Colton', 'Reyes', '[{"value":"colton.reyes@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1009","is_primary":true}]'::jsonb, 'New Lead', 'Google', '{}', '2026-08-29T09:00:00.000Z', '2026-08-30T09:00:00.000Z', '2026-08-29T10:00:00.000Z', 0, 63, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('37a3baae-2a8c-417e-891a-5656abb5a6d4', 1010, 'Renee', 'Abbott', '[{"value":"renee.abbott@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1010","is_primary":true}]'::jsonb, 'Nurture', 'YouTube', '{}', '2026-05-23T09:00:00.000Z', '2026-08-19T10:00:00.000Z', '2026-08-28T10:00:00.000Z', 0, 29, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('0ab6d1cb-e829-4807-b1cc-09f8c466c85f', 1011, 'Deshawn', 'Pope', '[{"value":"deshawn.pope@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1011","is_primary":true}]'::jsonb, 'Past Client', 'Referral', '{}', '2026-05-22T09:00:00.000Z', null, null, 9600, 33, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('5fbd90c4-af93-4635-be23-bd52df4ef4dd', 1012, 'Kaylee', 'Monroe', '[{"value":"kaylee.monroe@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1012","is_primary":true}]'::jsonb, 'Hot', 'Open House', '{}', '2026-05-21T09:00:00.000Z', '2026-08-31T12:00:00.000Z', '2026-08-23T10:00:00.000Z', 0, 81, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('f703d736-483c-4968-b3fe-c1dad0613384', 1013, 'Victor', 'Ianelli', '[{"value":"victor.ianelli@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1013","is_primary":true}]'::jsonb, 'Active Client', 'Ylopo', '{}', '2026-05-20T09:00:00.000Z', '2026-08-27T13:00:00.000Z', '2026-08-30T10:00:00.000Z', 0, 41, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('9f6b0ae0-7f6d-4ffc-b8e6-5c33327d39ad', 1014, 'Nadia', 'Frost', '[{"value":"nadia.frost@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1014","is_primary":true}]'::jsonb, 'New Lead', 'Meta', '{}', '2026-08-31T09:00:00.000Z', '2026-08-29T14:00:00.000Z', null, 0, 67, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('0f115d7b-847e-4b32-8804-953b06bcc64e', 1015, 'Bryce', 'Calloway', '[{"value":"bryce.calloway@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1015","is_primary":true}]'::jsonb, 'Nurture', 'Google', '{}', '2026-05-18T09:00:00.000Z', '2026-07-22T15:00:00.000Z', '2026-08-27T10:00:00.000Z', 0, 19, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('86939bd5-5090-407f-a8f8-dab50e179802', 1016, 'Selena', 'Ortega', '[{"value":"selena.ortega@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1016","is_primary":true}]'::jsonb, 'Hot', 'Referral', '{}', '2026-05-17T09:00:00.000Z', '2026-08-31T08:00:00.000Z', '2026-08-30T10:00:00.000Z', 0, 86, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('a4973ef8-4828-4904-ae53-224c57242f22', 1017, 'Omar', 'Haddad', '[{"value":"omar.haddad@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1017","is_primary":true}]'::jsonb, 'Active Client', 'Sphere', '{}', '2026-05-16T09:00:00.000Z', '2026-08-26T09:00:00.000Z', '2026-08-25T10:00:00.000Z', 0, 71, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('4c6154c3-d4dd-4e84-9e02-6d64f2ff1fa4', 1018, 'Kelsey', 'Vance', '[{"value":"kelsey.vance@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1018","is_primary":true}]'::jsonb, 'Past Client', 'Sphere', '{}', '2026-05-15T09:00:00.000Z', null, null, 11200, 25, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('3d099dd0-4064-49a3-847f-b72aa3d56c82', 1019, 'Trent', 'Buford', '[{"value":"trent.buford@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1019","is_primary":true}]'::jsonb, 'New Lead', 'Ylopo', '{}', '2026-08-26T09:00:00.000Z', '2026-08-30T11:00:00.000Z', '2026-08-31T10:00:00.000Z', 0, 41, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('0e4c6135-d50e-4e12-bb15-1eb7c3e8c635', 1020, 'Alicia', 'Kwan', '[{"value":"alicia.kwan@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1020","is_primary":true}]'::jsonb, 'Nurture', 'YouTube', '{}', '2026-05-13T09:00:00.000Z', '2026-08-16T12:00:00.000Z', '2026-08-26T10:00:00.000Z', 0, 33, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('2f4a2692-e0b8-47d6-88c5-c19f43ca9d74', 1021, 'Gabe', 'Sutter', '[{"value":"gabe.sutter@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1021","is_primary":true}]'::jsonb, 'Hot', 'Open House', '{}', '2026-05-12T09:00:00.000Z', '2026-08-28T13:00:00.000Z', '2026-08-19T10:00:00.000Z', 0, 69, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('fe6cfd14-1674-4886-88ce-82dadcbd04fa', 1022, 'Monique', 'Dill', '[{"value":"monique.dill@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1022","is_primary":true}]'::jsonb, 'Active Client', 'Referral', '{}', '2026-05-11T09:00:00.000Z', '2026-08-23T14:00:00.000Z', '2026-08-29T10:00:00.000Z', 0, 41, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('23a3782c-6401-4a53-8bfb-53061086a878', 1023, 'Parker', 'Ellison', '[{"value":"parker.ellison@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1023","is_primary":true}]'::jsonb, 'New Lead', 'Google', '{}', '2026-08-29T09:00:00.000Z', '2026-08-31T15:00:00.000Z', '2026-08-31T10:00:00.000Z', 0, 76, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('9e3c52d8-13a6-44f0-b20c-cb7128b91b9b', 1024, 'Rosa', 'Benitez', '[{"value":"rosa.benitez@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1024","is_primary":true}]'::jsonb, 'Nurture', 'Meta', '{}', '2026-05-09T09:00:00.000Z', '2026-08-09T08:00:00.000Z', '2026-08-25T10:00:00.000Z', 0, 19, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('b110a036-a30c-46ad-8132-7cbdee12eb76', 1025, 'Chad', 'Mercer', '[{"value":"chad.mercer@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1025","is_primary":true}]'::jsonb, 'Past Client', 'Referral', '{}', '2026-05-08T09:00:00.000Z', null, null, 8700, 29, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('33874c04-e2a0-4201-b1b3-2f53bf375e74', 1026, 'Yasmin', 'Attah', '[{"value":"yasmin.attah@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1026","is_primary":true}]'::jsonb, 'Hot', 'Sphere', '{}', '2026-05-07T09:00:00.000Z', '2026-08-31T10:00:00.000Z', '2026-08-29T10:00:00.000Z', 0, 94, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('02fa72f4-e70c-442d-96c2-cec6b92472eb', 1027, 'Blake', 'Fontaine', '[{"value":"blake.fontaine@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1027","is_primary":true}]'::jsonb, 'Active Client', 'Ylopo', '{}', '2026-05-06T09:00:00.000Z', '2026-08-20T11:00:00.000Z', '2026-08-28T10:00:00.000Z', 0, 29, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('55f6b7a7-cb4c-4c5b-b127-a9eae7a9c5d8', 1028, 'Erin', 'Gallagher', '[{"value":"erin.gallagher@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1028","is_primary":true}]'::jsonb, 'New Lead', 'YouTube', '{}', '2026-08-31T09:00:00.000Z', '2026-08-30T12:00:00.000Z', '2026-08-31T10:00:00.000Z', 0, 47, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('8375efe1-3cf6-4151-8137-0e195944e879', 1029, 'Damon', 'Wexler', '[{"value":"damon.wexler@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1029","is_primary":true}]'::jsonb, 'Nurture', 'Google', '{}', '2026-05-04T09:00:00.000Z', '2026-08-13T13:00:00.000Z', '2026-08-24T10:00:00.000Z', 0, 26, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('45209b7e-9ea6-4de9-bc52-58864bf41867', 1030, 'Sofia', 'Marchetti', '[{"value":"sofia.marchetti@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1030","is_primary":true}]'::jsonb, 'Hot', 'Referral', '{}', '2026-05-03T09:00:00.000Z', '2026-08-29T14:00:00.000Z', '2026-08-22T10:00:00.000Z', 0, 85, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('f7803cec-0dd0-4080-8bfd-7d41c9f204c9', 1031, 'Ty', 'Robinson', '[{"value":"ty.robinson@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1031","is_primary":true}]'::jsonb, 'Active Client', 'Open House', '{}', '2026-05-02T09:00:00.000Z', '2026-08-25T15:00:00.000Z', '2026-08-26T10:00:00.000Z', 0, 44, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('209406b6-527b-4a7b-acc6-452b6166e348', 1032, 'Hannah', 'Beaumont', '[{"value":"hannah.beaumont@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1032","is_primary":true}]'::jsonb, 'Past Client', 'Sphere', '{}', '2026-05-01T09:00:00.000Z', null, null, 10400, 33, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('81a9a105-9d03-4c06-bc38-97667b056ced', 1033, 'Jamal', 'Ferris', '[{"value":"jamal.ferris@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1033","is_primary":true}]'::jsonb, 'New Lead', 'Meta', '{}', '2026-08-26T09:00:00.000Z', '2026-08-28T09:00:00.000Z', '2026-08-29T10:00:00.000Z', 0, 30, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('033300ff-e8a5-4194-8d31-214e12f89dc5', 1034, 'Court', 'Nyland', '[{"value":"court.nyland@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1034","is_primary":true}]'::jsonb, 'Nurture', 'Ylopo', '{}', '2026-04-29T09:00:00.000Z', '2026-07-29T10:00:00.000Z', '2026-08-23T10:00:00.000Z', 0, 22, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('07a38d65-97ad-472e-9277-d39ebea9d4df', 1035, 'Bianca', 'Loomis', '[{"value":"bianca.loomis@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1035","is_primary":true}]'::jsonb, 'Hot', 'YouTube', '{}', '2026-04-28T09:00:00.000Z', '2026-08-31T11:00:00.000Z', '2026-08-25T10:00:00.000Z', 0, 92, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('314460bb-a190-4142-9466-5bc257f3ef24', 1036, 'Wes', 'Pryor', '[{"value":"wes.pryor@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1036","is_primary":true}]'::jsonb, 'Active Client', 'Referral', '{}', '2026-04-27T09:00:00.000Z', '2026-08-24T12:00:00.000Z', '2026-08-30T10:00:00.000Z', 0, 37, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('05e035d7-b83c-4e9b-80c3-864760445bb5', 1037, 'Denise', 'Alcorn', '[{"value":"denise.alcorn@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1037","is_primary":true}]'::jsonb, 'New Lead', 'Google', '{}', '2026-08-29T09:00:00.000Z', '2026-08-29T13:00:00.000Z', '2026-08-30T10:00:00.000Z', 0, 41, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('39c9e482-7fb6-4837-8b07-37b76d49a0ae', 1038, 'Rafael', 'Cordova', '[{"value":"rafael.cordova@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1038","is_primary":true}]'::jsonb, 'Nurture', 'Sphere', '{}', '2026-04-25T09:00:00.000Z', '2026-08-05T14:00:00.000Z', '2026-08-22T10:00:00.000Z', 0, 34, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;
insert into contacts (id, fub_person_id, first_name, last_name, emails, phones, stage, source, tags, fub_created_at, last_inbound_at, last_outbound_at, lifetime_value, lead_score, is_archived, synced_at) values ('7be9995a-7dbe-47a0-8c15-db5bfe7d385d', 1039, 'Kim', 'Stanhope', '[{"value":"kim.stanhope@example.com","is_primary":true}]'::jsonb, '[{"value":"334-555-1039","is_primary":true}]'::jsonb, 'Past Client', 'Referral', '{}', '2026-04-24T09:00:00.000Z', null, null, 12900, 25, false, '2026-08-31T09:00:00.000Z') on conflict (fub_person_id) do nothing;

-- properties
insert into properties (id, mls_number, address_line1, city, state, zip, county, beds, baths, sqft, subdivision) values ('d1eb4cad-5692-4b8d-ac6f-b759e6604dc3', 'MGM100234', '1234 Elm Street', 'Montgomery', 'AL', '36104', 'Montgomery', 4, 3, 2450, 'Cloverdale') on conflict (mls_number) do nothing;
insert into properties (id, mls_number, address_line1, city, state, zip, county, beds, baths, sqft, subdivision) values ('093308c4-1af5-45d3-af05-427ee84ba54e', 'MGM100891', '88 Ryan Ridge', 'Pike Road', 'AL', '36064', 'Montgomery', 5, 4, 3200, 'The Waters') on conflict (mls_number) do nothing;
insert into properties (id, mls_number, address_line1, city, state, zip, county, beds, baths, sqft, subdivision) values ('fb2896a6-31f1-40d7-9b79-f1c6d67d6760', 'MGM101120', '701 Sturbridge Dr', 'Prattville', 'AL', '36066', 'Montgomery', 4, 3, 2780, 'Sturbridge') on conflict (mls_number) do nothing;
insert into properties (id, mls_number, address_line1, city, state, zip, county, beds, baths, sqft, subdivision) values ('443de737-7d4b-4a55-9e02-23b1526c14e3', 'MGM101455', '215 Halcyon Blvd', 'Montgomery', 'AL', '36117', 'Montgomery', 3, 2, 1850, 'Halcyon') on conflict (mls_number) do nothing;
insert into properties (id, mls_number, address_line1, city, state, zip, county, beds, baths, sqft, subdivision) values ('8562e09b-8757-4175-97b1-ef77ac69620e', 'MGM101788', '3390 Wetumpka Hwy', 'Wetumpka', 'AL', '36092', 'Montgomery', 4, 3, 2600, 'Emerald Mountain') on conflict (mls_number) do nothing;
insert into properties (id, mls_number, address_line1, city, state, zip, county, beds, baths, sqft, subdivision) values ('c8cf7630-c468-487e-aa61-1b1071f2c60a', 'MGM102001', '42 Millbrook Lane', 'Millbrook', 'AL', '36054', 'Montgomery', 3, 2, 1720, 'Deer Creek') on conflict (mls_number) do nothing;
insert into properties (id, mls_number, address_line1, city, state, zip, county, beds, baths, sqft, subdivision) values ('025e22f8-1e39-469f-9e51-e30d79fbe5b1', 'MGM102310', '560 Wynlakes Blvd', 'Montgomery', 'AL', '36117', 'Montgomery', 5, 4, 3600, 'Wynlakes') on conflict (mls_number) do nothing;

-- deals
insert into deals (id, contact_id, property_id, side, status, contract_date, inspection_deadline, appraisal_deadline, financing_deadline, closing_date, sale_price, commission_rate, financing_type) values ('0298c850-6e7d-4dfc-8b0a-ceda766c91a2', 'e0bdfff9-7a46-45de-a4c2-db43d459c5b0', 'd1eb4cad-5692-4b8d-ac6f-b759e6604dc3', 'buyer', 'under_contract', '2026-08-28', '2026-09-04', '2026-09-12', '2026-09-20', '2026-09-27', 389000, 0.03, 'conventional');
insert into deals (id, contact_id, property_id, side, status, contract_date, inspection_deadline, appraisal_deadline, financing_deadline, closing_date, sale_price, commission_rate, financing_type) values ('2be1e497-5693-48da-b353-d18b541f307c', '9826c07a-a0d6-4e57-b87f-b9845c89e789', 'fb2896a6-31f1-40d7-9b79-f1c6d67d6760', 'buyer', 'inspection', '2026-08-22', '2026-09-01', '2026-09-08', '2026-09-16', '2026-09-22', 315000, 0.03, 'va');
insert into deals (id, contact_id, property_id, side, status, contract_date, inspection_deadline, appraisal_deadline, financing_deadline, closing_date, sale_price, commission_rate, financing_type) values ('6d7f3a3e-3fc4-4704-a199-6dbdbf8df8e0', 'b4809110-89e1-4642-9664-d05101040e3d', '8562e09b-8757-4175-97b1-ef77ac69620e', 'buyer', 'financing', '2026-08-10', '2026-08-17', '2026-08-25', '2026-09-02', '2026-09-06', 268000, 0.03, 'fha');
insert into deals (id, contact_id, property_id, side, status, contract_date, inspection_deadline, appraisal_deadline, financing_deadline, closing_date, sale_price, commission_rate, financing_type) values ('eb92e591-498c-4fde-ac49-4a1ec8f4ca33', '5db8e44f-6cc0-4dcc-b569-8d039a923c25', '093308c4-1af5-45d3-af05-427ee84ba54e', 'seller', 'active_listing', null, null, null, null, null, 545000, 0.03, null);
insert into deals (id, contact_id, property_id, side, status, contract_date, inspection_deadline, appraisal_deadline, financing_deadline, closing_date, sale_price, commission_rate, financing_type) values ('68858e69-7ac0-4bc2-a36d-8fc650026296', 'a4973ef8-4828-4904-ae53-224c57242f22', '443de737-7d4b-4a55-9e02-23b1526c14e3', 'seller', 'under_contract', '2026-08-26', '2026-09-02', '2026-09-10', '2026-09-18', '2026-09-25', 289000, 0.03, 'conventional');
insert into deals (id, contact_id, property_id, side, status, contract_date, inspection_deadline, appraisal_deadline, financing_deadline, closing_date, sale_price, commission_rate, financing_type) values ('63885d99-0b98-41a1-88f6-0a8eee3e4bdd', 'f703d736-483c-4968-b3fe-c1dad0613384', '025e22f8-1e39-469f-9e51-e30d79fbe5b1', 'seller', 'active_listing', null, null, null, null, null, 615000, 0.03, null);
insert into deals (id, contact_id, property_id, side, status, contract_date, inspection_deadline, appraisal_deadline, financing_deadline, closing_date, sale_price, commission_rate, financing_type) values ('5092cdbb-82a3-418e-b0c7-52ed1f526424', '4c6154c3-d4dd-4e84-9e02-6d64f2ff1fa4', 'c8cf7630-c468-487e-aa61-1b1071f2c60a', 'buyer', 'sold', '2026-07-22', '2026-07-29', '2026-08-06', '2026-08-13', '2026-08-19', 235000, 0.03, 'usda');

-- listings
insert into listings (id, deal_id, property_id, list_date, list_price, current_price, price_history, mls_status, showing_count_7d, showing_count_total, unread_feedback_count) values ('806db712-80c9-446e-84c0-bd01b58afc9f', 'eb92e591-498c-4fde-ac49-4a1ec8f4ca33', '093308c4-1af5-45d3-af05-427ee84ba54e', '2026-07-14', 559000, 545000, '[{"date":"2026-07-14","price":559000,"reason":"list"},{"date":"2026-08-13","price":545000,"reason":"reduction"}]'::jsonb, 'Active', 0, 14, 3);
insert into listings (id, deal_id, property_id, list_date, list_price, current_price, price_history, mls_status, showing_count_7d, showing_count_total, unread_feedback_count) values ('3523fa73-4e52-4c16-ad29-12b95cc34ac8', '63885d99-0b98-41a1-88f6-0a8eee3e4bdd', '025e22f8-1e39-469f-9e51-e30d79fbe5b1', '2026-08-19', 615000, 615000, '[{"date":"2026-08-19","price":615000,"reason":"list"}]'::jsonb, 'Active', 5, 9, 1);
insert into listings (id, deal_id, property_id, list_date, list_price, current_price, price_history, mls_status, showing_count_7d, showing_count_total, unread_feedback_count) values ('5ad2031c-a0b1-4218-bc9b-204d23a02829', '68858e69-7ac0-4bc2-a36d-8fc650026296', '443de737-7d4b-4a55-9e02-23b1526c14e3', '2026-07-02', 299000, 289000, '[{"date":"2026-07-02","price":299000,"reason":"list"},{"date":"2026-08-01","price":289000,"reason":"reduction"}]'::jsonb, 'Under Contract', 0, 22, 0);

-- tasks
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('7cac81e1-e197-45f1-bd5c-51ae7816653d', '0298c850-6e7d-4dfc-8b0a-ceda766c91a2', 'e0bdfff9-7a46-45de-a4c2-db43d459c5b0', 'Send executed contract to client and lender', null, '2026-08-28', 'contract', 0, false, 'done', 'high', false, '2026-08-30T09:00:00.000Z');
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('0641420c-bbb3-47f7-9a22-bbe4b137e86c', '0298c850-6e7d-4dfc-8b0a-ceda766c91a2', 'e0bdfff9-7a46-45de-a4c2-db43d459c5b0', 'Confirm earnest money delivered', null, '2026-08-29', 'contract', 1, false, 'open', 'high', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('7d2ebf08-c627-4306-8338-b8833cc01b9c', '0298c850-6e7d-4dfc-8b0a-ceda766c91a2', 'e0bdfff9-7a46-45de-a4c2-db43d459c5b0', 'Order inspection', null, '2026-08-29', 'contract', 1, false, 'done', 'high', false, '2026-08-30T09:00:00.000Z');
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('44c66aac-0429-490d-9977-26e520954229', '0298c850-6e7d-4dfc-8b0a-ceda766c91a2', 'e0bdfff9-7a46-45de-a4c2-db43d459c5b0', 'Check inspection scheduled', null, '2026-08-31', 'contract', 3, false, 'open', 'normal', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('91055efb-7555-443e-9afc-eabadb3ef206', '0298c850-6e7d-4dfc-8b0a-ceda766c91a2', 'e0bdfff9-7a46-45de-a4c2-db43d459c5b0', 'Attend inspection', null, '2026-09-04', 'inspection', 0, false, 'open', 'high', true, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('6ca1a1bd-77c1-4a6e-b2ad-f7c4e85da692', '0298c850-6e7d-4dfc-8b0a-ceda766c91a2', 'e0bdfff9-7a46-45de-a4c2-db43d459c5b0', 'Review inspection report with client', null, '2026-09-05', 'inspection', 1, false, 'open', 'high', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('5da14323-2466-451a-92fa-5e623bf63663', '2be1e497-5693-48da-b353-d18b541f307c', '9826c07a-a0d6-4e57-b87f-b9845c89e789', 'Confirm appraisal ordered by correct assigned appraiser', null, '2026-08-30', 'contract', 3, false, 'open', 'high', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('589e27e0-3141-4569-be42-d207b5499ca5', '2be1e497-5693-48da-b353-d18b541f307c', '9826c07a-a0d6-4e57-b87f-b9845c89e789', 'Attend inspection', null, '2026-09-01', 'inspection', 0, false, 'open', 'high', true, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('61ecd643-f8f7-47d2-b774-1581e64ee1df', '2be1e497-5693-48da-b353-d18b541f307c', '9826c07a-a0d6-4e57-b87f-b9845c89e789', 'Confirm termite / pest letter ordered', null, '2026-09-12', 'closing', -10, false, 'open', 'high', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('37fb43cc-e321-46a1-a61d-b58fb9ccad9d', '6d7f3a3e-3fc4-4704-a199-6dbdbf8df8e0', 'b4809110-89e1-4642-9664-d05101040e3d', 'Lender check-in, conditions cleared?', null, '2026-08-26', 'financing', -7, false, 'open', 'high', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('95cb2613-07ec-42ac-bfb5-178a75d9567b', '6d7f3a3e-3fc4-4704-a199-6dbdbf8df8e0', 'b4809110-89e1-4642-9664-d05101040e3d', 'Confirm clear to close', null, '2026-09-02', 'financing', 0, false, 'open', 'high', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('d5db5418-54cc-4801-bfaf-0383d8b45c45', '6d7f3a3e-3fc4-4704-a199-6dbdbf8df8e0', 'b4809110-89e1-4642-9664-d05101040e3d', 'Send wire fraud warning to client', null, '2026-09-03', 'closing', -3, false, 'open', 'high', true, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('9e6a3b2c-0694-4eea-bc36-b6e95cf8f773', '6d7f3a3e-3fc4-4704-a199-6dbdbf8df8e0', 'b4809110-89e1-4642-9664-d05101040e3d', 'Schedule final walkthrough', null, '2026-09-04', 'closing', -2, false, 'open', 'high', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('40a06330-d232-4f53-aac7-cd24ad57c4f7', '6d7f3a3e-3fc4-4704-a199-6dbdbf8df8e0', 'b4809110-89e1-4642-9664-d05101040e3d', 'Final walkthrough', null, '2026-09-05', 'closing', -1, false, 'open', 'high', true, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('0343acdd-2c14-457e-8198-de3ee518f92f', '6d7f3a3e-3fc4-4704-a199-6dbdbf8df8e0', 'b4809110-89e1-4642-9664-d05101040e3d', 'Attend closing', null, '2026-09-06', 'closing', 0, true, 'open', 'high', true, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('60bc03f4-8d62-4b61-b3e5-a7b1315cccbe', '68858e69-7ac0-4bc2-a36d-8fc650026296', 'a4973ef8-4828-4904-ae53-224c57242f22', 'Confirm earnest money received', null, '2026-08-30', 'contract', 1, false, 'open', 'high', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('a7cd2a0b-76b8-4fe1-bf59-08655679c1c8', '68858e69-7ac0-4bc2-a36d-8fc650026296', 'a4973ef8-4828-4904-ae53-224c57242f22', 'Prepare for inspection access', null, '2026-09-01', 'inspection', -1, false, 'open', 'normal', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('c760d590-132a-4193-8fdd-b00741f33ff1', '68858e69-7ac0-4bc2-a36d-8fc650026296', 'a4973ef8-4828-4904-ae53-224c57242f22', 'Order payoff', null, '2026-09-18', 'closing', -7, false, 'open', 'high', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('1373191f-95cb-49ae-a2cc-a2f59227e90a', 'eb92e591-498c-4fde-ac49-4a1ec8f4ca33', '5db8e44f-6cc0-4dcc-b569-8d039a923c25', 'Weekly seller update call', null, '2026-08-31', 'manual', null, false, 'open', 'normal', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('43081a29-5ab8-42d3-96a1-415c2e420451', 'eb92e591-498c-4fde-ac49-4a1ec8f4ca33', '5db8e44f-6cc0-4dcc-b569-8d039a923c25', 'Price and position review', null, '2026-09-02', 'manual', null, false, 'open', 'high', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('e1b07d58-1044-4def-8c70-9048c515770a', '63885d99-0b98-41a1-88f6-0a8eee3e4bdd', 'f703d736-483c-4968-b3fe-c1dad0613384', 'First seller update call', null, '2026-08-31', 'list_date', 7, false, 'open', 'high', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('247018fc-19a8-41aa-97c2-05aa0cb9f851', null, 'de462e69-c783-46a6-83e2-3828b9bd1eec', 'Call back re: financing pre-approval', null, '2026-08-31', 'manual', null, false, 'open', 'high', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('37cf8ea1-8e57-41ca-a406-cf03a9ddfed3', null, '5fbd90c4-af93-4635-be23-bd52df4ef4dd', 'Send Pike Road listings roundup', null, '2026-08-30', 'manual', null, false, 'open', 'normal', false, null);
insert into tasks (id, deal_id, contact_id, title, description, due_date, anchor_type, anchor_offset_days, is_pinned, status, priority, is_client_visible, completed_at) values ('b957fb5e-5485-4335-934b-ede821008edb', null, '86939bd5-5090-407f-a8f8-dab50e179802', 'Schedule buyer consult', null, '2026-09-01', 'manual', null, false, 'open', 'normal', false, null);

-- appointments
insert into appointments (id, contact_id, property_id, deal_id, source, type, starts_at, ends_at, location, notes, status, feedback) values ('9963d56d-d11c-4be7-9d4b-001342407a60', '9826c07a-a0d6-4e57-b87f-b9845c89e789', 'fb2896a6-31f1-40d7-9b79-f1c6d67d6760', '2be1e497-5693-48da-b353-d18b541f307c', 'showingtime', 'showing', '2026-08-31T11:00:00.000Z', '2026-08-31T11:30:00.000Z', '701 Sturbridge Dr, Prattville', null, 'scheduled', null);
insert into appointments (id, contact_id, property_id, deal_id, source, type, starts_at, ends_at, location, notes, status, feedback) values ('c3a29c82-58a7-404b-905a-2162a3f243b9', '86939bd5-5090-407f-a8f8-dab50e179802', null, null, 'calendly', 'buyer_consult', '2026-08-31T15:30:00.000Z', '2026-08-31T16:15:00.000Z', 'Zoom', 'Referral from Deshawn', 'scheduled', null);
insert into appointments (id, contact_id, property_id, deal_id, source, type, starts_at, ends_at, location, notes, status, feedback) values ('8f78cf5b-9737-4ed4-aa95-fe514c1d99bf', 'e0bdfff9-7a46-45de-a4c2-db43d459c5b0', 'd1eb4cad-5692-4b8d-ac6f-b759e6604dc3', '0298c850-6e7d-4dfc-8b0a-ceda766c91a2', 'manual', 'inspection', '2026-09-04T09:00:00.000Z', '2026-09-04T11:00:00.000Z', '1234 Elm Street', null, 'scheduled', null);

-- content_items
insert into content_items (id, title, pillar, format, status, target_publish_date, hook, notes, source_type, source_deal_id, source_contact_id) values ('54c827d8-d36b-4910-8f8c-6b5fd3908aa4', 'Is Pike Road actually worth the price difference?', 'pros_cons', 'youtube_long', 'scripted', '2026-09-03', 'Everybody says Pike Road is ''worth it.'' Let''s actually run the numbers.', null, 'contact_question', null, '5fbd90c4-af93-4635-be23-bd52df4ef4dd');
insert into content_items (id, title, pillar, format, status, target_publish_date, hook, notes, source_type, source_deal_id, source_contact_id) values ('1c44fa96-c52b-486c-bc58-5ba71c5822b1', '5 Cloverdale streets locals fight to live on', 'area_guides', 'reel', 'filmed', '2026-09-01', 'This one street in Cloverdale never hits the market.', null, 'manual', null, null);
insert into content_items (id, title, pillar, format, status, target_publish_date, hook, notes, source_type, source_deal_id, source_contact_id) values ('b455287b-9d99-4159-b4d7-30815e754049', 'What $300k actually buys in Prattville right now', 'cost_of_living', 'reel', 'idea', '2026-09-04', 'Three houses, same price, wildly different.', null, 'manual', null, null);
insert into content_items (id, title, pillar, format, status, target_publish_date, hook, notes, source_type, source_deal_id, source_contact_id) values ('85b63c65-c3d1-45ae-9278-de73020e5507', 'August market update — rates, inventory, what it means', 'livestream', 'livestream', 'scheduled', '2026-09-02', 'Live Thursday: where the Montgomery market actually is.', null, 'manual', null, null);
insert into content_items (id, title, pillar, format, status, target_publish_date, hook, notes, source_type, source_deal_id, source_contact_id) values ('a195c6d9-da5a-4b08-b65b-573ed2615958', 'The truth nobody tells you about buying new construction', 'gut_check', 'youtube_long', 'idea', null, 'Builders don''t want you to know this one thing.', null, 'manual', null, null);
insert into content_items (id, title, pillar, format, status, target_publish_date, hook, notes, source_type, source_deal_id, source_contact_id) values ('e28806f2-8c78-43b5-86c8-7324800f72a3', 'Weekly email — 3 new listings under $350k', 'area_guides', 'email', 'idea', '2026-09-01', null, null, 'manual', null, null);
insert into content_items (id, title, pillar, format, status, target_publish_date, hook, notes, source_type, source_deal_id, source_contact_id) values ('d05d50d5-8c67-445e-a13a-1c3a4c49aa3e', 'Wetumpka vs Millbrook: which fits your family?', 'pros_cons', 'carousel', 'editing', '2026-08-31', null, null, 'manual', null, null);
insert into content_items (id, title, pillar, format, status, target_publish_date, hook, notes, source_type, source_deal_id, source_contact_id) values ('f250c34c-9d50-4e7d-bf9f-b573822ac50a', 'Property taxes in Montgomery County, explained', 'cost_of_living', 'blog', 'published', '2026-08-25', null, null, 'manual', null, null);
insert into content_items (id, title, pillar, format, status, target_publish_date, hook, notes, source_type, source_deal_id, source_contact_id) values ('7b4f4177-e399-4a33-b341-850b1cd5b2ac', 'Why I stopped recommending this popular subdivision', 'gut_check', 'reel', 'idea', null, 'I used to send everyone here. Not anymore.', null, 'manual', null, null);
insert into content_items (id, title, pillar, format, status, target_publish_date, hook, notes, source_type, source_deal_id, source_contact_id) values ('d92c58ef-e0b4-4467-85ae-c2aaea337038', 'Emerald Mountain area guide', 'area_guides', 'youtube_long', 'published', '2026-08-19', null, null, 'manual', null, null);
insert into content_items (id, title, pillar, format, status, target_publish_date, hook, notes, source_type, source_deal_id, source_contact_id) values ('8da50eec-3312-47d2-9769-1aa6f5569562', 'Should you buy before you sell? A gut check', 'gut_check', 'reel', 'scripted', '2026-09-05', null, null, 'manual', null, null);
insert into content_items (id, title, pillar, format, status, target_publish_date, hook, notes, source_type, source_deal_id, source_contact_id) values ('4afc5481-ca60-4fe5-9e2c-ddde3727a29c', 'Live Q&A: first-time buyer questions', 'livestream', 'livestream', 'published', '2026-08-22', null, null, 'manual', null, null);

commit;
