import { Router } from 'express';

import {
  blockConversationCounterpart,
  bookmarkConversationMessage,
  getMyConversationUnreadCount,
  listConversationMessages,
  listMyBlocks,
  listMyBookmarks,
  listMyConversations,
  listShareableProducts,
  markConversationRead,
  openConversation,
  searchMyConversations,
  sendConversationMessage,
  unblockConversationCounterpart,
  unblockUser,
  unbookmarkConversationMessage
} from '../controllers/message.controller.js';
import { requireAuth } from '../middleware/auth.js';
import {
  validateConversationOpen,
  validateMessageCreate
} from '../middleware/validate.js';

const router = Router();

router.use(requireAuth);

// Declared before `/:id/...` so the literal segment is never read as an id.
router.get('/unread-count', getMyConversationUnreadCount);
router.get('/search', searchMyConversations);
// Everything this reader marked, across every thread. Literal, so it is never
// read as a conversation id.
router.get('/bookmarks', listMyBookmarks);
// Everyone this reader has closed the door on. Literal, like `/bookmarks`, so
// it is never read as a conversation id.
router.get('/blocks', listMyBlocks);
router.delete('/blocks/:userId', unblockUser);
router.get('/', listMyConversations);
router.post('/', validateConversationOpen, openConversation);
router.get('/:id/messages', listConversationMessages);
// The shop's shelves, as seen from inside this thread. Not a catalogue route:
// which shop it is comes from the conversation, never from the caller.
router.get('/:id/products', listShareableProducts);
router.post('/:id/messages', validateMessageCreate, sendConversationMessage);
router.post(
  '/:id/messages/:messageId/bookmark',
  bookmarkConversationMessage
);
router.delete(
  '/:id/messages/:messageId/bookmark',
  unbookmarkConversationMessage
);
// Whom it blocks is the conversation's own other side, never a name in the
// request - there is no id to forge.
router.post('/:id/block', blockConversationCounterpart);
router.delete('/:id/block', unblockConversationCounterpart);
router.post('/:id/read', markConversationRead);

export default router;
