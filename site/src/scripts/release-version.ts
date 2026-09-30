// Pages are static, so the version they were built with can lag behind a new
// release. Elements marked data-release-version="<built version>" get the
// latest one from /api/latest-release (cached at the edge).
const marked = document.querySelectorAll<HTMLElement>("[data-release-version]");

if (marked.length > 0) {
  fetch("/api/latest-release")
    .then((res) => (res.ok ? res.json() : null))
    .then((data: { version?: unknown } | null) => {
      const latest = data?.version;
      if (typeof latest !== "string" || !/^v\d+\.\d+\.\d+$/.test(latest)) return;
      for (const el of marked) {
        const built = el.dataset.releaseVersion;
        if (!built || built === latest) continue;
        const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
          if (node.nodeValue?.includes(built)) node.nodeValue = node.nodeValue.replaceAll(built, latest);
        }
        el.dataset.releaseVersion = latest;
      }
    })
    .catch(() => {
      // Keep the built version.
    });
}
