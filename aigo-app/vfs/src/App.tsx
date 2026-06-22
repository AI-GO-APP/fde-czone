// aigo-app/vfs/src/App.tsx
import { useEffect, useState } from "react";
import { callAction, listWeighings, WeighingRow } from "./aigoClient";

export default function App() {
  const [plate, setPlate] = useState("KEP-2758");
  const [weight, setWeight] = useState("14.54");
  const [operator, setOperator] = useState("王小明");
  const [customer, setCustomer] = useState("測試環保");
  const [material, setMaterial] = useState("一般事業廢棄物");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState("");
  const [payload, setPayload] = useState<any>(null);
  const [rows, setRows] = useState<WeighingRow[]>([]);

  async function refresh() {
    try { setRows(await listWeighings()); }
    catch (e: any) { setMsg("讀取紀錄失敗: " + e.message); }
  }
  useEffect(() => { refresh(); }, []);

  async function submit() {
    setBusy(true); setMsg(""); setPayload(null);
    try {
      const r = await callAction("weigh", {
        plate, weight: parseFloat(weight), weigh_operator: operator,
        customer, material,
        plate_source: "manual", weight_source: "manual",
      });
      setPayload(r.print_payload);
      setMsg("成功: " + r.ticket_no + " (" + (r.event === "second" ? "二磅" : "一磅") + ")"
        + (r.needs_manual && r.needs_manual.length ? "  需補: " + r.needs_manual.join(",") : ""));
      await refresh();
    } catch (e: any) { setMsg("過磅失敗: " + e.message); }
    finally { setBusy(false); }
  }

  const cell: any = { border: "1px solid #ccc", padding: 6 };
  const inp: any = { width: "100%" };
  return (
    <div style={{ fontFamily: '"微軟正黑體", "Microsoft JhengHei", sans-serif', padding: 24, maxWidth: 860, margin: "0 auto" }}>
      <h2>薪榮地磅 — 驗證輸入</h2>
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 12 }}>
        <label>車號<input value={plate} onChange={e => setPlate(e.target.value)} style={inp} /></label>
        <label>重量(公噸)<input value={weight} onChange={e => setWeight(e.target.value)} style={inp} /></label>
        <label>會磅員<input value={operator} onChange={e => setOperator(e.target.value)} style={inp} /></label>
        <label>客戶名稱<input value={customer} onChange={e => setCustomer(e.target.value)} style={inp} /></label>
        <label>料種<input value={material} onChange={e => setMaterial(e.target.value)} style={inp} /></label>
      </div>
      <div style={{ marginTop: 12 }}>
        <button onClick={submit} disabled={busy} style={{ padding: "8px 18px" }}>{busy ? "處理中…" : "過磅"}</button>
        <span style={{ marginLeft: 12 }}>{msg}</span>
      </div>
      {payload && (
        <pre style={{ background: "#f4f6f8", padding: 12, marginTop: 12, whiteSpace: "pre-wrap" }}>
          {JSON.stringify(payload, null, 2)}
        </pre>
      )}
      <h3 style={{ marginTop: 24 }}>最近紀錄</h3>
      <table style={{ borderCollapse: "collapse", width: "100%" }}>
        <thead><tr>
          <th style={cell}>單號</th><th style={cell}>車號</th><th style={cell}>客戶</th><th style={cell}>料種</th>
          <th style={cell}>會磅員</th><th style={cell}>狀態</th><th style={cell}>毛重</th><th style={cell}>淨重</th><th style={cell}>時間</th>
        </tr></thead>
        <tbody>
          {rows.map(r => (
            <tr key={r.id}>
              <td style={cell}>{r.ticket_no}</td><td style={cell}>{r.plate}</td>
              <td style={cell}>{r.customer_name}</td><td style={cell}>{r.material_name}</td>
              <td style={cell}>{r.weigh_operator}</td><td style={cell}>{r.status}</td>
              <td style={cell}>{r.gross_weight ?? ""}</td><td style={cell}>{r.net_weight ?? ""}</td><td style={cell}>{r.at}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
