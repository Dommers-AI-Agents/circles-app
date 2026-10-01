// backend/services/conversationAccess.js
//
// Who may be put into a conversation, and who may still write into one.
// Security audit 2026-10-01: POST /api/messages/conversations accepted any
// list of user ids — no connection check, no size cap — so anyone could
// build a "group" of strangers and push every one of them a message. Direct
// chats already required an accepted connection (getOrCreateDirectConversation);
// groups and added participants now follow the same rule.

const { ServiceError } = require('../utils/serviceError');
const { isSameUser } = require('./idService');
const { excludedUserIds } = require('./moderationService');

const MAX_PARTICIPANTS = 50;   // including the creator
const MAX_MESSAGE_CHARS = 4000;

/**
 * Validates the ids someone wants in a conversation with them. Returns the
 * cleaned, de-duplicated list of OTHER participants; throws ServiceError when
 * any of them isn't an accepted connection of `creatorId` or is blocked.
 * `connectedIds` is injectable for tests; production reads it.
 */
async function vetParticipants({ creatorId, creatorData, participantIds, connectedIds = null }) {
  if (!Array.isArray(participantIds) || participantIds.some(id => typeof id !== 'string' || !id.trim())) {
    throw new ServiceError(400, 'invalid_participants', 'Participants must be a list of user ids');
  }
  const others = [...new Set(participantIds.map(id => id.trim()))].filter(id => !isSameUser(id, creatorId));
  if (others.length === 0) {
    throw new ServiceError(400, 'invalid_participants', 'Add at least one other person');
  }
  if (others.length + 1 > MAX_PARTICIPANTS) {
    throw new ServiceError(400, 'too_many_participants', `A conversation can have up to ${MAX_PARTICIPANTS} people`);
  }

  const blocked = excludedUserIds(creatorData);
  if (others.some(id => blocked.has(id))) {
    throw new ServiceError(403, 'blocked', 'You can’t start a conversation with someone you’ve blocked or who blocked you');
  }

  let connected = connectedIds;
  if (!connected) {
    const { getConnectedUserIds } = require('../utils/networkAccess');
    connected = await getConnectedUserIds(creatorId);
  }
  const connectedList = [...connected];
  const strangers = others.filter(id => !connectedList.some(c => isSameUser(c, id)));
  if (strangers.length > 0) {
    throw new ServiceError(403, 'not_connected', 'You can only add people you’re connected with', { notConnected: strangers });
  }
  return others;
}

/** Message body rule shared by send: present-or-media, and bounded. */
function checkMessageContent(content) {
  if (content !== undefined && content !== null && typeof content !== 'string') {
    throw new ServiceError(400, 'invalid_content', 'Message content must be text');
  }
  if (typeof content === 'string' && content.length > MAX_MESSAGE_CHARS) {
    throw new ServiceError(400, 'message_too_long', `Messages can be up to ${MAX_MESSAGE_CHARS} characters`);
  }
}

/**
 * True when a direct (two-person) conversation must refuse a new message
 * because either side blocked the other. `senderData` is the sender's user
 * doc; blockedBy is denormalized onto it, so one doc answers both directions.
 */
function directChatBlocked(conversation, senderId, senderData) {
  if (!conversation || conversation.type !== 'direct') return false;
  const blocked = excludedUserIds(senderData);
  return (conversation.participants || []).some(p => !isSameUser(p, senderId) && blocked.has(p));
}

module.exports = {
  vetParticipants,
  checkMessageContent,
  directChatBlocked,
  MAX_PARTICIPANTS,
  MAX_MESSAGE_CHARS
};
