import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { viteSingleFile } from "vite-plugin-singlefile";

export default defineConfig({
  plugins: [react(), tailwindcss(), viteSingleFile()],
  build: {
    target: "safari17",
    assetsInlineLimit: 100000000,
    cssCodeSplit: false,
    minify: true,
    sourcemap: false,
    outDir: "dist",
    emptyOutDir: true,
  },
});
