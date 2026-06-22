// vfs/src/main.tsx
import { createRoot } from "react-dom/client";
import App from "./App";
import { resolveMountPoint } from "./mount";

// 掛載點由平台 runtime 以 window.__CUSTOM_APP_ROOT__ 注入, 本機 dev 退回 #root。
// 舊版「找不到 #root 就自建 div append 到 body」會掛到平台容器外,
// 導致線上白畫面 / 內容被擠到頁尾, 已移除。
const rootEl = resolveMountPoint();
if (!rootEl) {
  throw new Error("找不到掛載點: window.__CUSTOM_APP_ROOT__ 與 #root 皆不存在");
}
createRoot(rootEl).render(<App />);
