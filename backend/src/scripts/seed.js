import { connectDatabase, disconnectDatabase } from '../config/database.js';
import { env } from '../config/env.js';
import {
  CLI_ACTIONS,
  cliExecutionRefusal,
  cliRefusalMessage,
  safeCliErrorSummary
} from './cli-safety.js';
import {
  AboutUsContent,
  createDefaultAboutUsContent
} from '../models/AboutUsContent.js';
import { Business } from '../models/Business.js';
import { BusinessReview } from '../models/BusinessReview.js';
import { Favorite } from '../models/Favorite.js';
import { User } from '../models/User.js';

const businessNames = [
  'متجر الياسمين',
  'خضار المدينة',
  'مخبز الدار',
  'صيدلية الشفاء',
  'مكتبة النور',
  'زهور الربيع',
  'سوبر ماركت المدينة',
  'مطعم البيت'
];

const categories = [
  'مواد غذائية',
  'خضار وفواكه',
  'مخبوزات',
  'صحة وعناية',
  'قرطاسية وهدايا',
  'هدايا وزهور',
  'تقييم مرتفع',
  'وجبات وخدمات توصيل'
];

const productSets = [
  ['ألبان', 'قهوة', 'خضار'],
  ['تفاح', 'بندورة', 'خيار'],
  ['خبز', 'كعك', 'معجنات'],
  ['دواء', 'فيتامينات', 'عناية'],
  ['دفاتر', 'أقلام', 'هدايا'],
  ['ورد', 'شوكولاتة', 'هدايا'],
  ['منظفات', 'مشروبات', 'أغذية'],
  ['وجبات', 'مشاوي', 'سلطات']
];

const colors = [0xffdeeef8, 0xfff3ebb9, 0xffbff3b9, 0xffb9ddf3, 0xfffee3dc];

function buildBusiness(index, ownerId) {
  const template = index % businessNames.length;

  return {
    owner: index === 1 ? ownerId : undefined,
    publicId: `002${(10000 + index).toString()}`,
    name: `${businessNames[template]} ${index.toString().padStart(2, '0')}`,
    category: categories[template],
    description:
      'هذا النص افتراضي لتعريف المتجر والخدمات والمنتجات المتاحة في الحي.',
    address: `الحي ${template + 1}، شارع ${index}`,
    location: {
      type: 'Point',
      coordinates: [35.2 + template / 100, 31.9 + template / 100]
    },
    contacts: [
      {
        name: 'خدمة العملاء',
        phone: `+9725900${index.toString().padStart(4, '0')}`,
        email: `business${index}@merzox.local`
      }
    ],
    products: productSets[template].map((name, productIndex) => ({
      name,
      description: `منتج ${name} من ${businessNames[template]}`,
      price: 10 + productIndex * 5,
      imageUrl: '',
      classification: ['new', 'bestSelling', 'offers'][productIndex % 3],
      ratingAverage: 3.8 + productIndex / 2,
      ratingCount: 5 + productIndex,
      likeCount: productIndex * 3,
      isService: template === 3
    })),
    ratingAverage: 3.8 + (index % 12) / 10,
    ratingCount: 12 + index,
    followerCount: 20 + index * 2,
    discountLabel: index % 9 === 0 ? '15%' : undefined,
    colorValue: colors[index % colors.length],
    subscribedAt: new Date(Date.now() - index * 60 * 60 * 1000)
  };
}

async function seed() {
  await connectDatabase();

  await Promise.all([
    User.deleteMany({}),
    Business.deleteMany({}),
    BusinessReview.deleteMany({}),
    Favorite.deleteMany({}),
    AboutUsContent.deleteMany({})
  ]);

  await AboutUsContent.create(createDefaultAboutUsContent());

  const normalUser = new User({
    name: 'مستخدم تجريبي',
    email: 'user@merzox.local',
    phone: '+972590000001',
    phones: [{ value: '+972590000001', isPrimary: true }],
    address: 'رام الله',
    userType: 'normal',
    emailVerified: true,
    gender: 'female'
  });
  await normalUser.setPassword('Password123');
  await normalUser.save();

  const businessUser = new User({
    name: 'تاجر تجريبي',
    email: 'merchant@merzox.local',
    phone: '+972590000002',
    phones: [{ value: '+972590000002', isPrimary: true }],
    address: 'القدس',
    userType: 'business',
    emailVerified: true,
    gender: 'unspecified'
  });
  await businessUser.setPassword('Password123');
  await businessUser.save();

  const businesses = Array.from({ length: 240 }, (_, index) =>
    buildBusiness(index + 1, businessUser._id)
  );

  await Business.insertMany(businesses);

  console.log(
    'Seed complete. Development fixtures were recreated.'
  );

  await disconnectDatabase();
}

const seedAction =
  CLI_ACTIONS.destructiveSeed;

const seedRefusal =
  cliExecutionRefusal({
    nodeEnv:
      env.nodeEnv,
    allowValue:
      process.env[
        seedAction.allowFlag
      ]
  });

if (seedRefusal) {
  console.error(
    cliRefusalMessage({
      action:
        seedAction,
      refusal:
        seedRefusal
    })
  );

  process.exitCode = 1;
} else {
  seed().catch(
    async (error) => {
      console.error(
        'Seed failed.',
        safeCliErrorSummary(
          error
        )
      );

      try {
        await disconnectDatabase();
      } catch (
        disconnectError
      ) {
        console.error(
          'Seed database disconnect failed.',
          safeCliErrorSummary(
            disconnectError
          )
        );
      }

      process.exitCode = 1;
    }
  );
}
