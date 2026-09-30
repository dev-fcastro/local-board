// @ts-check
import { defineConfig } from "astro/config";
import vercel from "@astrojs/vercel";

// Pages stay static; only /api/* routes (prerender = false) run as
// serverless functions on Vercel.
export default defineConfig({
  site: "https://localboards.vercel.app",
  output: "static",
  adapter: vercel(),
});
