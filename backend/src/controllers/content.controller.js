import { AboutUsContent, createDefaultAboutUsContent } from '../models/AboutUsContent.js';
import { asyncHandler } from '../utils/asyncHandler.js';

function localizedValue(value, language) {
  const preferred = value?.[language]?.trim();
  if (preferred) return preferred;

  const fallback = value?.ar?.trim() || value?.en?.trim();
  return fallback ?? '';
}

export function serializeAboutUs(content, language) {
  return {
    pageTitle: localizedValue(content.pageTitle, language),
    appLabel: localizedValue(content.appLabel, language),
    appName: content.appName,
    introduction: localizedValue(content.introduction, language),
    sections: [...content.sections]
      .sort((left, right) => left.order - right.order)
      .map((section) => ({
        key: section.key,
        title: localizedValue(section.title, language),
        content: localizedValue(section.content, language)
      })),
    updatedAt: content.updatedAt
  };
}

export const getAboutUs = asyncHandler(async (req, res) => {
  const language = req.query.lang === 'en' ? 'en' : 'ar';
  const content = await AboutUsContent.findOneAndUpdate(
    { key: 'about-us' },
    { $setOnInsert: createDefaultAboutUsContent() },
    {
      upsert: true,
      new: true,
      runValidators: true,
      setDefaultsOnInsert: true
    }
  ).lean();

  res.json({
    success: true,
    data: { aboutUs: serializeAboutUs(content, language) }
  });
});
