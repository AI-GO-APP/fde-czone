import { describe, it, expect, beforeEach } from "vitest";
import { buildActionUrl, unwrapEnvelope, mapRecord, classify, LiveWeight } from "./aigoClient";

beforeEach(() => {
  (globalThis as any).window = { __API_BASE__: "/api/v1", __APP_ID__: "APP1", __IS_EXTERNAL__: false };
});

describe("buildActionUrl", () => {
  it("內部 app", () => {
    expect(buildActionUrl("weigh")).toBe("/api/v1/actions/apps/APP1/run/weigh");
  });
  it("外部 app", () => {
    (globalThis as any).window.__IS_EXTERNAL__ = true;
    expect(buildActionUrl("weigh")).toBe("/api/v1/ext/actions/run/weigh");
  });
});

describe("unwrapEnvelope", () => {
  it("成功回 result", () => {
    expect(unwrapEnvelope({ status: "success", result: { a: 1 } })).toEqual({ a: 1 });
  });
  it("失敗丟錯", () => {
    expect(() => unwrapEnvelope({ status: "error", error: "壞了" })).toThrow("壞了");
  });
  it("無信封原樣回", () => {
    expect(unwrapEnvelope({ a: 1 })).toEqual({ a: 1 });
  });
});

describe("mapRecord", () => {
  it("二磅時間優先, null 處理", () => {
    const row = mapRecord({ id: "r1", data: {
      ticket_no: "20260622-002", plate: "KEP-2758", weigh_operator: "王小明",
      status: "done", gross_weight: 14.54, net_weight: 6.34,
      first_weigh_at: "2026-06-22T04:00:00", second_weigh_at: "2026-06-22T05:00:00" } });
    expect(row).toEqual({
      id: "r1", ticket_no: "20260622-002", plate: "KEP-2758", weigh_operator: "王小明",
      status: "done", gross_weight: 14.54, net_weight: 6.34, at: "2026-06-22T05:00:00",
      customer_name: "", material_name: "" });
  });
  it("一磅時 fallback first, 缺值補空/null", () => {
    const row = mapRecord({ id: "r2", data: { ticket_no: "20260622-003", plate: "ABC", first_weigh_at: "2026-06-22T06:00:00" } });
    expect(row.at).toBe("2026-06-22T06:00:00");
    expect(row.weigh_operator).toBe("");
    expect(row.net_weight).toBeNull();
  });

  describe("mapRecord 客戶/料種", () => {
    it("帶出 customer_name 與 material_name", () => {
      const row = mapRecord({ id: "1", data: { customer_name: "測試環保", material_name: "廢木料-棧板" } });
      expect(row.customer_name).toBe("測試環保");
      expect(row.material_name).toBe("廢木料-棧板");
    });
    it("缺欄位時回空字串", () => {
      const row = mapRecord({ id: "2", data: {} });
      expect(row.customer_name).toBe("");
      expect(row.material_name).toBe("");
    });
  });
});

describe("classify", () => {
  const base: LiveWeight = {
    weight: 4830, state: "weighing",
    at: "2026-07-01T14:03:13",
    server_at: "2026-07-01T14:03:14",
    server_now: "2026-07-01T14:03:15",
  };
  it("新鮮 + 有車 → weighing", () => {
    expect(classify(base)).toBe("weighing");
  });
  it("新鮮 + 重量 0 → idle", () => {
    expect(classify({ ...base, weight: 0, state: "idle" })).toBe("idle");
  });
  it("server_at 為 null → offline", () => {
    expect(classify({ ...base, server_at: null, weight: null })).toBe("offline");
  });
  it("超過 90 秒 → offline", () => {
    expect(classify({ ...base, server_at: "2026-07-01T14:00:00", server_now: "2026-07-01T14:01:31" })).toBe("offline");
  });
  it("剛好 90 秒 → 不算離線(idle/weighing)", () => {
    expect(classify({ ...base, server_at: "2026-07-01T14:00:00", server_now: "2026-07-01T14:01:30" })).toBe("weighing");
  });
});
