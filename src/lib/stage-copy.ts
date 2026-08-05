// Plain-language stage copy for the client portal (PRD §6.2). Written once,
// reused forever. Normal-person language, not real-estate jargon.

import type { MilestoneStage } from "./types";

export const STAGE_CLIENT_COPY: Record<MilestoneStage, string> = {
  under_contract:
    "Your offer is accepted and the contract is signed by everyone. We're officially underway. Over the next few weeks we'll work through inspections, the appraisal, and financing — I'll guide you through each step.",
  inspection:
    "A licensed inspector is checking the home top to bottom so there are no surprises. Once I have the report, we'll go through it together and decide if we're asking the seller to fix anything.",
  appraisal:
    "The lender ordered an appraisal, which is when a licensed appraiser confirms the house is worth what you agreed to pay. This usually takes about a week. Nothing needed from you right now.",
  financing:
    "Your lender is finalizing the loan — verifying documents and getting final approval. This is the stretch where they may ask for a document or two. Send anything they request quickly and we stay on schedule.",
  clear_to_close:
    "The loan is fully approved — this is called 'clear to close.' The finish line is in sight. Next we confirm the closing time, do a final walkthrough, and get you your keys.",
  closing:
    "Closing week. You'll do a final walkthrough of the home, review the closing figures, and sign the paperwork. I'll send exact times and remind you what to bring. Then the house is yours.",
  sold:
    "Congratulations — it's official, the home is yours! I'm here for anything you need going forward, from contractor recommendations to questions down the road.",
};
