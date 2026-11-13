import {defineBoolean, defineInt, defineSecret, defineString} from "firebase-functions/params";
import {HttpsError} from "firebase-functions/v2/https";

export const preparationEnabled = defineBoolean("PAYMENT_PREPARATION_ENABLED", {default: false});
export const platformFeeBps = defineInt("PLATFORM_FEE_BPS", {default: 1200});
export const paymentGatewayMode = defineString("PAYMENT_GATEWAY_MODE", {default: "toss-test"});
export const tossTestClientKey = defineString("TOSS_TEST_CLIENT_KEY", {default: ""});
export const checkoutBaseUrl = defineString("CHECKOUT_BASE_URL", {default: ""});
// The value is supplied only through Secret Manager when the payment codebase is deployed.
export const tossTestSecretKey = defineSecret("TOSS_TEST_SECRET_KEY");

export function assertLocalPreparation(enabled: boolean, env: NodeJS.ProcessEnv = process.env): void {
  if (!enabled || env.FUNCTIONS_EMULATOR !== "true" || !env.FIRESTORE_EMULATOR_HOST ||
      !env.FIREBASE_AUTH_EMULATOR_HOST || !env.GCLOUD_PROJECT?.startsWith("demo-")) {
    throw new HttpsError("failed-precondition", "STEP 4 preparation is disabled outside the demo emulators.");
  }
}

export function assertTestSecret(value: string): string {
  if (!/^(test_sk_|test_gsk_)/.test(value)) {
    throw new HttpsError("failed-precondition", "토스 테스트 Secret Key 설정이 필요합니다. 운영 키는 허용하지 않습니다.");
  }
  return value;
}
