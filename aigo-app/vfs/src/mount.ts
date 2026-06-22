// vfs/src/mount.ts
// 解析 React 掛載容器。
//
// 平台 runtime 不會使用本 app 的 index.html, 而是把 app 掛進它「注入」的容器,
// 並以 window.__CUSTOM_APP_ROOT__ 指向該容器 (對齊 fde-echouse / jhtravel / sc1984
// 三個既有 aigo app 的一致寫法)。本機 dev 才退回 index.html 的 #root。
//
// 平台外層容器為 height:100vh; overflow:hidden, 故掛載點需自撐滿高並自行捲動,
// 否則內容會被擠到頁尾、看似白畫面。
type WinWithRoot = Window & { __CUSTOM_APP_ROOT__?: HTMLElement };

export function resolveMountPoint(
  win: WinWithRoot = window,
  doc: Document = document
): HTMLElement | null {
  const el = win.__CUSTOM_APP_ROOT__ ?? doc.getElementById("root");
  if (el) {
    el.style.height = "100%";
    el.style.overflowY = "auto";
  }
  return el;
}
