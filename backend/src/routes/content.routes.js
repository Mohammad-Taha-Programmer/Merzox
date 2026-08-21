import { Router } from 'express';

import { getAboutUs } from '../controllers/content.controller.js';

const router = Router();

router.get('/about-us', getAboutUs);

export default router;
