// vfs/src/main.tsx
import { createRoot } from "react-dom/client";
import App from "./App";

// 平台發布的頁面外殼不一定有 #root, 找不到就自己建一個再掛載。
let container = document.getElementById("root");
if (!container) {
  container = document.createElement("div");
  container.id = "root";
  document.body.appendChild(container);
}
createRoot(container).render(<App />);
