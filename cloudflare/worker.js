// 栗子记账分发反代（Cloudflare Worker）
//
// 为什么存在：GitHub Releases（github.com 与 github-releases.githubusercontent.com）
// 国内直连不可靠，应用内检查更新与 APK 下载经常超时。本 Worker 把 Release
// 资产映射到自有域名 chestnut.taipi.top，走 Cloudflare CDN，国内可达性
// 远好于 GitHub 直连。GitHub Release 仍是唯一事实源，本服务只做转发。
//
// 部署（Cloudflare Dashboard，无需 wrangler）：
//   1. Workers & Pages → Create → Create Worker → 粘贴本文件全部内容 → Deploy
//   2. Worker → Settings → Domains & Routes → Add → Custom domain
//      填 chestnut.taipi.top（需 taipi.top 已托管在 Cloudflare，DNS 自动配置）
//
// 路由（白名单 + 文件名收紧，其余一律 404，防止被当通用反代滥用）：
//   /latest/download/latest.json        -> releases/latest/download/latest.json
//   /download/v<版本>/chestnut-*.apk    -> releases/download/v<版本>/chestnut-*.apk
//
// APk 经此域下载时 App 会追加 ?t=<毫秒> 时间戳参数，GitHub 侧会忽略未知
// 查询串，透传即可，无缓存一致性风险。

const UPSTREAM = 'https://github.com/koeltp/chestnut/releases';

export default {
  async fetch(request) {
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return new Response('Method Not Allowed', { status: 405 });
    }

    const url = new URL(request.url);
    const m = url.pathname.match(/^\/(latest\/download|download\/[^/]+)\/([A-Za-z0-9._-]+)$/);
    if (!m) return new Response('Not Found', { status: 404 });

    const [, route, file] = m;
    // 只放行更新清单与版本化 APK，堵住任意文件转发
    if (file !== 'latest.json' && !/^chestnut-[A-Za-z0-9.-]+\.apk$/.test(file)) {
      return new Response('Not Found', { status: 404 });
    }

    const upstream = `${UPSTREAM}/${route}/${file}${url.search}`;
    // redirect: 'follow'——GitHub 会 302 到 objects.githubusercontent.com，
    // 跟随后流式透传 body（60+MB APK 也不缓冲，Worker CPU 占用可忽略）
    const resp = await fetch(upstream, {
      redirect: 'follow',
      headers: { 'User-Agent': 'chestnut-release-proxy' },
      cf: { cacheEverything: false },
    });

    if (!resp.ok) {
      return new Response('Upstream error', { status: resp.status });
    }
    return resp;
  },
};
