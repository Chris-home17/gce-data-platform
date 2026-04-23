// Dev-bypass is a local-only convenience that skips Azure AD sign-in.
// It MUST never be enabled in a production build — `next.config.mjs`
// also fails the build if the flag is true and NODE_ENV is production.
export const DEV_BYPASS =
  process.env.NEXT_PUBLIC_DEV_BYPASS === 'true' &&
  process.env.NODE_ENV !== 'production'
