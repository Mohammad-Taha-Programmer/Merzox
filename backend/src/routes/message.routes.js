import { Router } from 'express';

import {
  getMyConversationUnreadCount,
  listConversationMessages,
  listMyConversations,
  markConversationRead,
  openConversation,
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
router.get('/', listMyConversations);
router.post('/', validateConversationOpen, openConversation);
router.get('/:id/messages', listConversationMessages);
router.post('/:id/messages', validateMessageCreate, sendConversationMessage);
router.post('/:id/read', markConversationRead);

export default router;
