// aigo-app/vfs/src/aigoClient.ts
// 與 aigo 平台後端溝通的薄層 (模式 A): 平台注入的 window 全域 + fetch。

function apiBase(): string { return (window as any).__API_BASE__ || "/api/v1"; }
function appId(): string { return (window as any).__APP_ID__ || ""; }
function headers(): Record<string, string> {
  const h: Record<string, string> = { "Content-Type": "application/json" };
  const t = (window as any).__APP_TOKEN__ || "";
  if (t) h["Authorization"] = "Bearer " + t;
  return h;
}

// 內部 app: /actions/apps/{app_id}/run/{name} (此 app 後端已實測可用)
// 外部 app: /ext/actions/run/{name}
export function buildActionUrl(name: string): string {
  const isExternal = !!(window as any).__IS_EXTERNAL__;
  return isExternal
    ? apiBase() + "/ext/actions/run/" + name
    : apiBase() + "/actions/apps/" + appId() + "/run/" + name;
}

// action 回信封 {status, result, error}: 成功回 result, 否則丟錯。
export function unwrapEnvelope(env: any): any {
  if (env && env.status && env.status !== "success") {
    throw new Error(env.error || "action 失敗");
  }
  return env && Object.prototype.hasOwnProperty.call(env, "result") ? env.result : env;
}

export async function callAction(name: string, params: Record<string, any> = {}): Promise<any> {
  const resp = await fetch(buildActionUrl(name), {
    method: "POST", headers: headers(), credentials: "include",
    body: JSON.stringify({ params }),
  });
  if (!resp.ok) throw new Error("HTTP " + resp.status);
  return unwrapEnvelope(await resp.json());
}

const _idCache: Record<string, string> = {};
export async function getObjectId(slug: string): Promise<string> {
  if (_idCache[slug]) return _idCache[slug];
  const resp = await fetch(apiBase() + "/data/objects", { headers: headers(), credentials: "include" });
  if (!resp.ok) throw new Error("HTTP " + resp.status);
  const objs = await resp.json();
  const list = Array.isArray(objs) ? objs : [];
  for (const o of list) { if (o.api_slug === slug) { _idCache[slug] = o.id; return o.id; } }
  throw new Error("找不到資料表 " + slug);
}

export interface WeighingRow {
  id: string; ticket_no: string; plate: string; weigh_operator: string;
  status: string; gross_weight: number | null; net_weight: number | null; at: string;
  customer_name: string; material_name: string;
}

export function mapRecord(raw: any): WeighingRow {
  const d = (raw && raw.data) || {};
  return {
    id: raw ? raw.id : "",
    ticket_no: d.ticket_no || "",
    plate: d.plate || "",
    weigh_operator: d.weigh_operator || "",
    status: d.status || "",
    gross_weight: d.gross_weight === undefined ? null : d.gross_weight,
    net_weight: d.net_weight === undefined ? null : d.net_weight,
    at: d.second_weigh_at || d.first_weigh_at || "",
    customer_name: d.customer_name || "",
    material_name: d.material_name || "",
  };
}

export async function listWeighings(): Promise<WeighingRow[]> {
  const oid = await getObjectId("x_czone_weighing");
  const resp = await fetch(apiBase() + "/data/objects/" + oid + "/records", { headers: headers(), credentials: "include" });
  if (!resp.ok) throw new Error("HTTP " + resp.status);
  const rows = await resp.json();
  const arr = Array.isArray(rows) ? rows : [];
  const out = arr.map(mapRecord);
  out.sort((a, b) => (b.at || "").localeCompare(a.at || "")); // 新到舊
  return out;
}

export interface LiveWeight {
  weight: number | null;
  state: string;
  at: string | null;
  server_at: string | null;
  server_now: string;
}

export async function getLiveWeight(): Promise<LiveWeight> {
  return await callAction("get_live_weight", {});
}

export type BoardState = "offline" | "weighing" | "idle";

// 新鮮度只用伺服器時間(server_now - server_at)。ISO 無時區也沒關係:
// 兩個時間同格式相減，時區解讀會互相抵銷。
export function classify(lw: LiveWeight, staleSec = 90): BoardState {
  if (!lw || !lw.server_at) return "offline";
  const ageSec = (Date.parse(lw.server_now) - Date.parse(lw.server_at)) / 1000;
  if (isNaN(ageSec) || ageSec > staleSec) return "offline";
  if (lw.state === "weighing" && !!lw.weight && lw.weight !== 0) return "weighing";
  return "idle";
}
