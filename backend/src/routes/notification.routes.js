import { Router } from 'express';

import {
  getMyNotificationUnreadCount,
  listMyNotifications,
  markAllNotificationsRead,
  markNotificationRead
} from '../controllers/notification.controller.js';
import { requireAuth } from '../middleware/auth.js';

const router = Router();

router.use(requireAuth);

router.get('/unread-count', getMyNotificationUnreadCount);
router.post('/read-all', markAllNotificationsRead);
router.get('/', listMyNotifications);
router.post('/:id/read', markNotificationRead);

export default router;
