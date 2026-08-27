import { buildRecommendationView } from '../services/recommendation.service.js';
import { asyncHandler } from '../utils/asyncHandler.js';

export const getMyRecommendations = asyncHandler(
  async (req, res) => {
    const recommendation = await buildRecommendationView({
      user: req.user
    });

    res.json({
      success: true,
      data: recommendation
    });
  }
);
