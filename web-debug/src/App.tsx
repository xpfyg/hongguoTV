/**
 * 红果 TV · Web 调试器
 *
 * 复用 RN 工程的纯 TS 数据层（src/domain + src/data/provider + src/data/useCatalog），
 * 用浏览器原生 React DOM 渲染，连接内容服务调试接口/数据链路，无需编译原生 App。
 * 注意：token 鉴权时 <video> 无法携带自定义请求头，播放采用 fetch→Blob URL。
 */
import React, { useEffect, useMemo, useRef, useState } from "react";
import { BridgeProvider } from "../../src/data/provider";
import { useCatalog } from "../../src/data/useCatalog";
import { Detail, Series, normalizeBaseUrl } from "../../src/domain/model";

const styles: Record<string, React.CSSProperties> = {
  root: { minHeight: "100vh", padding: 24, boxSizing: "border-box", maxWidth: 1280, margin: "0 auto" },
  header: { display: "flex", gap: 12, alignItems: "center", flexWrap: "wrap" },
  brand: { fontSize: 24, fontWeight: 800, color: "#FF6B4A", marginRight: 8 },
  input: { flex: 1, minWidth: 260, padding: "10px 14px", fontSize: 15, borderRadius: 10, border: "1px solid #333", background: "#111", color: "#fff" },
  btn: { padding: "10px 18px", borderRadius: 12, border: "1px solid #333", background: "#1a1a1f", color: "#fff", fontSize: 15, cursor: "pointer" },
  btnPrimary: { background: "#FF6B4A", borderColor: "#FF6B4A", color: "#000" },
  tabs: { display: "flex", gap: 10, margin: "16px 0" },
  grid: { display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(180px, 1fr))", gap: 16 },
  card: { cursor: "pointer", borderRadius: 14, overflow: "hidden", border: "2px solid transparent", background: "#111", outline: "none" },
  cardFocus: { borderColor: "#fff", transform: "scale(1.05)", boxShadow: "0 10px 30px rgba(0,0,0,.6)" },
  cover: { width: "100%", aspectRatio: "2/3", objectFit: "cover", background: "#222" },
  badge: { position: "absolute" as const, bottom: 0, left: 0, right: 0, padding: "6px 8px", background: "rgba(0,0,0,.7)", fontSize: 13 },
  title: { padding: "8px 10px 12px", fontSize: 15, fontWeight: 600, lineHeight: "22px" },
  muted: { color: "#9B9BA8" },
  detail: { display: "flex", gap: 28, marginTop: 8 },
  poster: { width: 220, borderRadius: 14 },
  eps: { display: "flex", flexWrap: "wrap", gap: 10, marginTop: 16 },
  ep: { width: 56, padding: "10px 0", textAlign: "center" as const, borderRadius: 10, border: "1px solid #333", background: "#16161a", cursor: "pointer", outline: "none" },
  epFocus: { borderColor: "#fff", background: "#fff", color: "#000" },
  epNow: { borderColor: "#FF6B4A", color: "#FF6B4A" },
  player: { width: "100%", aspectRatio: "16/9", background: "#000", borderRadius: 12 },
  status: { fontSize: 14, color: "#9B9BA8" },
};

type View = { kind: "list" } | { kind: "detail"; id: string } | { kind: "play"; detail: Detail; index: number };

export default function App() {
  const [baseUrl, setBaseUrl] = useState("http://localhost:8787");
  const [token, setToken] = useState("");
  const [connected, setConnected] = useState<string>();
  const [checking, setChecking] = useState(false);
  const [tab, setTab] = useState<"推荐" | "搜索">("推荐");
  const [query, setQuery] = useState("");
  const [submitted, setSubmitted] = useState("");
  const [searchRun, setSearchRun] = useState(0);
  const [view, setView] = useState<View>({ kind: "list" });
  const [detail, setDetail] = useState<Detail>();
  const [detailBusy, setDetailBusy] = useState(false);
  const [detailError, setDetailError] = useState("");
  const [playing, setPlaying] = useState<{ detail: Detail; index: number; uri: string }>();
  const [playingBusy, setPlayingBusy] = useState(false);
  const [playingError, setPlayingError] = useState("");
  const gridRef = useRef<HTMLDivElement>(null);

  const provider = useMemo(() => new BridgeProvider({ baseUrl, token }), [baseUrl, token]);
  const catalog = useCatalog(provider, tab === "搜索" ? submitted : null, !!connected);

  async function connect() {
    setChecking(true);
    try {
      const next = normalizeBaseUrl(baseUrl);
      await new BridgeProvider({ baseUrl: next, token }).health();
      setBaseUrl(next);
      setConnected(next);
    } catch (e) {
      setConnected(undefined);
      alert(e instanceof Error ? e.message : "连接失败");
    } finally {
      setChecking(false);
    }
  }

  function open(item: Series) {
    setDetail(undefined);
    setDetailError("");
    setDetailBusy(true);
    provider
      .detail(item.id)
      .then(setDetail)
      .catch((e) => setDetailError(e instanceof Error ? e.message : "加载失败"))
      .finally(() => setDetailBusy(false));
    setView({ kind: "detail", id: item.id });
  }

  async function playEpisode(detailArg: Detail, index: number) {
    setPlayingBusy(true);
    setPlayingError("");
    try {
      const ep = detailArg.episodes[index];
      const res = await provider.resolve(ep.id);
      let uri = res.uri;
      if (token.trim()) {
        const r = await fetch(res.uri, { headers: { Authorization: `Bearer ${token.trim()}` } });
        if (!r.ok) throw new Error(`拉流失败 ${r.status}`);
        uri = URL.createObjectURL(await r.blob());
      }
      setPlaying({ detail: detailArg, index, uri });
    } catch (e) {
      setPlayingError(e instanceof Error ? e.message : "播放失败");
    } finally {
      setPlayingBusy(false);
    }
  }

  // 键盘焦点模拟（方向键在网格内移动，Enter 打开）
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (view.kind !== "list") return;
      const focus = document.activeElement as HTMLElement | null;
      if (focus && focus.dataset && focus.dataset.role === "grid-item") {
        if (["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(e.key)) {
          e.preventDefault();
          const cells = Array.from(document.querySelectorAll<HTMLElement>("[data-role='grid-item']"));
          const idx = cells.indexOf(focus as HTMLElement);
          if (idx < 0) return;
          const cols = Math.max(1, Math.round(Math.sqrt(cells.length)));
          const map: Record<string, number> = {
            ArrowRight: idx + 1,
            ArrowLeft: idx - 1,
            ArrowDown: idx + cols,
            ArrowUp: idx - cols,
          };
          const next = Math.max(0, Math.min(cells.length - 1, map[e.key]));
          cells[next]?.focus();
        }
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [view]);

  const items = catalog.items;

  return (
    <div style={styles.root}>
      <div style={styles.header}>
        <span style={styles.brand}>红果 TV</span>
        <input style={styles.input} value={baseUrl} onChange={(e) => setBaseUrl(e.target.value)} placeholder="http://localhost:8787" />
        <input style={{ ...styles.input, minWidth: 140, flex: "0 0 auto" }} value={token} onChange={(e) => setToken(e.target.value)} placeholder="访问口令（可选）" />
        <button style={{ ...styles.btn, ...styles.btnPrimary }} onClick={connect} disabled={checking}>
          {checking ? "连接中…" : connected ? "重新连接" : "连接"}
        </button>
        <span style={styles.status}>{connected ? `已连接 ${connected}` : "未连接"}</span>
      </div>

      {view.kind === "play" && playing ? (
        <div style={{ marginTop: 16 }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 12 }}>
            <span style={{ fontSize: 18, fontWeight: 700 }}>{playing.detail.title} · 第{playing.detail.episodes[playing.index].number}集</span>
            <button style={styles.btn} onClick={() => setView({ kind: "detail", id: playing.detail.id })}>返回详情</button>
          </div>
          <video key={playing.uri} src={playing.uri} controls autoPlay style={styles.player} />
          {playingBusy && <div style={styles.status}>正在解析播放地址…</div>}
          {!!playingError && <div style={{ color: "#FF6B4A", marginTop: 8 }}>{playingError}</div>}
        </div>
      ) : view.kind === "detail" ? (
        <div style={{ marginTop: 8 }}>
          <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 12 }}>
            <span style={{ fontSize: 22, fontWeight: 700 }}>剧集详情</span>
            <button style={styles.btn} onClick={() => setView({ kind: "list" })}>← 返回列表</button>
          </div>
          {detailBusy ? (
            <div style={styles.status}>正在加载剧集…</div>
          ) : detailError ? (
            <div style={{ color: "#FF6B4A" }}>{detailError}</div>
          ) : detail ? (
            <>
              <div style={styles.detail}>
                <img src={detail.cover} alt="" style={styles.poster} />
                <div>
                  <h1 style={{ margin: "0 0 8px", fontSize: 28 }}>{detail.title}</h1>
                  <div style={styles.muted}>{detail.badge} · {detail.tags}</div>
                  <p style={{ color: "#9B9BA8", lineHeight: "26px", maxWidth: 640 }}>{detail.description}</p>
                </div>
              </div>
              <div style={styles.eps}>
                {detail.episodes.map((e, i) => (
                  <button key={e.id} style={styles.ep} onClick={() => playEpisode(detail, i)}>
                    {e.number}
                  </button>
                ))}
              </div>
            </>
          ) : null}
        </div>
      ) : (
        <>
          <div style={styles.tabs}>
            {(["推荐", "搜索"] as const).map((t) => (
              <button key={t} style={{ ...styles.btn, ...(tab === t ? styles.btnPrimary : {}) }} onClick={() => { setTab(t); setView({ kind: "list" }); }}>
                {t}
              </button>
            ))}
            {tab === "搜索" && (
              <>
                <input style={{ ...styles.input, flex: "0 1 auto" }} value={query} onChange={(e) => setQuery(e.target.value)}
                  onKeyDown={(e) => { if (e.key === "Enter") { setSubmitted(query.trim()); setSearchRun((n) => n + 1); } }}
                  placeholder="输入剧名或关键词，回车搜索" />
                <button style={{ ...styles.btn, ...styles.btnPrimary }} onClick={() => { setSubmitted(query.trim()); setSearchRun((n) => n + 1); }}>搜索</button>
              </>
            )}
          </div>
          {!connected ? (
            <div style={styles.status}>请先填写服务地址并点击「连接」</div>
          ) : catalog.busy && !catalog.items.length ? (
            <div style={styles.status}>正在加载…</div>
          ) : catalog.error && !catalog.items.length ? (
            <div style={{ color: "#FF6B4A" }}>{catalog.error}</div>
          ) : (
            <div ref={gridRef} style={styles.grid}>
              {items.map((item) => (
                <div key={item.id} data-role="grid-item" tabIndex={0}
                  onClick={() => open(item)}
                  onKeyDown={(e) => { if (e.key === "Enter") open(item); }}
                  style={styles.card}
                  onFocus={(e) => { e.currentTarget.style.borderColor = "#fff"; e.currentTarget.style.transform = "scale(1.05)"; }}
                  onBlur={(e) => { e.currentTarget.style.borderColor = "transparent"; e.currentTarget.style.transform = "scale(1)"; }}>
                  <div style={{ position: "relative" }}>
                    <img src={item.cover} alt="" style={styles.cover} loading="lazy" />
                    <div style={styles.badge}>{item.badge || "短剧"}</div>
                  </div>
                  <div style={styles.title}>{item.title}</div>
                </div>
              ))}
            </div>
          )}
        </>
      )}
      <div style={{ marginTop: 28, color: "#555", fontSize: 13 }}>
        Web 调试器仅用于接口与数据链路调试：复用 src/domain 与 src/data 纯 TS 层；焦点用键盘方向键 + Enter 模拟；带 token 时播放走 fetch→Blob。UI 行为与 tvOS 版不完全一致。
      </div>
    </div>
  );
}
