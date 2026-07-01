// aigo-app/vfs/src/App.tsx
import { useEffect, useState } from "react";
import { callAction, listWeighings, WeighingRow } from "./aigoClient";
import LiveWeightBoard from "./LiveWeightBoard";

export default function App() {
  const [view, setView] = useState<"board" | "form">("board");
  const [plate, setPlate] = useState("KEP-2758");
  const [weight, setWeight] = useState("14540");
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

  return (
    <div className="wp-root">
      <div className="wp-nav">
        <button className="wp-btn" onClick={() => setView("board")} disabled={view === "board"}>即時看板</button>
        <button className="wp-btn" onClick={() => setView("form")} disabled={view === "form"}>驗證輸入</button>
      </div>
      {view === "board" && <LiveWeightBoard />}
      {view === "form" && (
      <>
        <h2 className="wp-title">薪榮地磅 — 驗證輸入</h2>
      <div className="wp-grid">
        <label className="wp-field">車號<input value={plate} onChange={e => setPlate(e.target.value)} /></label>
        <label className="wp-field">重量(公斤)<input value={weight} onChange={e => setWeight(e.target.value)} /></label>
        <label className="wp-field">會磅員<input value={operator} onChange={e => setOperator(e.target.value)} /></label>
        <label className="wp-field">客戶名稱<input value={customer} onChange={e => setCustomer(e.target.value)} /></label>
        <label className="wp-field">料種<input value={material} onChange={e => setMaterial(e.target.value)} /></label>
      </div>
      <div className="wp-actions">
        <button onClick={submit} disabled={busy} className="wp-btn">{busy ? "處理中…" : "過磅"}</button>
        <span className="wp-msg">{msg}</span>
      </div>
      {payload && (
        <pre className="wp-payload">
          {JSON.stringify(payload, null, 2)}
        </pre>
      )}
      <h3 className="wp-subtitle">最近紀錄</h3>
      <table className="wp-table">
        <thead><tr>
          <th>單號</th><th>車號</th><th>客戶</th><th>料種</th>
          <th>會磅員</th><th>狀態</th><th>毛重</th><th>淨重</th><th>時間</th>
        </tr></thead>
        <tbody>
          {rows.map(r => (
            <tr key={r.id}>
              <td>{r.ticket_no}</td><td>{r.plate}</td>
              <td>{r.customer_name}</td><td>{r.material_name}</td>
              <td>{r.weigh_operator}</td><td>{r.status}</td>
              <td>{r.gross_weight ?? ""}</td><td>{r.net_weight ?? ""}</td><td>{r.at}</td>
            </tr>
          ))}
        </tbody>
      </table>
      </>
      )}
    </div>
  );
}
