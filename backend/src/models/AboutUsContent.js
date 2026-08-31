import mongoose from 'mongoose';

const ABOUT_US_SECTION_KEYS = [
  'how-it-works',
  'terms-of-use',
  'operating-rules',
  'privacy-policy'
];

const localizedTextSchema = new mongoose.Schema(
  {
    ar: { type: String, required: true, trim: true, maxlength: 4000 },
    en: { type: String, required: true, trim: true, maxlength: 4000 }
  },
  { _id: false }
);

const aboutUsSectionSchema = new mongoose.Schema(
  {
    key: {
      type: String,
      required: true,
      enum: ABOUT_US_SECTION_KEYS
    },
    title: { type: localizedTextSchema, required: true },
    content: { type: localizedTextSchema, required: true },
    order: { type: Number, required: true, min: 0, max: 3 }
  },
  { _id: false }
);

const defaultSections = [
  {
    key: 'how-it-works',
    title: { ar: 'آلية العمل', en: 'How it works' },
    content: {
      ar: 'يساعدك Merzox على اكتشاف المتاجر والأعمال القريبة، والبحث عن المنتجات والخدمات، والتواصل مع البائع ثم إتمام الطلب ومتابعته من مكان واحد.',
      en: 'Merzox helps you discover nearby businesses, find products and services, contact the seller, and then place and track an order in one place.'
    },
    order: 0
  },
  {
    key: 'terms-of-use',
    title: { ar: 'شروط العمل', en: 'Terms of use' },
    content: {
      ar: 'يجب تقديم معلومات حساب صحيحة واستخدام التطبيق بصورة قانونية. تعرض تفاصيل السعر والتوصيل والدفع قبل تأكيد الطلب، وتخضع المعاملة للشروط المعروضة وقت الشراء.',
      en: 'You must provide accurate account information and use the app lawfully. Price, delivery, and payment details are shown before an order is confirmed, and the transaction follows the terms displayed at purchase.'
    },
    order: 1
  },
  {
    key: 'operating-rules',
    title: { ar: 'أحكام العمل', en: 'Operating rules' },
    content: {
      ar: 'يلتزم المستخدمون والمتاجر باحترام الآخرين، ودقة بيانات المنتجات، وعدم نشر محتوى مضلل أو ضار. يمكن تقييد الحسابات التي تخالف هذه الأحكام لحماية مجتمع Merzox.',
      en: 'Users and businesses must respect others, keep product information accurate, and avoid misleading or harmful content. Accounts that breach these rules may be restricted to protect the Merzox community.'
    },
    order: 2
  },
  {
    key: 'privacy-policy',
    title: { ar: 'سياسة الخصوصية', en: 'Privacy policy' },
    content: {
      ar: 'يجمع Merzox البيانات اللازمة لتشغيل الحساب والطلبات فقط. لا تستخدم بيانات الموقع أو جهات الاتصال أو التخصيص بالذكاء الاصطناعي إلا بعد موافقتك، ويمكنك إدارة هذه الأذونات من إعدادات التطبيق والجهاز.',
      en: 'Merzox collects only the data needed to operate accounts and orders. Location, contacts, and AI personalization data are not used without your permission, and you can manage these permissions in the app and device settings.'
    },
    order: 3
  }
];

export function createDefaultAboutUsContent() {
  return {
    key: 'about-us',
    pageTitle: { ar: 'من نحن', en: 'About us' },
    appLabel: { ar: 'تطبيق', en: 'Application' },
    appName: 'MERZOX',
    introduction: {
      ar: 'Merzox منصة تجارة إلكترونية تربط المستخدمين بالمتاجر والأعمال القريبة، وتسهّل اكتشاف المنتجات والخدمات والتواصل والطلب من مكان واحد.',
      en: 'Merzox is an e-commerce platform that connects people with nearby businesses and makes it easier to discover products, communicate, and order in one place.'
    },
    sections: defaultSections.map((section) => ({
      ...section,
      title: { ...section.title },
      content: { ...section.content }
    }))
  };
}

const aboutUsContentSchema = new mongoose.Schema(
  {
    key: {
      type: String,
      enum: ['about-us'],
      default: 'about-us',
      unique: true,
      immutable: true
    },
    pageTitle: { type: localizedTextSchema, required: true },
    appLabel: { type: localizedTextSchema, required: true },
    appName: {
      type: String,
      required: true,
      trim: true,
      minlength: 1,
      maxlength: 40
    },
    introduction: { type: localizedTextSchema, required: true },
    sections: {
      type: [aboutUsSectionSchema],
      required: true,
      validate: {
        validator(value) {
          return (
            value.length === ABOUT_US_SECTION_KEYS.length &&
            new Set(value.map((section) => section.key)).size ===
              ABOUT_US_SECTION_KEYS.length
          );
        },
        message: 'About Us content requires four distinct sections'
      }
    }
    // There was an `isPublished` flag here, defaulted true and indexed. The
    // one query this collection has selects on `key` alone and never read it,
    // so setting it false unpublished nothing. There is no surface anywhere
    // that could set it, either. A field that promises a capability it does
    // not have is worse than no field.
  },
  { timestamps: true }
);

export const AboutUsContent = mongoose.model(
  'AboutUsContent',
  aboutUsContentSchema
);
