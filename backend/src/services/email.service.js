import nodemailer from 'nodemailer';

import { env } from '../config/env.js';
import { logger } from '../observability/logger.js';

function smtpConfigured() {
  return Boolean(env.smtp.host && env.smtp.user && env.smtp.pass && env.smtp.from);
}

export function smtpStatus() {
  return {
    configured: smtpConfigured(),
    hostConfigured: Boolean(env.smtp.host),
    userConfigured: Boolean(env.smtp.user),
    passConfigured: Boolean(env.smtp.pass),
    fromConfigured: Boolean(env.smtp.from)
  };
}

let transporter;

function getTransporter() {
  if (!smtpConfigured()) {
    return null;
  }

  transporter ??= nodemailer.createTransport({
    host: env.smtp.host,
    port: env.smtp.port,
    secure: env.smtp.secure,
    auth: {
      user: env.smtp.user,
      pass: env.smtp.pass
    }
  });

  return transporter;
}

export async function sendVerificationEmail({ to, name, link }) {
  const mailer = getTransporter();

  if (!mailer) {
    logger.warn(
      'verification_email_not_sent',
      {
        appCode:
          'SMTP_NOT_CONFIGURED'
      }
    );

    return {
      sent: false,
      reason: 'SMTP_NOT_CONFIGURED'
    };
  }

  await mailer.sendMail({
    from: env.smtp.from,
    to,
    subject: 'Verify your Merzox account',
    text: [
      `Hello ${name},`,
      '',
      'Please verify your Merzox account by opening this link:',
      link,
      '',
      'This link expires in 24 hours.',
      '',
      'Merzox'
    ].join('\n'),
    html: `
      <div dir="ltr" style="font-family:Arial,sans-serif;line-height:1.6;color:#2b2b2b">
        <h2>Verify your Merzox account</h2>
        <p>Hello ${name},</p>
        <p>Please verify your account by clicking the button below.</p>
        <p>
          <a href="${link}" style="display:inline-block;background:#ee6c4d;color:#fff;padding:12px 18px;text-decoration:none;border-radius:4px">
            Verify email
          </a>
        </p>
        <p>If the button does not work, copy and paste this link into your browser:</p>
        <p><a href="${link}">${link}</a></p>
        <p>This link expires in 24 hours.</p>
      </div>
    `
  });

  return { sent: true };
}

export async function sendPasswordResetEmail({
  to,
  token,
  expiresInMinutes
}) {
  const mailer = getTransporter();

  if (!mailer) {
    logger.warn(
      'password_reset_email_not_sent',
      {
        appCode:
          'SMTP_NOT_CONFIGURED'
      }
    );

    // Deliberately do not log `to`, `token`, or a reset URL.
    return {
      sent: false,
      reason: 'SMTP_NOT_CONFIGURED'
    };
  }

  await mailer.sendMail({
    from: env.smtp.from,
    to,
    subject: 'Reset your Merzox password',
    text: [
      'A password reset was requested for your Merzox account.',
      '',
      'Enter this reset code in the Merzox application:',
      token,
      '',
      `This code expires in ${expiresInMinutes} minutes.`,
      '',
      'If you did not request this change, ignore this email.',
      '',
      'Merzox'
    ].join('\n'),
    html: `
      <div dir="ltr" style="font-family:Arial,sans-serif;line-height:1.6;color:#2b2b2b">
        <h2>Reset your Merzox password</h2>
        <p>A password reset was requested for your Merzox account.</p>
        <p>Enter this reset code in the Merzox application:</p>
        <p>
          <code style="display:inline-block;padding:10px;background:#f4f4f4;border-radius:4px">
            ${token}
          </code>
        </p>
        <p>This code expires in ${expiresInMinutes} minutes.</p>
        <p>If you did not request this change, ignore this email.</p>
      </div>
    `
  });

  return { sent: true };
}
