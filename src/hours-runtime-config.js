// Release control only. No UI, URL or localStorage can enable V3.
// These fields are deployment declarations, NOT database/catalog proof or permissions.
export const HOURS_RUNTIME_RELEASE=Object.freeze({
 version:1,enabled:true,activationApproved:true,
 backend:Object.freeze({stage6Postcheck:'DAILY_V2_POSTCHECK_PASS_NOT_ACTIVATED',ad15Postcheck:'AD15_POSTCHECK_OK',remainingV3ChainVerified:true})
});
