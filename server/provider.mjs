import fs from "node:fs";
import vm from "node:vm";
import crypto from "node:crypto";
import axios from "axios";

// Trusted, pinned GPL source. This is a compatibility wrapper, not a sandbox for user scripts.
const source = fs.readFileSync(
  new URL("./vendor/hongguo.cjs", import.meta.url),
  "utf8"
);
const context = vm.createContext({
  require: (name) => {
    if (name === "node:crypto") return crypto;
    throw new Error("Unsupported module");
  },
  Buffer,
  URL,
  URLSearchParams,
  axios: axios.create({
    maxContentLength: 16 * 1024 * 1024,
    maxBodyLength: 1024 * 1024,
  }),
});
vm.runInContext(
  source +
    "\nthis.api = {categoryPage, categoryData, itemToCard, appSearchPage, routerData, resolveStream, prepareHeader, remoteRange, decryptPartial, streamCache, videoInfoCache, pageCache, appSearchCache};",
  context,
  { timeout: 5000 }
);
const api = context.api;
const SITE = "https://hongguoduanju.com";
const card = (row) => ({
  id: String(row.url),
  title: row.title,
  cover: row.img || "",
  description: row.content || "",
  badge: row.desc || "",
  tags: row.tname || "",
});
const cards = (rows) =>
  Array.from(rows)
    .filter((r) => /^\d+$/.test(String(r.url)) && r.title)
    .map(card);
// 演职人员规范化：上游 celebrities 结构不固定且多数剧集为空，统一成稳定字段。
const cleanUrl = (value) =>
  String(value || "").replace(/\\\//g, "/").replace(/\\u0026/g, "&");
// 上游角色形如 "饰 顾娇" / "饰演 男主"，统一去掉前缀，保留纯角色名。
const cleanRole = (value) =>
  String(value || "")
    .trim()
    .replace(/^(出演|饰演|扮演|饰)\s*/, "")
    .trim();
const celebrity = (row) => {
  const src = typeof row === "string" ? { name: row } : row || {};
  return {
    id: String(
      src.id || src.celebrity_id || src.actor_id || src.person_id || ""
    ),
    name: String(
      src.name ||
        src.nickname ||
        src.actor_name ||
        src.actorName ||
        src.title ||
        ""
    ),
    role: cleanRole(
      src.role ||
        src.sub_title ||
        src.actor_role ||
        src.character ||
        src.desc
    ),
    avatar: cleanUrl(
      src.avatar || src.actor_avatar || src.head_url || src.portrait || ""
    ),
  };
};
export const normalizeCelebrities = (value) => {
  if (!value) return [];
  const list = Array.isArray(value)
    ? value
    : Array.isArray(value.list)
      ? value.list
      : value.actors || value.celebrity_list || value.celebrities || [];
  return Array.isArray(list)
    ? list.map(celebrity).filter((c) => c.name || c.id)
    : [];
};

// 分类目录：对应官网 4 个内容类型（首页 homeSections / 分类页）+ 4 个热播榜。
const CATEGORY_CONFIG = {
  short: { name: "短剧", kind: "home", tab: "all" },
  human: { name: "真人剧", kind: "category", route: "real-drama" },
  comic: { name: "漫剧", kind: "category", route: "comic-drama" },
  ai: { name: "AI剧", kind: "category", route: "ai-drama" },
  rank_hot: { name: "红果热播榜", kind: "rank", route: "hot-drama" },
  rank_human: { name: "真人剧热播榜", kind: "rank", route: "hot-real-drama" },
  rank_comic: { name: "漫剧热播榜", kind: "rank", route: "hot-comic-drama" },
  rank_ai: { name: "AI剧热播榜", kind: "rank", route: "hot-ai-drama" },
};
const RANK_ROUTE_RE = /^(hot-drama|hot-real-drama|hot-comic-drama|hot-ai-drama)$/;
export const CATEGORY_IDS = Object.keys(CATEGORY_CONFIG);
const UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";
// 官网首页 homeSections 按 tab_type 返回对应类型的卡片（all/human/comic/ai）。
async function homeTab(tab) {
  const data = await api.routerData(`${SITE}/`);
  const sections = data?.loaderData?.page?.homeSections;
  if (!Array.isArray(sections)) throw new Error("首页数据不可用");
  const section = sections.find((s) => s?.tab_type === tab);
  if (!section || !Array.isArray(section.video_list))
    throw new Error("首页分类数据不可用");
  return cards(section.video_list.map(api.itemToCard));
}
// 官网分类页 /category/{real-drama|comic-drama|ai-drama}。
async function browseCategory(route, page = 1) {
  const data = await api.routerData(
    `${SITE}/category/${route}${page > 1 ? `?page=${page}` : ""}`
  );
  const pageData =
    data?.loaderData?.category_$ || data?.loaderData?.category_page;
  if (!Array.isArray(pageData?.recommendList)) throw new Error("分类数据不可用");
  return { items: cards(pageData.recommendList.map(api.itemToCard)), page };
}
const decodeHtml = (value) =>
  String(value)
    .replace(/&quot;/g, '"')
    .replace(/&#x2F;|&#47;/gi, "/")
    .replace(/&#x27;|&#39;/gi, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&amp;/g, "&");
// 官网榜单页 /rank/{route}：榜单数据内嵌在 HTML data-fn-args 中。
export async function rankPage(route, page = 1) {
  if (!RANK_ROUTE_RE.test(route)) throw new Error("不支持的榜单");
  const suffix = page > 1 ? `?page=${page}` : "";
  // 官网对连续请求会动态降级返回无 SSR 数据的壳页面，解析到无效数据时带间隔重试。
  let inner = null;
  for (let attempt = 1; attempt <= 3 && !inner?.isSuccess; attempt++) {
    if (attempt > 1)
      await new Promise((resolve) => setTimeout(resolve, attempt * 800));
    const resp = await axios.get(`${SITE}/rank/${route}${suffix}`, {
      timeout: 15000,
      // Accept 必须声明 text/html：官网对 application/json 请求会返回无 SSR 数据的壳页面。
      headers: { "User-Agent": UA, Accept: "text/html,application/xhtml+xml" },
    });
    // 榜单 HTML 内嵌 data-fn-args（官网改版后 data-fn-name 已非固定值，直接取唯一 data-fn-args）。
    const match = /data-fn-args="([^"]+)"/.exec(resp.data);
    if (!match) continue;
    try {
      const payload = JSON.parse(decodeHtml(match[1]));
      const block =
        Array.isArray(payload) && payload.length > 1 ? payload[1] : null;
      const content =
        Array.isArray(block) && block.length ? block[0] : null;
      inner = content?.routerDataFnArgs?.[0]
        ? JSON.parse(content.routerDataFnArgs[0])
        : {};
    } catch {
      /* 壳页面或解析失败视为一次无效尝试，继续重试。 */
    }
  }
  if (!inner?.isSuccess || !Array.isArray(inner.rankList))
    throw new Error("榜单数据格式错误");
  if (!inner?.isSuccess || !Array.isArray(inner.rankList))
    throw new Error("榜单数据格式错误");
  const items = inner.rankList.map((item) =>
    api.itemToCard({
      series_id: item?.seriesId || item?.series_id || item?.id,
      series_name: item?.title || item?.seriesTitle || item?.series_name,
      series_cover: item?.cover || item?.seriesCover || item?.series_cover,
      series_intro:
        item?.description || item?.intro || item?.seriesIntro || item?.summary,
      episode_cnt: item?.episodeCount || item?.episode_cnt,
      tags: item?.tags,
    })
  );
  return { items: cards(items), page };
}

export const provider = {
  // 官网已改版：旧 /category?tab=1 会 301 到真人剧分类页，首页推荐改为解析首页 all（热播短剧）分区。
  async home(page = 1) {
    return { items: await homeTab("all"), page };
  },
  async category(typeId, page = 1) {
    const config = CATEGORY_CONFIG[typeId];
    if (!config) throw new Error("不支持的分类");
    const base = { type_id: typeId, type_name: config.name };
    if (config.kind === "home")
      return { ...base, items: await homeTab(config.tab), page: 1 };
    if (config.kind === "category")
      return { ...base, items: (await browseCategory(config.route, page)).items, page };
    return { ...base, items: (await rankPage(config.route, page)).items, page };
  },
  async search(keyword, page = 1) {
    try {
      const result = await api.appSearchPage(keyword, 11, page, 20);
      if (result.list.length) return { items: cards(result.list), page };
    } catch {
      /* Website fallback; failure below remains an error, never an empty success. */
    }
    const data = await api.routerData(
      `${SITE}/search/${encodeURIComponent(keyword)}?page=${page}`
    );
    const pageData =
      data?.loaderData?.["search_(keyword)/page"] ||
      data?.loaderData?.search_page;
    if (!Array.isArray(pageData?.searchList)) throw new Error("搜索数据不可用");
    return { items: cards(pageData.searchList.map(api.itemToCard)), page };
  },
  // 按演职人员搜索：官网搜索演员名会返回演员卡片（自带参演剧集 video_list）与剧集条目。
  async actorSearch(keyword, page = 1) {
    const data = await api.routerData(
      `${SITE}/search/${encodeURIComponent(keyword)}?page=${page}`
    );
    const pageData =
      data?.loaderData?.["search_(keyword)/page"] ||
      data?.loaderData?.search_page;
    if (!Array.isArray(pageData?.searchList)) throw new Error("搜索数据不可用");
    const actorEntry = pageData.searchList.find(
      (item) => Number(item?.doc_type) === 46
    );
    const info = actorEntry?.user_info || {};
    const actor = actorEntry
      ? {
          id: String(
            info.actor_id || info.person_id || actorEntry.keyword || ""
          ),
          name: info.user_name || actorEntry.name || "",
          avatar: info.user_avatar || "",
          description: info.description || "",
          subtitle: Array.isArray(info.subtitle_list)
            ? info.subtitle_list.join(" / ")
            : "",
        }
      : null;
    const works = actorEntry?.video_list || [];
    const items =
      actor && Array.isArray(works) && works.length
        ? cards(works.map(api.itemToCard))
        : cards(pageData.searchList.map(api.itemToCard));
    return { actor, items, page };
  },
  async detail(id) {
    const data = await api.routerData(`${SITE}/detail?series_id=${id}`);
    const series = data?.loaderData?.detail_page?.seriesDetail;
    if (!series || !Array.isArray(series.vid_list) || !series.vid_list.length)
      throw new Error("剧集不存在或分集暂不可用");
    const episodes = Array.from(series.vid_list, (vid, index) => ({
      id: String(vid),
      title: `第 ${index + 1} 集`,
      number: index + 1,
    }));
    if (
      episodes.some((e) => !/^\d+$/.test(e.id)) ||
      new Set(episodes.map((e) => e.id)).size !== episodes.length
    )
      throw new Error("分集数据异常");
    return {
      ...card(api.itemToCard(series)),
      id,
      celebrities: normalizeCelebrities(series.celebrities),
      episodes,
    };
  },
  async stream(id, fresh = false) {
    if (fresh) {
      api.streamCache.delete(`${id}|auto`);
      api.videoInfoCache.delete(id);
    }
    const stream = await api.resolveStream(id, "auto");
    const prepared = await api.prepareHeader(stream);
    return {
      total: prepared.total,
      chunk: async (start, end) =>
        api.decryptPartial(
          (await api.remoteRange(stream, start, end)).data,
          start,
          stream.key,
          prepared
        ),
    };
  },
};

// Limit the pinned upstream's otherwise unbounded caches during long-lived home use.
setInterval(() => {
  for (const cache of [
    api.streamCache,
    api.videoInfoCache,
    api.pageCache,
    api.appSearchCache,
  ]) {
    for (const [key, value] of cache)
      if (Date.now() - value.time > 300000) cache.delete(key);
    while (cache.size > 100) cache.delete(cache.keys().next().value);
  }
}, 60000).unref();
