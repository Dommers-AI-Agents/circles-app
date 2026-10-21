// backend/services/clubService.js
//
// Clubs widget (run clubs, walk groups, book clubs…; Wes, 2026-10-21). The
// pieces live in services/clubs/: shared (rules, schedule → dated
// occurrences, what a member sees), membership, schedule (meetups, one-off
// events, RSVPs) and posts (bulletin, board, replies). This file is the one
// import for controllers and the landing page.
module.exports = {
  ...require('./clubs/membership'),
  ...require('./clubs/schedule'),
  ...require('./clubs/posts')
};
