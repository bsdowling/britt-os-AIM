// Domain types — mirror the Supabase schema (PRD §3).

export type DealSide = "buyer" | "seller" | "both";

export type DealStatus =
  | "active_search"
  | "listing_prep"
  | "active_listing"
  | "under_contract"
  | "inspection"
  | "appraisal"
  | "financing"
  | "clear_to_close"
  | "closing"
  | "sold"
  | "dead";

export type FinancingType = "conventional" | "fha" | "va" | "usda" | "cash";

export type DealHealth = "green" | "amber" | "red";

export type TaskAnchor =
  | "contract"
  | "inspection"
  | "appraisal"
  | "financing"
  | "closing"
  | "list_date"
  | "manual";

export type TaskStatus = "open" | "done" | "skipped";
export type TaskPriority = "low" | "normal" | "high";

export type ApptType =
  | "showing"
  | "listing_appt"
  | "buyer_consult"
  | "closing"
  | "inspection"
  | "photo_shoot"
  | "other";

export type ApptStatus = "scheduled" | "completed" | "cancelled" | "no_show";

export type ContentPillar =
  | "area_guides"
  | "pros_cons"
  | "gut_check"
  | "cost_of_living"
  | "livestream";

export type ContentFormat =
  | "youtube_long"
  | "reel"
  | "livestream"
  | "email"
  | "blog"
  | "carousel"
  | "gbp_post";

export type ContentStatus =
  | "idea"
  | "scripted"
  | "filmed"
  | "editing"
  | "scheduled"
  | "published";

export type ContentSource =
  | "deal"
  | "contact_question"
  | "listing"
  | "market_data"
  | "manual";

export interface EmailEntry {
  value: string;
  type?: string;
  is_primary?: boolean;
}
export type PhoneEntry = EmailEntry;

export interface Contact {
  id: string;
  fub_person_id: number;
  first_name: string | null;
  last_name: string | null;
  emails: EmailEntry[];
  phones: PhoneEntry[];
  stage: string | null;
  source: string | null;
  tags: string[];
  assigned_pond: string | null;
  fub_created_at: string | null;
  last_inbound_at: string | null;
  last_outbound_at: string | null;
  lifetime_value: number;
  lead_score: number;
  is_archived: boolean;
  synced_at: string | null;
  // generated column
  needs_response: boolean;
  created_at: string;
  updated_at: string;
}

export interface Property {
  id: string;
  mls_number: string | null;
  address_line1: string | null;
  city: string | null;
  state: string | null;
  zip: string | null;
  county: string | null;
  beds: number | null;
  baths: number | null;
  sqft: number | null;
  subdivision: string | null;
  school_district: string | null;
  photos: string[];
  created_at: string;
  updated_at: string;
}

export interface Deal {
  id: string;
  contact_id: string;
  property_id: string | null;
  side: DealSide;
  status: DealStatus;
  contract_date: string | null;
  inspection_deadline: string | null;
  appraisal_deadline: string | null;
  financing_deadline: string | null;
  closing_date: string | null;
  sale_price: number | null;
  commission_rate: number;
  financing_type: FinancingType | null;
  brokerage_file_url: string | null;
  notes: string | null;
  dead_reason: string | null;
  gross_commission: number;
  created_at: string;
  updated_at: string;
}

export interface Task {
  id: string;
  deal_id: string | null;
  contact_id: string | null;
  title: string;
  description: string | null;
  due_date: string | null;
  due_time: string | null;
  anchor_type: TaskAnchor | null;
  anchor_offset_days: number | null;
  is_pinned: boolean;
  status: TaskStatus;
  priority: TaskPriority;
  template_item_id: string | null;
  is_client_visible: boolean;
  completed_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface Appointment {
  id: string;
  contact_id: string | null;
  property_id: string | null;
  deal_id: string | null;
  source: string;
  type: ApptType;
  starts_at: string;
  ends_at: string | null;
  location: string | null;
  notes: string | null;
  status: ApptStatus;
  feedback: string | null;
}

export interface ContentItem {
  id: string;
  title: string;
  pillar: ContentPillar | null;
  format: ContentFormat | null;
  status: ContentStatus;
  target_publish_date: string | null;
  hook: string | null;
  notes: string | null;
  source_type: ContentSource | null;
  source_deal_id: string | null;
  source_contact_id: string | null;
  canva_url: string | null;
  published_url: string | null;
  created_at: string;
  updated_at: string;
}

export interface Listing {
  id: string;
  deal_id: string;
  property_id: string | null;
  list_date: string | null;
  list_price: number | null;
  current_price: number | null;
  price_history: { date: string; price: number; reason?: string }[];
  mls_status: string | null;
  showing_count_7d: number;
  showing_count_total: number;
  unread_feedback_count: number;
}

// The seven-stage milestone tracker (PRD §6.1)
export const MILESTONE_STAGES = [
  "under_contract",
  "inspection",
  "appraisal",
  "financing",
  "clear_to_close",
  "closing",
  "sold",
] as const;
export type MilestoneStage = (typeof MILESTONE_STAGES)[number];

export const STAGE_LABELS: Record<string, string> = {
  active_search: "Active Search",
  listing_prep: "Listing Prep",
  active_listing: "Active Listing",
  under_contract: "Under Contract",
  inspection: "Inspection",
  appraisal: "Appraisal",
  financing: "Financing",
  clear_to_close: "Clear to Close",
  closing: "Closing",
  sold: "Sold",
  dead: "Dead",
};
