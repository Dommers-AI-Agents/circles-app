// backend/config/flags.js
//
// Every feature switch in one place, read from the environment at CALL time
// (tests and Cloud Run env updates flip them without a reload). Each keeps the
// exact rule it had where it used to be parsed inline — some are "on when
// '1'", some "on when 'true'", some "on unless '0'" — so nothing changes in
// production. New flags go here, never as a bare process.env read.
const on = (name, value = '1') => process.env[name] === value;

const flags = {
  /** Widgets pay FavCoins (drinks, postcards, events, clubs, widget data). */
  widgetPiggy: () => on('WIDGET_PIGGY_ENABLED'),
  /** Printed postcards and Fridge Mail. */
  postcardMail: () => on('POSTCARD_MAIL_ENABLED'),
  /** Server-picked home prompt cards. */
  homePrompts: () => on('HOME_PROMPTS_ENABLED'),
  /** The postcard nudge (on unless explicitly '0'). */
  postcardNudge: () => process.env.POSTCARD_NUDGE_ENABLED !== '0',
  /** Proximity check-in banners (on unless explicitly '0'). */
  proximityBanners: () => process.env.PROXIMITY_BANNERS_ENABLED !== '0',
  /** FavCoin claims to the Cactus wallet. */
  piggyClaims: () => on('PIGGY_CLAIMS_ENABLED', 'true'),
  /** Weekly map digest email job. */
  weeklyMapDigest: () => on('WEEKLY_MAP_DIGEST_ENABLED', 'true'),
  /** Kill switch for all outgoing email. */
  emailSendingDisabled: () => on('EMAIL_SENDING_DISABLED', 'true'),
  /** Paid LLM tiers need the flag AND a key. */
  categoryLlm: () => on('CATEGORY_LLM_ENABLED', 'true') && Boolean(process.env.ANTHROPIC_API_KEY),
  circleAdvisor: () => on('CIRCLE_ADVISOR_ENABLED', 'true') && Boolean(process.env.ANTHROPIC_API_KEY)
};

module.exports = flags;
