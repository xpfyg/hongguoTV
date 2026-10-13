# 内容服务 API v1

服务面向家庭网络，原生客户端共享此协议。所有成功 JSON 响应均使用 UTF-8；失败返回非 2xx 和 `{ "error": "可显示的信息" }`。上游失败不会返回空列表伪装成成功。

| 请求 | 返回 |
| --- | --- |
| `GET /health` | `service: hongguotv`、`version`、`apiVersion: 1`、`upstream: unverified`；只检查进程 |
| `GET /api/home?page=1` | `{ items: Series[], page }` |
| `GET /api/category/:typeId?page=1` | `{ type_id, type_name, items: Series[], page }` |
| `GET /api/search?q=关键词&page=1` | `{ items: Series[], page }` |
| `GET /api/series/:id` | `Series` 加 `episodes: Episode[]` |
| `GET /api/episodes/:id/play?fresh=1` | `{ path, contentType: video/mp4 }`，媒体路径相对当前服务地址；`fresh=1` 强制重新解析 |
| `GET /api/episodes/:id/stream` | MP4 媒体流，支持单区间 Range、后缀区间、HEAD、Content-Length / Content-Range |

`Series` 字段：`id`、`title`、`cover`、`description`、`badge`、`tags`。
`Episode` 字段：`id`、`number`、`title`。ID 始终保留为字符串。
详情响应（`/api/series/:id`）额外返回 `celebrities: Celebrity[]`（演职人员）。实测上游约 1/4 剧集有数据（真人剧为主，单剧 3–24 人），其余为空数组，客户端应容忍空列表；上游原始字段为 `nickname`/`sub_title`（形如"饰 顾娇"）/`avatar`/`celebrity_id`，服务端已规范化为 `Celebrity`：`id`、`name`、`role`（已去"饰/饰演"前缀）、`avatar`，缺失时为空字符串。

分类接口 `typeId` 白名单与数据源：
| typeId | 内容 | 数据源 |
| --- | --- | --- |
| `short` | 短剧（热播） | 首页 `homeSections.all`，单页 |
| `human` | 真人剧 | `/category/real-drama`，分页 |
| `comic` | 漫剧 | `/category/comic-drama`，分页 |
| `ai` | AI剧 | `/category/ai-drama`，分页 |
| `rank_hot` | 红果热播榜 | `/rank/hot-drama`，分页 |
| `rank_human` | 真人剧热播榜 | `/rank/hot-real-drama`，分页 |
| `rank_comic` | 漫剧热播榜 | `/rank/hot-comic-drama`，分页 |
| `rank_ai` | AI剧热播榜 | `/rank/hot-ai-drama`，分页 |

无效 `typeId` 与非法分页返回 400；`/api/home` 现解析首页 `all`（热播短剧）分区（官网改版后旧分类 URL 已 301 到真人剧页）。

客户端按 `剧集ID + 分集ID + 播放秒数` 保存续播记录，不保存临时媒体 URL。一次播放错误会重新解析一次；仍失败时显示重试入口。

服务开启 `BRIDGE_TOKEN` 时，JSON 和视频请求均要求 `Authorization: Bearer <口令>`，播放器也必须携带该请求头。当前没有浏览器跨域白名单配置，因此 Web 端需额外适配，不能当作已交付。

输入错误使用 400，口令错误使用 401，不存在的路径使用 404，无效媒体范围使用 416，源站失败使用 502。同时媒体请求限制为 4 个，超出使用 503。服务不接受用户指定的任意代理 URL。

媒体代理按 1 MiB 分块处理并遵守客户端背压；对开放区间返回完整请求范围，而不是只返回首个 1 MiB。元数据 / 视频缓存定时清理并限制数量。源站 URL 和签名材料不输出到客户端错误和服务日志。

服务为首版家庭使用实现。进程内存、长时间稳定性、不同编码的设备兼容性、源站自然过期后的行为及公网环境均需另行验证。
