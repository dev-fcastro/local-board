// Cookie consent state. Any future analytics script must check readConsent()
// or listen for the "lb:consent" event before loading.

export interface Consent {
  v: 1;
  necessary: true;
  analytics: boolean;
  at: string;
}

const KEY = "lb-consent";

export function readConsent(): Consent | null {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Consent;
    return parsed?.v === 1 ? parsed : null;
  } catch {
    return null;
  }
}

export function writeConsent(analytics: boolean): Consent {
  const consent: Consent = { v: 1, necessary: true, analytics, at: new Date().toISOString() };
  try {
    localStorage.setItem(KEY, JSON.stringify(consent));
  } catch {
    // storage blocked: the choice still applies for this page view
  }
  window.dispatchEvent(new CustomEvent<Consent>("lb:consent", { detail: consent }));
  return consent;
}
