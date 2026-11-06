import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "astro/config";

export default defineConfig({
  site: "https://dayline.robin.build",
  output: "static",
  build: { format: "file" },
  vite: {
    plugins: [tailwindcss()],
  },
});
