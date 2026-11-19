import {defineInt} from "firebase-functions/params";

// Shared pricing policy without importing optional gateway secrets.
export const platformFeeBps = defineInt("PLATFORM_FEE_BPS", {default: 1200});
