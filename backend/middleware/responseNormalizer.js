// backend/middleware/responseNormalizer.js
// Error responses are split between {success:false, message:...} (most
// controllers) and {success:false, error:...} (rewards/subscription/referral/
// auth). Clients have repeatedly shown generic text because they read the
// key a given endpoint didn't use. This wraps res.json so every non-2xx JSON
// object response carries BOTH keys — controllers stay untouched, and the
// split can never bite a client again.

module.exports = (req, res, next) => {
  const originalJson = res.json.bind(res);
  res.json = (body) => {
    if (res.statusCode >= 400 && body && typeof body === 'object' && !Array.isArray(body)) {
      if (typeof body.message === 'string' && body.error === undefined) {
        body.error = body.message;
      } else if (typeof body.error === 'string' && body.message === undefined) {
        body.message = body.error;
      }
    }
    return originalJson(body);
  };
  next();
};
