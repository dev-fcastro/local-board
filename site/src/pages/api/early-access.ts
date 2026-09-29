import type { APIRoute } from "astro";
import { mailConfig, normalizeEmail, transport, welcomeEmail } from "../../lib/mail";

export const prerender = false;

// Best-effort per-instance throttle; serverless instances are short-lived,
// so this only blunts bursts. The honeypot + validation do the rest.
const hits = new Map<string, number[]>();
function limited(key: string, max = 5, windowMs = 10 * 60_000) {
  const now = Date.now();
  const recent = (hits.get(key) ?? []).filter((t) => now - t < windowMs);
  recent.push(now);
  hits.set(key, recent);
  return recent.length > max;
}

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });

export const POST: APIRoute = async ({ request, clientAddress, site }) => {
  let data: Record<string, unknown>;
  try {
    data = await request.json();
  } catch {
    return json(400, { ok: false, error: "Invalid request." });
  }

  // Honeypot: real people never fill the hidden "company" field.
  if (typeof data.company === "string" && data.company.length > 0) return json(200, { ok: true });

  const email = normalizeEmail(data.email);
  if (!email) return json(422, { ok: false, error: "Please enter a valid email address." });

  let ip = "unknown";
  try {
    ip = clientAddress;
  } catch {
    // not available in some runtimes
  }
  if (limited(ip)) return json(429, { ok: false, error: "Too many attempts. Please try again in a few minutes." });

  const config = mailConfig();
  if (!config) {
    console.error("early-access: SMTP is not configured (EMAIL_* env vars missing)");
    return json(503, { ok: false, error: "Sign-ups are temporarily unavailable. Please try again later." });
  }

  const siteUrl = (site?.toString() ?? new URL(request.url).origin).replace(/\/$/, "");
  const mailer = transport(config);
  try {
    const welcome = welcomeEmail(siteUrl);
    await mailer.sendMail({ from: config.from, to: email, ...welcome });
    if (config.notifyTo) {
      await mailer.sendMail({
        from: config.from,
        to: config.notifyTo,
        replyTo: email,
        subject: `Local Board early access: ${email}`,
        text: `New early-access sign-up\n\nEmail: ${email}\nWhen: ${new Date().toISOString()}\nUser agent: ${request.headers.get("user-agent") ?? "-"}`,
      });
    }
    return json(200, { ok: true });
  } catch (err) {
    console.error("early-access: send failed", err);
    return json(502, { ok: false, error: "We couldn't send the confirmation email. Please try again later." });
  } finally {
    mailer.close();
  }
};

export const ALL: APIRoute = () => json(405, { ok: false, error: "Method not allowed." });
