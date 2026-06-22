import { describe, it, expect } from "vitest";
import { resolveMountPoint } from "./mount";

// 沿用本專案 mock global 的測試風格 (不引入 jsdom), 用最小 fake 物件驗證掛載契約。
const el = (id: string) => ({ id, style: {} as any });

describe("resolveMountPoint", () => {
  it("平台注入 window.__CUSTOM_APP_ROOT__ 時優先用它 (對齊 echouse/jhtravel/sc1984)", () => {
    const platform = el("platform");
    const win = { __CUSTOM_APP_ROOT__: platform } as any;
    const doc = { getElementById: () => el("root") } as any;
    expect(resolveMountPoint(win, doc)?.id).toBe("platform");
  });

  it("無平台變數時退回 index.html 的 #root (本機 dev)", () => {
    const root = el("root");
    const win = {} as any;
    const doc = { getElementById: (id: string) => (id === "root" ? root : null) } as any;
    expect(resolveMountPoint(win, doc)?.id).toBe("root");
  });

  it("掛載容器設為滿高可捲動 (對應平台外層 100vh overflow:hidden, 否則內容被擠到頁尾)", () => {
    const platform = el("platform");
    resolveMountPoint({ __CUSTOM_APP_ROOT__: platform } as any, {} as any);
    expect(platform.style.height).toBe("100%");
    expect(platform.style.overflowY).toBe("auto");
  });

  it("兩者皆無時回 null (讓 main.tsx fail loud, 不再自建 div 掛到 body 外)", () => {
    const doc = { getElementById: () => null } as any;
    expect(resolveMountPoint({} as any, doc)).toBeNull();
  });
});
