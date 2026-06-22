import { describe, it, expect, beforeEach } from "vitest";
import { buildActionUrl, unwrapEnvelope, mapRecord } from "./aigoClient";

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
      status: "done", gross_weight: 14.54, net_weight: 6.34, at: "2026-06-22T05:00:00" });
  });
  it("一磅時 fallback first, 缺值補空/null", () => {
    const row = mapRecord({ id: "r2", data: { ticket_no: "20260622-003", plate: "ABC", first_weigh_at: "2026-06-22T06:00:00" } });
    expect(row.at).toBe("2026-06-22T06:00:00");
    expect(row.weigh_operator).toBe("");
    expect(row.net_weight).toBeNull();
  });
});
