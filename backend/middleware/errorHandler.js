// backend/middleware/errorHandler.js
// Unhandled errors: the full error goes to the logs; production clients get
// a generic message for 5xx so internals (paths, queries, stack traces) never
// reach them (security audit 2026-10-01). 4xx keep their message — those are
// meant for the user.
const errorHandler = (err, req, res, next) => {
  const status = err.statusCode || err.status || 500;
  console.error(err.stack || err);
  const expose = status < 500 || process.env.NODE_ENV !== 'production';
  res.status(status).json({
    success: false,
    error: expose ? (err.message || 'Server Error') : 'Something went wrong. Please try again.'
  });
};

module.exports = errorHandler;
