import { Router } from 'express';

import {
  getMyConversationUnreadCount,
  listConversationMessages,
  listMyConversations,
  listShareableProducts,
  markConversationRead,
  openConversation,
  searchMyConversations,
  sendConversationMessage
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
router.get('/', listMyConversations);
router.post('/', validateConversationOpen, openConversation);
router.get('/:id/messages', listConversationMessages);
// The shop's shelves, as seen from inside this thread. Not a catalogue route:
// which shop it is comes from the conversation, never from the caller.
router.get('/:id/products', listShareableProducts);
router.post('/:id/messages', validateMessageCreate, sendConversationMessage);
router.post('/:id/read', markConversationRead);

export default router;
