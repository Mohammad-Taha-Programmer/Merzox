import { env } from '../config/env.js';
import {
  sendVerificationEmail,
  smtpStatus
} from '../services/email.service.js';
import {
  CLI_ACTIONS,
  cliExecutionRefusal,
  cliRefusalMessage,
  safeCliErrorSummary
} from './cli-safety.js';

async function runEmailDiagnostic() {
  const to =
    process.argv[2] ??
    env.smtp.user;

  const status =
    smtpStatus();

  console.log(
    'SMTP configuration:',
    {
      configured:
        status.configured,
      SMTP_HOST:
        status.hostConfigured,
      SMTP_USER:
        status.userConfigured,
      SMTP_PASS:
        status.passConfigured,
      SMTP_FROM:
        status.fromConfigured
    }
  );

  if (!status.configured) {
    console.error(
      'SMTP is incomplete. Fill SMTP_HOST, SMTP_USER, SMTP_PASS, and SMTP_FROM in backend/.env.'
    );

    process.exitCode = 1;
    return;
  }

  try {
    await sendVerificationEmail({
      to,
      name:
        'Merzox Test',
      link:
        `${env.publicBaseUrl}/api/v1/auth/verify-email?token=test`
    });

    console.log(
      'SMTP test message accepted for delivery.'
    );
  } catch (error) {
    if (
      error?.code ===
      'EAUTH'
    ) {
      console.error(
        'SMTP authentication failed. Check the configured SMTP credentials. ' +
        'The provider may require an application-specific password.',
        safeCliErrorSummary(
          error
        )
      );
    } else {
      console.error(
        'SMTP test failed.',
        safeCliErrorSummary(
          error
        )
      );
    }

    process.exitCode = 1;
  }
}

const diagnosticAction =
  CLI_ACTIONS.emailDiagnostic;

const diagnosticRefusal =
  cliExecutionRefusal({
    nodeEnv:
      env.nodeEnv,
    allowValue:
      process.env[
        diagnosticAction.allowFlag
      ]
  });

if (diagnosticRefusal) {
  console.error(
    cliRefusalMessage({
      action:
        diagnosticAction,
      refusal:
        diagnosticRefusal
    })
  );

  process.exitCode = 1;
} else {
  await runEmailDiagnostic();
}
