import {getAuth} from "firebase-admin/auth";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {PDFDocument} from "pdf-lib";

export const adminManageAccount = onCall({region: "asia-northeast3", timeoutSeconds: 120, maxInstances: 2}, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "관리자 로그인이 필요합니다.");
  const input = request.data as Record<string, unknown>;
  if (!input || Object.keys(input).some(k => !["uid", "action", "reason"].includes(k)) ||
      typeof input.uid !== "string" || !input.uid || input.uid.includes("/") || input.uid.length > 128 ||
      !["suspend", "restore", "delete"].includes(input.action as string) ||
      typeof input.reason !== "string" || !input.reason.trim() || input.reason.length > 500) {
    throw new HttpsError("invalid-argument", "대상 회원과 처리 사유를 확인해 주세요.");
  }
  const uid = input.uid, action = input.action as string, db = getFirestore(), auth = getAuth();
  const ref = db.collection("users").doc(uid);
  const actor = (await db.collection("users").doc(request.auth.uid).get()).data();
  if (actor?.role !== "admin" || (actor.accountStatus ?? "active") !== "active") throw new HttpsError("permission-denied", "현재 관리자만 계정을 관리할 수 있습니다.");
  if (uid === request.auth.uid) throw new HttpsError("failed-precondition", "본인 관리자 계정은 정지하거나 삭제할 수 없습니다.");
  const target = (await ref.get()).data();
  if (!target || !["student", "coach"].includes(target.role)) throw new HttpsError("failed-precondition", "수강생 또는 코치 계정만 관리할 수 있습니다.");
  if (target.accountStatus === "deleted") {
    if (action === "delete") return {uid, accountStatus: "deleted"};
    throw new HttpsError("failed-precondition", "삭제된 계정은 복구할 수 없습니다.");
  }
  const instructorRef = db.collection("instructors").doc(uid);
  const operation = db.collection("account_admin_operations").doc(uid);
  await db.runTransaction(async tx => {
    const administrator = (await tx.get(db.collection("users").doc(request.auth!.uid))).data();
    const member = (await tx.get(ref)).data();
    const instructor = (await tx.get(instructorRef)).data();
    const previous = (await tx.get(operation)).data();
    if (previous?.state === "pending" && previous.leaseUntil?.toMillis() > Date.now()) throw new HttpsError("aborted", "다른 계정 처리가 진행 중입니다. 잠시 후 다시 시도해 주세요.");
    if (administrator?.role !== "admin" || (administrator.accountStatus ?? "active") !== "active" || !member || !["student", "coach"].includes(member.role)) throw new HttpsError("permission-denied", "계정 권한이 변경되었습니다.");
    if (member.accountStatus === "deleting" && action !== "delete") throw new HttpsError("failed-precondition", "삭제 처리 중인 계정입니다.");
    // Block existing tokens immediately through Rules before Auth mutation.
    tx.update(ref, {accountStatus: action === "delete" ? "deleting" : action === "restore" ? "restoring" : "suspended", updatedAt: FieldValue.serverTimestamp()});
    if (instructor) tx.update(instructorRef, {
      approvalBeforeSuspension: instructor.status === "suspended" ? instructor.approvalBeforeSuspension ?? "pending" : instructor.status,
      status: "suspended", updatedAt: FieldValue.serverTimestamp(),
    });
    tx.set(operation, {uid, action, reason: input.reason, actorUid: request.auth!.uid, state: "pending", leaseUntil: new Date(Date.now() + 180000), updatedAt: FieldValue.serverTimestamp()});
  });
  try {
    if (action === "restore") {
      await auth.updateUser(uid, {disabled: false});
      await db.runTransaction(async tx => {
        const coach = (await tx.get(instructorRef)).data();
        tx.update(ref, {accountStatus: "active", updatedAt: FieldValue.serverTimestamp()});
        if (coach) tx.update(instructorRef, {status: ["approved", "pending", "rejected"].includes(coach.approvalBeforeSuspension) ? coach.approvalBeforeSuspension : "pending", updatedAt: FieldValue.serverTimestamp()});
        tx.update(operation, {state: "completed", updatedAt: FieldValue.serverTimestamp()});
      });
    } else {
      try { await auth.updateUser(uid, {disabled: true}); await auth.revokeRefreshTokens(uid); }
      catch (error) { if ((error as {code?: string}).code !== "auth/user-not-found") throw error; }
      if (action === "delete") {
        try { await auth.deleteUser(uid); } catch (error) { if ((error as {code?: string}).code !== "auth/user-not-found") throw error; }
        const batch = db.batch();
        batch.set(ref, {uid, role: target.role, accountStatus: "deleted", profileCompleted: false, deletedAt: FieldValue.serverTimestamp(), deletedBy: request.auth.uid});
        batch.delete(instructorRef); batch.update(operation, {state: "completed", updatedAt: FieldValue.serverTimestamp()});
        await batch.commit();
        // Financial/lesson/chat evidence is retained; only profile PDFs are removed.
        try { await getStorage().bucket().deleteFiles({prefix: `coach_documents/${uid}/`}); await db.recursiveDelete(db.collection("coach_document_uploads").doc(uid)); }
        catch { await operation.set({documentCleanupPending: true}, {merge: true}); }
      } else { await operation.update({state: "completed", updatedAt: FieldValue.serverTimestamp()}); }
    }
  } catch {
    await operation.set({state: "retry_required", updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    throw new HttpsError("unavailable", "접근은 차단했지만 서버 처리가 완료되지 않았습니다. 같은 작업을 다시 실행해 주세요.");
  }
  return {uid, accountStatus: action === "delete" ? "deleted" : action === "restore" ? "active" : "suspended"};
});

export const validateCareerPdf = onCall({region: "asia-northeast3", timeoutSeconds: 60, maxInstances: 2}, async request => {
  if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  const {fileId, fileName} = request.data ?? {};
  if (typeof fileId !== "string" || !/^[A-Za-z0-9_-]{1,100}$/.test(fileId) || typeof fileName !== "string" || fileName.length > 200) throw new HttpsError("invalid-argument", "파일 정보를 확인해 주세요.");
  const uid = request.auth.uid, db = getFirestore();
  const user = (await db.collection("users").doc(uid).get()).data();
  if (!user || (user.accountStatus ?? "active") !== "active") throw new HttpsError("permission-denied", "활성 계정만 업로드할 수 있습니다.");
  const path = `coach_documents/${uid}/${fileId}.pdf`, file = getStorage().bucket().file(path);
  const [metadata] = await file.getMetadata();
  if (metadata.contentType !== "application/pdf" || Number(metadata.size) <= 0 || Number(metadata.size) > 5 * 1024 * 1024) throw new HttpsError("invalid-argument", "5MB 이하 PDF 파일만 업로드할 수 있습니다.");
  const [bytes] = await file.download();
  try { const document = await PDFDocument.load(bytes); if (document.getPageCount() < 1) throw new Error("empty"); }
  catch { throw new HttpsError("invalid-argument", "읽을 수 있는 PDF가 아닙니다. 암호를 해제한 PDF로 업로드해 주세요."); }
  await db.collection("coach_document_uploads").doc(uid).collection("files").doc(fileId).set({uid, fileId, fileName, path, verified: true, size: Number(metadata.size), createdAt: FieldValue.serverTimestamp()});
  return {fileId, fileName, size: Number(metadata.size)};
});
