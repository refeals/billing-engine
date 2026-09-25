// Public on purpose: the demo login shows them. Must match Demo::User in the API
// (api/app/services/demo/user.rb). Kept free of imports so the Node-side end-to-end suite
// can use it too.
export const DEMO_CREDENTIALS = {
  email: 'demo@billing-engine.dev',
  password: 'demo-billing-2026',
} as const
