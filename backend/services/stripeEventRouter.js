// backend/services/stripeEventRouter.js
// One Stripe webhook endpoint, one signing secret, two feature handlers.
// Attribution is by the event's object type and `metadata.kind`: printed
// postcard orders own payment intents carrying `metadata.orderId` (and the
// charge refunds that follow them); Fridge Mail owns pack payments
// (`metadata.kind = 'fridgemail_pack'`), invoices and subscriptions.
const postcardMailService = require('./postcardMailService');
const fridgeMailService = require('./fridgeMailService');

async function route(event) {
  const obj = (event && event.data && event.data.object) || {};
  const kind = (obj.metadata && obj.metadata.kind) || null;
  switch (obj.object) {
    case 'payment_intent':
      if (kind === fridgeMailService.PACK_KIND) return fridgeMailService.handleStripeEvent(event);
      return postcardMailService.handleStripeEvent(event);
    case 'charge':
      return postcardMailService.handleStripeEvent(event);
    case 'invoice':
    case 'subscription':
      return fridgeMailService.handleStripeEvent(event);
    default:
      return { ignored: true };
  }
}

module.exports = { route };
