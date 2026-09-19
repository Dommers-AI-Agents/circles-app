// backend/middleware/scheduledTask.js
//
// Every scheduled-task endpoint has the same shape: log that it was
// triggered, run one service call, answer `{ success: true, …body,
// timestamp }` or `{ success: false, error, details }`. This wrapper is
// that shape once, so routes/taskRoutes.js can be a manifest again.
function scheduledTask({ name, log, failure, run }) {
  return async (req, res) => {
    try {
      const line = typeof log === 'function' ? log(req) : log;
      if (Array.isArray(line)) console.log(...line); else console.log(line);
      const body = (await run(req)) || {};
      res.json({ success: true, ...body, timestamp: new Date().toISOString() });
    } catch (error) {
      console.error(`❌ Error in ${name} endpoint:`, error);
      res.status(500).json({ success: false, error: failure, details: error.message });
    }
  };
}

module.exports = { scheduledTask };
