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
