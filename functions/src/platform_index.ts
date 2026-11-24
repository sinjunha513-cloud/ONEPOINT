// Deploy the platform workflows independently of optional payment secrets.
import {getApps, initializeApp} from "firebase-admin/app";

if (getApps().length === 0) initializeApp();

export {adminManageAccount, validateCareerPdf} from "./admin_accounts";
export {projectUserPublicProfile, projectInstructorPublicProfile, requestLesson, requestLessonWithSlot, completeLesson, setFeedLiked, deleteVideo} from "./security_workflows";
export {saveAvailabilitySlot, saveAvailabilitySlots, deleteAvailabilitySlot, rescheduleLesson, releaseCancelledSlot, projectPublicAvailability} from "./scheduling";
export {notifyLessonActivity, notifyChatMessage, notifyLessonFeedback, notifyCoachReview, notifyFeedReaction, syncMyNotifications} from "./notifications";
export {claimMonthlyCoupon, applyLessonCoupon, removeLessonCoupon, syncLessonCoupon, syncPaymentCoupon} from "./coupons";

export {acceptLesson, rejectLesson, cancelLesson, respondScheduleChange, respondLessonCompletion, resolveLessonDispute, expireLessonRequests} from "./lesson_workflow";
export {setUserBlocked,submitReport,resolveReport,notifyReportActivity,projectPublicFeed,refreshAuthorFeed} from './community';
export {getPushConfiguration,registerPushDevice,unregisterPushDevice,setPushPreference,sendNotificationPush} from './push_delivery';
export {requestAccountDeletion,beginAccountCleanup,retryAccountCleanup} from './account_lifecycle';
export {getMediaPlayback} from './media_playback';
export {syncMyActivity,syncLessonActivity} from './activity_stats';
