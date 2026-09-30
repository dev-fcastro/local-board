import type { APIRoute } from "astro";
import { latestRelease } from "../../data/downloads";

export const prerender = false;

// The newest published version, so pages built before a release still show
// it. Cached at the edge for 10 minutes; visitors never call GitHub directly.
export const GET: APIRoute = async () => {
  const version = await latestRelease();
  return new Response(JSON.stringify({ version }), {
    headers: {
      "content-type": "application/json",
      "cache-control": "public, max-age=300, s-maxage=600, stale-while-revalidate=86400",
    },
  });
};
