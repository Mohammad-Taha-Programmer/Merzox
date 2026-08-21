import { env } from '../config/env.js';
import { sendVerificationEmail, smtpStatus } from '../services/email.service.js';

const to = process.argv[2] ?? env.smtp.user;
const status = smtpStatus();

console.log('SMTP configuration:', {
  configured: status.configured,
  SMTP_HOST: status.hostConfigured,
  SMTP_USER: status.userConfigured,
  SMTP_PASS: status.passConfigured,
  SMTP_FROM: status.fromConfigured
});

if (!status.configured) {
  console.error('SMTP is incomplete. Fill SMTP_HOST, SMTP_USER, SMTP_PASS, and SMTP_FROM in backend/.env.');
  process.exitCode = 1;
} else {
  try {
    await sendVerificationEmail({
      to,
      name: 'Merzox Test',
      link: `${env.publicBaseUrl}/api/v1/auth/verify-email?token=test`
    });
    console.log(`Test email sent to ${to}.`);
  } catch (error) {
    if (error?.code === 'EAUTH') {
      console.error(
        'SMTP authentication failed. Check SMTP_USER and SMTP_PASS. For Yandex/Gmail, SMTP_PASS usually must be an app password, not the normal mailbox password.'
      );
      console.error(`Provider response: ${error.response ?? error.message}`);
    } else {
      console.error(`SMTP test failed: ${error?.message ?? error}`);
    }

    process.exitCode = 1;
  }
}
