import path from "node:path";
import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
      "@backend": path.resolve(__dirname, "../../backend/src"),
    },
  },
  // PORT/HOST set by portless when running via `bun run --filter` (portless
  // can't auto-inject --port because it sees `bun`, not `vite`)
  server: {
    port: Number(process.env.PORT) || 5173,
    host: process.env.HOST || "localhost",
  },
});
