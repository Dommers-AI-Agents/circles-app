// backend/utils/serviceError.js
//
// One shape for "the service refused": an HTTP status, a stable code the
// app can switch on, a sentence for the person, and optional details
// spread into the response body. Every feature service used to declare
// its own identical class and every controller its own `fail`; the
// subclasses below keep `instanceof` and test assertions working.
class ServiceError extends Error {
  constructor(status, code, message, details = null) {
    super(message);
    this.name = this.constructor.name;
    this.status = status;
    this.code = code;
    if (details) this.details = details;
  }
}

/**
 * Sends a ServiceError (or anything carrying status+code) as its own
 * response; anything else is logged and becomes a 500 with the feature's
 * fallback text. `fallbackCode` is optional so bodies that never had a
 * code keep their shape.
 */
function sendServiceError(res, error, { log, fallbackCode, fallbackMessage }) {
  if (error && error.status && error.code) {
    return res.status(error.status).json({
      success: false, code: error.code, message: error.message, ...(error.details || {})
    });
  }
  console.error(`${log}:`, error && error.message);
  const body = { success: false, message: fallbackMessage };
  if (fallbackCode) body.code = fallbackCode;
  return res.status(500).json(body);
}

module.exports = { ServiceError, sendServiceError };
