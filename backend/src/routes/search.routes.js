import { Router } from 'express';

import { searchCatalog } from '../controllers/search.controller.js';

const router = Router();

router.get('/', searchCatalog);

export default router;
