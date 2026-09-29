import nodemailer from "nodemailer";

export interface MailConfig {
  host: string;
  port: number;
  secure: boolean;
  requireTLS: boolean;
  user: string;
  pass: string;
  from: string;
  notifyTo?: string;
}

type Env = Record<string, string | undefined>;

/** Reads Django-style EMAIL_* variables. Returns null when SMTP is not configured. */
export function mailConfig(env: Env = process.env): MailConfig | null {
  const host = env.EMAIL_HOST;
  const user = env.EMAIL_HOST_USER;
  const pass = env.EMAIL_HOST_PASSWORD;
  if (!host || !user || !pass) return null;
  const port = Number(env.EMAIL_PORT ?? 587);
  const tls = /^(1|true|yes)$/i.test(env.EMAIL_USE_TLS ?? "true");
  return {
    host,
    port,
    secure: port === 465, // implicit TLS; 587 upgrades with STARTTLS
    requireTLS: tls && port !== 465,
    user,
    pass,
    from: env.DEFAULT_FROM_EMAIL || user,
    notifyTo: env.EARLY_ACCESS_NOTIFY_TO || undefined,
  };
}

export function transport(c: MailConfig) {
  return nodemailer.createTransport({
    host: c.host,
    port: c.port,
    secure: c.secure,
    requireTLS: c.requireTLS,
    auth: { user: c.user, pass: c.pass },
    connectionTimeout: 10_000,
    greetingTimeout: 10_000,
    socketTimeout: 15_000,
  });
}

const EMAIL_RE = /^[^\s@<>()[\]\\,;:"]+@[^\s@<>()[\]\\,;:"]+\.[a-z]{2,}$/i;

export function normalizeEmail(input: unknown): string | null {
  if (typeof input !== "string") return null;
  const email = input.trim().toLowerCase();
  if (email.length > 254 || !EMAIL_RE.test(email)) return null;
  return email;
}

const esc = (s: string) =>
  s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

export function welcomeEmail(siteUrl: string) {
  const subject = "You're on the Local Board early-access list";
  const text = [
    "Thanks for joining Local Board early access.",
    "",
    "Local Board v0.1 is out for Linux. Install it with:",
    `  curl -fsSL ${siteUrl}/install.sh | sh`,
    "",
    "Windows and macOS versions are not available yet — we'll write when they are.",
    "",
    "Your boards stay on your computer. No account needed.",
    "",
    `${siteUrl}`,
    "",
    "You got this email because this address was entered on the Local Board website.",
    "If that wasn't you, ignore it and you won't hear from us again.",
  ].join("\n");
  const html = `<!doctype html><html><body style="margin:0;background:#faf9f9;font-family:system-ui,-apple-system,Segoe UI,sans-serif;color:#17181a">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:40px 16px">
<table role="presentation" width="560" cellpadding="0" cellspacing="0" style="max-width:560px;background:#fff;border:1px solid #e6e5e1;border-radius:10px">
<tr><td style="padding:32px 32px 8px"><p style="margin:0;font-size:13px;letter-spacing:.08em;text-transform:uppercase;color:#4f46e5">Local Board · Early access</p>
<h1 style="margin:12px 0 0;font-size:26px;line-height:1.2;font-weight:600">You're on the list.</h1></td></tr>
<tr><td style="padding:16px 32px;font-size:15px;line-height:1.6;color:#55585e">
<p style="margin:0 0 16px">Local Board v0.1 is out for <strong style="color:#17181a">Linux</strong>. Install it with one command:</p>
<pre style="margin:0 0 16px;padding:14px 16px;background:#17181a;color:#faf9f9;border-radius:8px;font-size:13px;white-space:pre-wrap;word-break:break-all">curl -fsSL ${esc(siteUrl)}/install.sh | sh</pre>
<p style="margin:0 0 16px">Windows and macOS versions are not available yet — we'll write when they are.</p>
<p style="margin:0">Your boards stay on your computer. No account needed.</p></td></tr>
<tr><td style="padding:8px 32px 32px"><a href="${esc(siteUrl)}/download" style="display:inline-block;padding:12px 22px;border-radius:999px;background:#17181a;color:#fff;text-decoration:none;font-size:14px">Download Local Board</a></td></tr>
</table>
<p style="max-width:560px;margin:16px auto 0;font-size:12px;line-height:1.5;color:#8a8d93">You got this email because this address was entered on the Local Board website. If that wasn't you, ignore it and you won't hear from us again.</p>
</td></tr></table></body></html>`;
  return { subject, text, html };
}
