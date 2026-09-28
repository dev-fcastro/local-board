// Generative line illustrations (480×360 viewBox, stroke = currentColor).

const f = (n: number) => Math.round(n * 10) / 10;
const svg = (body: string) =>
  `<svg viewBox="0 0 480 360" fill="none" stroke="currentColor" stroke-width="1" stroke-linecap="round" stroke-linejoin="round">${body}</svg>`;

export function network(): string {
  const cx = 240;
  const cy = 180;
  const rings = [
    { r: 48, n: 6, size: 5 },
    { r: 100, n: 10, size: 4 },
    { r: 150, n: 16, size: 3 },
  ];
  const points = rings.map(({ r, n }, ri) =>
    Array.from({ length: n }, (_, i) => {
      const a = (i / n) * Math.PI * 2 + ri * 0.35;
      return { x: cx + Math.cos(a) * r, y: cy + Math.sin(a) * r * 0.72 };
    }),
  );

  let body = "";
  points.forEach((ring, ri) => {
    ring.forEach((p, i) => {
      const next = ring[(i + 1) % ring.length];
      body += `<path d="M${f(p.x)} ${f(p.y)}L${f(next.x)} ${f(next.y)}" opacity=".35"/>`;
      const inner = ri === 0 ? [{ x: cx, y: cy }] : points[ri - 1];
      const nearest = inner.reduce((a, b) =>
        Math.hypot(b.x - p.x, b.y - p.y) < Math.hypot(a.x - p.x, a.y - p.y) ? b : a,
      );
      body += `<path d="M${f(p.x)} ${f(p.y)}L${f(nearest.x)} ${f(nearest.y)}"/>`;
    });
  });
  points.forEach((ring, ri) =>
    ring.forEach((p) => (body += `<circle cx="${f(p.x)}" cy="${f(p.y)}" r="${rings[ri].size}" fill="var(--card-bg, #fff)"/>`)),
  );
  body += `<circle cx="${cx}" cy="${cy}" r="9" fill="currentColor"/>`;
  return svg(body);
}

export function stack(): string {
  const cx = 240;
  const w = 150;
  const h = 75;
  let body = "";
  for (let i = 4; i >= 1; i--) {
    const y = 150 + i * 26;
    body += `<path d="M${cx - w} ${y}L${cx} ${y + h}L${cx + w} ${y}" opacity="${f(1 - i * 0.18)}"/>`;
  }
  const top = 150;
  body += `<path d="M${cx} ${top - h}L${cx + w} ${top}L${cx} ${top + h}L${cx - w} ${top}Z" fill="var(--card-bg, #fff)"/>`;
  for (let u = 1; u < 10; u++) {
    for (let v = 1; v < 10; v++) {
      const x = cx + (u - v) * (w / 10);
      const y = top - h + (u + v) * (h / 10);
      body += `<circle cx="${f(x)}" cy="${f(y)}" r=".9" fill="currentColor" stroke="none"/>`;
    }
  }
  body += `<path d="M${cx - 80} ${top}L${cx - 20} ${top - 34}L${cx + 58} ${top + 12}" stroke-width="2.5"/>`;
  body += `<circle cx="${cx + 58}" cy="${top + 12}" r="6" fill="currentColor"/>`;
  return svg(body);
}

export function rings(): string {
  const cx = 240;
  const cy = 180;
  let body = "";
  for (let i = 0; i < 9; i++) {
    const r = 24 + i * 17;
    const dash = i < 4 ? "" : ` stroke-dasharray="${f(1 + (i - 3) * 1.2)} ${f(3 + (i - 3) * 3)}"`;
    body += `<circle cx="${cx}" cy="${cy}" r="${r}"${dash} opacity="${f(1 - i * 0.07)}"/>`;
  }
  const marks = [
    { r: 58, a: -0.6 },
    { r: 92, a: 2.2 },
    { r: 75, a: 3.9 },
    { r: 126, a: 0.9 },
  ];
  marks.forEach(({ r, a }) => {
    const x = cx + Math.cos(a) * r;
    const y = cy + Math.sin(a) * r;
    body += `<rect x="${f(x - 7)}" y="${f(y - 7)}" width="14" height="14" fill="var(--card-bg, #fff)"/>`;
  });
  body += `<circle cx="${cx}" cy="${cy}" r="8" fill="currentColor"/>`;
  return svg(body);
}

export function contours(): string {
  let body = "";
  const levels = 9;
  for (let k = 0; k < levels; k++) {
    const base = 22 + k * 17;
    const cx = 250 - k * 3;
    const cy = 186 + k * 2;
    const steps = 96;
    let d = "";
    for (let s = 0; s <= steps; s++) {
      const t = (s / steps) * Math.PI * 2;
      const r = base * (1 + 0.13 * Math.sin(3 * t + k * 0.4) + 0.07 * Math.sin(5 * t + k));
      const x = cx + Math.cos(t) * r * 1.25;
      const y = cy + Math.sin(t) * r * 0.78;
      d += `${s === 0 ? "M" : "L"}${f(x)} ${f(y)}`;
    }
    body += `<path d="${d}Z" opacity="${f(1 - k * 0.07)}"/>`;
  }
  body += `<path d="M250 190c0-26-14-40-30-40s-30 14-30 40c0 22 30 54 30 54s30-32 30-54Z" transform="translate(30 -64)" fill="var(--card-bg, #fff)" stroke-width="1.5"/>`;
  body += `<circle cx="250" cy="122" r="9" fill="currentColor"/>`;
  return svg(body);
}
