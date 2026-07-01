import { useEffect, useState } from "react";
import { getLiveWeight, classify, LiveWeight, BoardState } from "./aigoClient";

const POLL_MS = 1500;

function hhmmss(iso: string | null): string {
  return iso ? iso.slice(11, 19) : "--:--:--";
}

export default function LiveWeightBoard() {
  const [lw, setLw] = useState<LiveWeight | null>(null);
  const [err, setErr] = useState("");

  useEffect(() => {
    let alive = true;
    async function tick() {
      try { const r = await getLiveWeight(); if (alive) { setLw(r); setErr(""); } }
      catch (e: any) { if (alive) setErr(e.message || "讀取失敗"); }
    }
    tick();
    const h = setInterval(tick, POLL_MS);
    return () => { alive = false; clearInterval(h); };
  }, []);

  const state: BoardState = lw ? classify(lw) : "offline";
  const showErr = !!err;

  return (
    <div className="lwb-root">
      <h2 className="lwb-title">薪榮地磅 — 即時磅重</h2>
      {showErr && <div className="lwb-err">連線問題: {err}</div>}
      {state === "offline" && (
        <div className="lwb-offline">
          <div className="lwb-big">⚠️ 離線</div>
          <div className="lwb-sub">最後更新 {hhmmss(lw?.server_at ?? null)}</div>
        </div>
      )}
      {state === "idle" && (
        <div className="lwb-idle">
          <div className="lwb-big">0 <span className="lwb-unit">kg</span></div>
          <div className="lwb-sub">待命中 · 更新於 {hhmmss(lw?.server_at ?? null)}</div>
        </div>
      )}
      {state === "weighing" && (
        <div className="lwb-live">
          <div className="lwb-big">{(lw?.weight ?? 0).toLocaleString()} <span className="lwb-unit">kg</span></div>
          <div className="lwb-sub">更新於 {hhmmss(lw?.server_at ?? null)}</div>
        </div>
      )}
    </div>
  );
}
