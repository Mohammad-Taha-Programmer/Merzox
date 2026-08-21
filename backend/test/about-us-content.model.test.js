import assert from 'node:assert/strict';
import test from 'node:test';

import {
  AboutUsContent,
  createDefaultAboutUsContent
} from '../src/models/AboutUsContent.js';
import { serializeAboutUs } from '../src/controllers/content.controller.js';

test('default About Us content contains four valid localized sections', () => {
  const content = new AboutUsContent(createDefaultAboutUsContent());

  assert.equal(content.validateSync(), undefined);
  assert.equal(content.sections.length, 4);
  assert.equal(new Set(content.sections.map((section) => section.key)).size, 4);

  const arabic = serializeAboutUs(content, 'ar');
  const english = serializeAboutUs(content, 'en');
  assert.equal(arabic.pageTitle, 'من نحن');
  assert.equal(english.pageTitle, 'About us');
  assert.equal(arabic.sections[0].title, 'آلية العمل');
  assert.equal(english.sections[3].title, 'Privacy policy');
});

test('About Us content rejects incomplete accordion data', () => {
  const data = createDefaultAboutUsContent();
  data.sections.pop();
  const content = new AboutUsContent(data);

  const validationError = content.validateSync();
  assert.ok(validationError);
  assert.ok(validationError.errors.sections);
});
