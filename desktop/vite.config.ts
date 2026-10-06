import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
// @ts-expect-error 준비된 프로젝트에는 @types/node가 없다.
import fs from "node:fs";
import type { Plugin } from "vite";

// 설치된 pdfjs 자산만 사용. CJK CMap/표준 폰트/이미지 디코더도 오프라인 제공.
function pdfAssets(): Plugin {
  const directories = ["cmaps", "standard_fonts", "wasm", "iccs"];
  const source = (file: string) => new URL(`./node_modules/pdfjs-dist/${file}`, import.meta.url);
  return {
    name: "vnote-pdf-assets",
    generateBundle() {
      for (const directory of directories) {
        for (const file of fs.readdirSync(source(directory + "/"))) {
          const url = source(`${directory}/${file}`);
          if (fs.statSync(url).isFile()) this.emitFile({ type: "asset", fileName: `pdfjs/${directory}/${file}`, source: fs.readFileSync(url) });
        }
      }
    },
    configureServer(server) {
      server.middlewares.use("/pdfjs", (request, response, next) => {
        const path = request.url?.split("?")[0] || "";
        if (!/^\/(cmaps|standard_fonts|wasm|iccs)\/[A-Za-z0-9_.-]+$/.test(path)) return next();
        response.setHeader("Content-Type", path.endsWith(".wasm") ? "application/wasm" : path.endsWith(".js") ? "application/javascript" : "application/octet-stream");
        fs.createReadStream(source(path.slice(1))).on("error", () => { response.statusCode = 404; response.end(); }).pipe(response);
      });
    }
  };
}
// @ts-expect-error type error without @types/node package
import process from "node:process";
const host = process.env.TAURI_DEV_HOST;

// https://vite.dev/config/
export default defineConfig(() => ({
  plugins: [react(), pdfAssets()],

  // Vite options tailored for Tauri development and only applied in `tauri dev` or `tauri build`
  //
  // 1. prevent Vite from obscuring rust errors
  clearScreen: false,
  // 2. tauri expects a fixed port, fail if that port is not available
  server: {
    port: 1420,
    strictPort: true,
    host: host || false,
    hmr: host
      ? {
          protocol: "ws",
          host,
          port: 1421,
        }
      : undefined,
    watch: {
      // 3. tell Vite to ignore watching `src-tauri`
      ignored: ["**/src-tauri/**"],
    },
  },
}));
