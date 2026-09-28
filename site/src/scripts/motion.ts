import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";

declare global {
  interface Window {
    __motionReady?: boolean;
  }
}

const root = document.documentElement;

if (root.classList.contains("js-motion")) {
  window.__motionReady = true;
  gsap.registerPlugin(ScrollTrigger);

  const ease = "expo.out";
  const start = "top 90%";

  // Elements already on screen at load (including sticky ones that never
  // cross a trigger line) play immediately instead of waiting for scroll.
  const onScreen = (el: Element) => el.getBoundingClientRect().top < window.innerHeight;
  const trigger = (el: Element) =>
    onScreen(el) ? undefined : { trigger: el, start, once: true };

  gsap.utils.toArray<HTMLElement>("[data-rise]").forEach((el) => {
    gsap.to(el.querySelectorAll(":scope > span > span"), {
      y: 0,
      duration: 1.3,
      ease,
      stagger: 0.09,
      delay: onScreen(el) ? 0.2 : 0,
      scrollTrigger: trigger(el),
    });
  });

  gsap.utils.toArray<HTMLElement>("[data-mask]").forEach((el) => {
    gsap.to(el, {
      clipPath: "inset(0% 0 0 0)",
      duration: 1.2,
      ease,
      delay: Number(el.dataset.maskDelay ?? 0),
      scrollTrigger: trigger(el),
    });
  });

  const batch = (selector: string, vars: gsap.TweenVars, stagger: number) => {
    const els = gsap.utils.toArray<HTMLElement>(selector);
    const now = els.filter(onScreen);
    if (now.length) gsap.to(now, { ...vars, stagger, delay: 0.35 });
    const later = els.filter((el) => !now.includes(el));
    if (later.length) {
      ScrollTrigger.batch(later, {
        start,
        once: true,
        onEnter: (group) => gsap.to(group, { ...vars, stagger }),
      });
    }
  };

  batch("[data-reveal]", { opacity: 1, y: 0, duration: 1, ease }, 0.07);
  batch("[data-line]", { scaleX: 1, scaleY: 1, duration: 1.4, ease }, 0.04);

  window.addEventListener("load", () => ScrollTrigger.refresh());
}
