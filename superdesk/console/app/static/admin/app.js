// super控制台 -- vanilla JS admin UI for /api/admin/*
'use strict';

const $ = (s, el = document) => el.querySelector(s);
const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const store = {
  get(k) { try { return localStorage.getItem(k); } catch { return null; } },
  set(k, v) { try { localStorage.setItem(k, v); } catch { /* private mode */ } },
  del(k) { try { localStorage.removeItem(k); } catch { /* ignore */ } },
};
let TOKEN = store.get('sd_token') || '';
let GROUPS = [];
let USERS = [];

// ------------------------------------------------------------------ helpers
async function api(method, path, body) {
  const r = await fetch('/api/admin' + path, {
    method,
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + TOKEN },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (r.status === 401 && path !== '/login') { logout(); throw new Error('登录已过期'); }
  const data = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(data.error || ('HTTP ' + r.status));
  return data;
}
function toast(msg, ms = 2600) {
  const t = $('#toast'); t.textContent = msg; t.classList.remove('hidden');
  clearTimeout(toast._t); toast._t = setTimeout(() => t.classList.add('hidden'), ms);
}
async function guard(fn) { try { await fn(); } catch (e) { toast('❌ ' + e.message, 4000); } }
const fmt = (ts) => ts ? new Date(ts * 1000).toLocaleString('zh-CN', { hour12: false }) : '-';
function ago(ts) {
  if (!ts) return '从未';
  const s = Math.floor(Date.now() / 1000) - ts;
  if (s < 60) return '刚刚';
  if (s < 3600) return Math.floor(s / 60) + ' 分钟前';
  if (s < 86400) return Math.floor(s / 3600) + ' 小时前';
  return Math.floor(s / 86400) + ' 天前';
}
function dur(a, b) {
  if (!a || !b) return '-';
  const s = b - a; if (s < 60) return s + ' 秒';
  if (s < 3600) return Math.floor(s / 60) + ' 分 ' + (s % 60) + ' 秒';
  return Math.floor(s / 3600) + ' 小时 ' + Math.floor((s % 3600) / 60) + ' 分';
}
const size = (n) => n > 1 << 30 ? (n / (1 << 30)).toFixed(2) + ' GB' : (n / (1 << 20)).toFixed(1) + ' MB';
const devName = (r) => esc(r.alias || r.hostname || r.device_name || '') || '<span class="muted">未命名</span>';

function h(html) { const d = document.createElement('div'); d.innerHTML = html.trim(); return d.firstElementChild; }

function table(cols, rows, empty = '暂无数据') {
  if (!rows.length) return `<div class="tablewrap"><div class="empty">${empty}</div></div>`;
  return `<div class="tablewrap"><table><thead><tr>${cols.map((c) => `<th>${c[0]}</th>`).join('')}</tr></thead><tbody>${
    rows.map((r, i) => `<tr>${cols.map((c) => `<td class="${c[2] || ''}">${c[1](r, i)}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`;
}

function modal(title, bodyHtml, actions, wide = false) {
  $('#modal-title').textContent = title;
  $('#modal-body').innerHTML = bodyHtml;
  $('.modal-box').classList.toggle('wide', wide);
  const box = $('#modal-actions'); box.innerHTML = '';
  for (const [label, cls, fn] of actions) {
    const b = document.createElement('button'); b.textContent = label; if (cls) b.className = cls;
    b.onclick = () => guard(async () => { if ((await fn()) !== false) closeModal(); });
    box.appendChild(b);
  }
  $('#modal').classList.remove('hidden');
}
function closeModal() { $('#modal').classList.add('hidden'); $('#modal-body').innerHTML = ''; }
const cancel = ['取消', '', () => true];
$('#modal').addEventListener('click', (e) => { if (e.target.id === 'modal') closeModal(); });
const val = (name) => { const el = $(`#modal-body [name="${name}"]`); return el ? (el.type === 'checkbox' ? el.checked : el.value) : undefined; };

// paged list with search box; render(data) -> html
function pagedPage({ path, cols, search = '搜索…', extraFilters = '', params = () => '' }) {
  let pageNo = 1;
  $('#page').innerHTML = `<div class="toolbar"><input id="q" placeholder="${search}">${extraFilters}</div><div id="list"></div>`;
  const load = () => guard(async () => {
    const q = encodeURIComponent($('#q').value.trim());
    const d = await api('GET', `${path}${path.includes('?') ? '&' : '?'}page=${pageNo}&size=50&q=${q}${params()}`);
    const pages = Math.max(1, Math.ceil(d.total / d.size));
    $('#list').innerHTML = table(cols, d.data) +
      `<div class="pager">共 ${d.total} 条 · 第 ${d.page}/${pages} 页 <button class="small" id="prev" ${d.page <= 1 ? 'disabled' : ''}>上一页</button><button class="small" id="next" ${d.page >= pages ? 'disabled' : ''}>下一页</button></div>`;
    $('#prev').onclick = () => { pageNo--; load(); };
    $('#next').onclick = () => { pageNo++; load(); };
  });
  let t; $('#q').oninput = () => { clearTimeout(t); t = setTimeout(() => { pageNo = 1; load(); }, 300); };
  for (const el of document.querySelectorAll('.toolbar select')) el.onchange = () => { pageNo = 1; load(); };
  load();
  return load;
}

// ------------------------------------------------------------------ pages
const CONN_TYPES = ['远程控制', '文件传输', '端口转发/RDP', '查看摄像头', '远程终端'];
const ALARMS = { 0: 'IP 白名单拦截', 1: '密码错误超过 30 次', 2: '1 分钟内密码错误超 6 次', 6: 'IPv6 前缀拦截', 7: '终端登录退避', 8: '终端登录并发', 9: '会话越权', 10: 'ID 白名单拦截' };
const APPROVE = { '': '不管控（保持设备自己的设置）', 'password-click': '密码 或 被控端点击接受', password: '只能用密码', click: '必须被控端点击接受' };
const RULES = { 0: '无权限', 1: '只读', 2: '读写', 3: '完全控制' };

const PAGES = {
  overview: { title: '概览', async render() {
    const d = await api('GET', '/overview');
    $('#page').innerHTML = `
      <div class="cards">
        <div class="stat"><b>${d.online}<small class="muted"> / ${d.devices}</small></b><span>在线设备 / 全部</span></div>
        <div class="stat"><b>${d.active_sessions}</b><span>进行中的远程会话</span></div>
        <div class="stat"><b>${d.conns_today}</b><span>24 小时内连接</span></div>
        <div class="stat"><b style="color:${d.help_open ? 'var(--bad)' : ''}">${d.help_open}</b><span>待处理求助</span></div>
        <div class="stat"><b style="color:${d.alarms_today ? 'var(--warn)' : ''}">${d.alarms_today}</b><span>24 小时内安全告警</span></div>
        <div class="stat"><b>${d.users}</b><span>控制台账号</span></div>
      </div>
      <div class="grid2">
        <div class="panel"><h3>待处理求助</h3>${table([
          ['时间', (r) => ago(r.created_at)], ['电脑', (r) => esc(r.device_name) + `<br><span class="mono muted">${esc(r.device_id)}</span>`],
          ['问题', (r) => esc(r.message) || '<span class="muted">未填写</span>', 'wrap'],
          ['', (r) => `<button class="small primary" onclick="helpDone(${r.id})">已处理</button>`]], d.help, '没有待处理的求助 🎉')}</div>
        <div class="panel"><h3>最近动态</h3>${table([['时间', (r) => ago(r.created_at)], ['内容', (r) => esc(r.text), 'wrap']], d.events)}</div>
      </div>`;
  } },

  devices: { title: '设备', async render() {
    GROUPS = await api('GET', '/groups');
    const opts = '<option value="*">全部分组</option><option value="">未分组</option>' + GROUPS.map((g) => `<option>${esc(g.name)}</option>`).join('');
    const reload = pagedPage({
      path: '/devices', search: '搜索 ID / 电脑名 / 用户 / 备注',
      extraFilters: `<select id="fgroup">${opts}</select><select id="fonline"><option value="">全部状态</option><option value="1">仅在线</option></select>`,
      params: () => `&group=${encodeURIComponent($('#fgroup').value)}&online=${$('#fonline').value}`,
      cols: [
        ['状态', (r) => `<span class="dot ${r.online ? 'on' : ''}"></span>${r.online ? '在线' : ago(r.last_seen)}${r.conns ? ` <span class="tag warn">${r.conns} 个连接</span>` : ''}`],
        ['电脑', (r) => `${devName(r)}<br><span class="muted">${esc(r.username)}</span>`],
        ['ID', (r) => `<span class="mono">${esc(r.id)}</span>`],
        ['系统', (r) => esc((r.os || '').split(' / ')[0]) + `<br><span class="muted">${esc(r.flavor === 'helper' ? '员工助手' : r.flavor === 'full' ? '完整版' : '')} ${esc(r.build || r.version)}</span>`],
        ['分组', (r) => r.group_name ? `<span class="tag">${esc(r.group_name)}</span>` : '<span class="muted">-</span>'],
        ['登录账号', (r) => esc(r.login_user || '-')],
        ['IP', (r) => `<span class="mono">${esc(r.ip)}</span>`],
        ['备注', (r) => esc(r.note), 'wrap'],
        ['', (r) => `<div class="acts"><button class="small" onclick="editDevice('${esc(r.id)}')">编辑</button><button class="small" onclick="deviceDetail('${esc(r.id)}')">详情</button>${r.conns ? `<button class="small danger" onclick="disconnectDevice('${esc(r.id)}')">断开</button>` : ''}<button class="small danger" onclick="deleteDevice('${esc(r.id)}')">删除</button></div>`],
      ],
    });
    window._reload = reload;
  } },

  help: { title: '求助工单', async render() {
    const reload = pagedPage({
      path: '/help', search: '（按状态筛选）',
      extraFilters: '<select id="fst"><option value="open">待处理</option><option value="done">已处理</option><option value="">全部</option></select>',
      params: () => `&status=${$('#fst').value}`,
      cols: [
        ['#', (r) => r.id], ['时间', (r) => fmt(r.created_at)],
        ['电脑', (r) => esc(r.device_name) + ` <span class="muted">${esc(r.os)}</span>`],
        ['ID', (r) => `<span class="mono">${esc(r.device_id)}</span> <a href="superdesk://connection/new/${esc(r.device_id)}">连接</a>`],
        ['问题', (r) => esc(r.message) || '<span class="muted">未填写</span>', 'wrap'],
        ['状态', (r) => r.status === 'open' ? '<span class="tag bad">待处理</span>' : `<span class="tag ok">已处理</span> <span class="muted">${esc(r.handled_by)} ${ago(r.handled_at)}</span>`],
        ['', (r) => r.status === 'open' ? `<button class="small primary" onclick="helpDone(${r.id})">标记已处理</button>` : ''],
      ],
    });
    window._reload = reload;
  } },

  conns: { title: '连接审计', async render() {
    pagedPage({
      path: '/audit/conn', search: '搜索 ID / 电脑名 / IP / 备注',
      cols: [
        ['开始', (r) => fmt(r.created_at)],
        ['被控电脑', (r) => devName(r) + `<br><span class="mono muted">${esc(r.device_id)}</span>`],
        ['控制方', (r) => r.peer_id ? esc(r.peer_name) + `<br><span class="mono muted">${esc(r.peer_id)}</span>` : '<span class="muted">未通过验证</span>'],
        ['类型', (r) => r.authorized_at ? esc(CONN_TYPES[r.type] ?? r.type) : '-'],
        ['来源 IP', (r) => `<span class="mono">${esc(r.ip)}</span>`],
        ['时长', (r) => r.closed_at ? dur(r.authorized_at || r.created_at, r.closed_at) : (r.authorized_at ? '<span class="tag warn">进行中</span>' : '-')],
        ['备注', (r) => esc(r.note), 'wrap'],
      ],
    });
  } },

  files: { title: '文件传输审计', async render() {
    pagedPage({
      path: '/audit/file', search: '搜索 ID / 路径 / 文件名',
      cols: [
        ['时间', (r) => fmt(r.created_at)],
        ['电脑', (r) => devName(r) + `<br><span class="mono muted">${esc(r.device_id)}</span>`],
        ['对方', (r) => `<span class="mono">${esc(r.peer_id)}</span>`],
        ['方向', (r) => r.type === 0 ? '<span class="tag warn">从被控端发出</span>' : '<span class="tag">发往被控端</span>'],
        ['路径', (r) => esc(r.path || '剪贴板'), 'wrap'],
        ['文件', (r) => { try { const i = JSON.parse(r.info); return `${i.num ?? ''} 个：` + esc((i.files || []).map((f) => `${f[0]}（${size(f[1])}）`).join('，')); } catch { return esc(r.info); } }, 'wrap'],
      ],
    });
  } },

  alarms: { title: '安全告警', async render() {
    pagedPage({
      path: '/audit/alarm', search: '（全部告警）',
      cols: [
        ['时间', (r) => fmt(r.created_at)],
        ['电脑', (r) => devName(r) + `<br><span class="mono muted">${esc(r.device_id)}</span>`],
        ['类型', (r) => `<span class="tag bad">${esc(ALARMS[r.typ] ?? r.typ)}</span>`],
        ['详情', (r) => esc(r.info), 'wrap'],
      ],
    });
  } },

  recordings: { title: '会话录屏', async render() {
    const reload = pagedPage({
      path: '/recordings', search: '搜索 ID / 电脑名 / 文件名',
      cols: [
        ['时间', (r) => fmt(r.created_at)],
        ['电脑', (r) => devName(r) + `<br><span class="mono muted">${esc(r.device_id)}</span>`],
        ['文件', (r) => esc(r.filename), 'wrap'],
        ['大小', (r) => size(r.size) + (r.finished ? '' : ' <span class="tag warn">录制中/未完成</span>')],
        ['', (r) => `<div class="acts"><button class="small" onclick="playRecording(${r.id}, '${esc(r.filename)}')">播放</button><a class="small" href="/api/admin/recordings/${r.id}/file?token=${encodeURIComponent(TOKEN)}" download><button class="small">下载</button></a><button class="small danger" onclick="deleteRecording(${r.id})">删除</button></div>`],
      ],
    });
    window._reload = reload;
  } },

  groups: { title: '分组与访问策略', actions: [['新建分组', 'primary', () => editGroup()]], async render() {
    GROUPS = await api('GET', '/groups');
    const policyText = (g) => [
      g.work_hours_only ? `<span class="tag warn">仅工作时间可连：周${g.work_days.replaceAll(',', '')} ${g.work_start}-${g.work_end}</span>` : '',
      g.company_only ? '<span class="tag warn">仅公司账号设备可连</span>' : '',
      g.approve_mode ? `<span class="tag">${APPROVE[g.approve_mode]}</span>` : '',
      g.record_sessions ? '<span class="tag bad">录屏并上传</span>' : '',
      Object.keys(g.extra_options || {}).length ? `<span class="tag">附加配置 ${Object.keys(g.extra_options).length} 项</span>` : '',
    ].join('') || '<span class="muted">无限制</span>';
    $('#page').innerHTML = `<div class="panel muted">策略通过设备心跳自动下发（约 15 秒内生效）。设备在“设备”页指定分组。“仅公司账号设备可连”只允许已在客户端登录控制台账号的电脑发起连接，启用前请确认 IT 的电脑已登录。</div>` +
      table([
        ['分组', (g) => `<b>${esc(g.name)}</b><br><span class="muted">${esc(g.note)}</span>`],
        ['设备数', (g) => g.devices],
        ['策略', (g) => policyText(g), 'wrap'],
        ['', (g) => `<div class="acts"><button class="small" onclick='editGroup(${JSON.stringify(g.name)})'>编辑</button><button class="small danger" onclick='deleteGroup(${JSON.stringify(g.name)})'>删除</button></div>`],
      ], GROUPS, '还没有分组。新建分组后，在“设备”页把电脑分进去，即可按组下发访问策略。');
  } },

  users: { title: '控制台账号', actions: [['新建账号', 'primary', () => editUser()]], async render() {
    USERS = await api('GET', '/users');
    $('#page').innerHTML = `<div class="panel muted">账号用于：登录本控制台（管理员）、在客户端登录以使用共享通讯录和设备列表。员工电脑一般不需要账号。</div>` +
      table([
        ['用户名', (u) => `<b>${esc(u.name)}</b> ${u.is_admin ? '<span class="tag">管理员</span>' : ''} ${u.status === 1 ? '' : '<span class="tag bad">已禁用</span>'}`],
        ['显示名', (u) => esc(u.display_name)], ['邮箱', (u) => esc(u.email)],
        ['登录的设备', (u) => u.devices], ['创建', (u) => fmt(u.created_at)], ['备注', (u) => esc(u.note), 'wrap'],
        ['', (u) => `<div class="acts"><button class="small" onclick="editUser(${u.id})">编辑</button><button class="small danger" onclick="deleteUser(${u.id})">删除</button></div>`],
      ], USERS);
  } },

  abs: { title: '共享通讯录', actions: [['新建共享通讯录', 'primary', () => editAb()]], async render() {
    USERS = await api('GET', '/users');
    const abs = await api('GET', '/address-books');
    const shared = abs.filter((a) => !a.personal);
    const ruleText = (a) => a.rules.map((r) => `<span class="tag">${r.user_id == null ? '所有人' : esc((USERS.find((u) => u.id === r.user_id) || {}).name || '#' + r.user_id)}：${RULES[r.rule]}</span>`).join('') || '<span class="muted">仅管理员</span>';
    window._abs = abs;
    $('#page').innerHTML = `<div class="panel muted">共享通讯录会出现在每个有权限账号的客户端“地址簿”里，适合按部门整理常用电脑。个人通讯录由各账号在客户端里自行维护。</div>` +
      table([
        ['名称', (a) => `<b>${esc(a.name)}</b><br><span class="muted">${esc(a.note)}</span>`],
        ['设备数', (a) => a.peers], ['权限', ruleText, 'wrap'], ['创建者', (a) => esc(a.owner_name)],
        ['', (a) => `<div class="acts"><button class="small" onclick="abAddDevices('${a.guid}')">添加设备</button><button class="small" onclick="abPeers('${a.guid}')">查看</button><button class="small" onclick="editAb('${a.guid}')">编辑</button><button class="small danger" onclick="deleteAb('${a.guid}')">删除</button></div>`],
      ], shared, '还没有共享通讯录') +
      `<h3 style="margin:20px 0 8px">个人通讯录</h3>` +
      table([['账号', (a) => esc(a.owner_name)], ['设备数', (a) => a.peers]], abs.filter((a) => a.personal), '还没有账号使用个人通讯录');
  } },

  deploy: { title: '部署记录', async render() {
    $('#page').innerHTML = `<div class="panel">在公司电脑上以管理员身份运行部署脚本即可安装为开机服务、设置固定密码并自动出现在这里，详见 <a href="/download/" target="_blank">下载中心</a>。</div><div id="dl"></div>`;
    const d = await api('GET', '/deploy?size=200');
    $('#dl').innerHTML = table([
      ['时间', (r) => fmt(r.created_at)], ['电脑', (r) => esc(r.hostname)], ['ID', (r) => `<span class="mono">${esc(r.device_id) || '<span class="muted">未获取</span>'}</span>`],
      ['操作人', (r) => esc(r.username)], ['版本', (r) => esc(r.flavor === 'helper' ? '员工助手' : '完整版') + ' ' + esc(r.build)],
      ['IP', (r) => `<span class="mono">${esc(r.ip)}</span>`], ['备注', (r) => esc(r.note), 'wrap']], d.data, '还没有部署记录');
  } },

  settings: { title: '通知与设置', async render() {
    const s = await api('GET', '/settings');
    const kinds = { wecom: '企业微信群机器人', dingtalk: '钉钉群机器人', feishu: '飞书群机器人' };
    const hookHtml = (w, i) => `<div class="hook" data-i="${i}">
      <div class="row"><label>名称<input data-k="name" value="${esc(w.name || '')}" placeholder="例如：IT 值班群"></label>
      <label>类型<select data-k="kind">${Object.entries(kinds).map(([k, v]) => `<option value="${k}" ${w.kind === k ? 'selected' : ''}>${v}</option>`).join('')}</select></label></div>
      <label>Webhook 地址<input data-k="url" value="${esc(w.url || '')}" placeholder="https://..."></label>
      <label>加签密钥（钉钉/飞书开启“加签”时填写，可留空）<input data-k="secret" value="${esc(w.secret || '')}"></label>
      <div class="days">${Object.entries(s.notify_events).map(([k, v]) => `<label class="check"><input type="checkbox" data-ev="${k}" ${(w.events || []).includes(k) ? 'checked' : ''}>${v}</label>`).join('')}</div>
      <div class="acts" style="margin-top:10px"><label class="check"><input type="checkbox" data-k="enabled" ${w.enabled !== false ? 'checked' : ''}>启用</label>
      <button class="small" onclick="testHook(${i})">发送测试消息</button><button class="small danger" onclick="this.closest('.hook').remove()">删除</button></div></div>`;
    $('#page').innerHTML = `
      <div class="panel"><h3>群通知（企业微信 / 钉钉 / 飞书）</h3>
        <p class="muted">在群里添加“自定义机器人”，把 Webhook 地址填到这里。员工点击“请求 IT 协助”、有人远程连接电脑、新电脑部署完成等事件会推送到群里。</p>
        <div id="hooks">${(s.webhooks || []).map(hookHtml).join('')}</div>
        <button id="addhook">＋ 添加通知渠道</button></div>
      <div class="panel"><h3>数据保留</h3><div class="row">
        <label>录屏保留天数<input id="recdays" type="number" min="1" value="${s.recording_retention_days}"></label>
        <label>审计日志保留天数<input id="auddays" type="number" min="7" value="${s.audit_retention_days}"></label></div></div>
      <div class="panel"><h3>账号注册</h3>
        <label class="check"><input id="allowreg" type="checkbox" ${s.allow_register !== false ? 'checked' : ''}> 允许在客户端登录框自助注册账号（无需审核，注册的是普通账号）</label></div>
      <button class="primary" id="savesettings">保存设置</button>`;
    window._hookHtml = hookHtml;
    $('#addhook').onclick = () => { const n = document.querySelectorAll('.hook').length; $('#hooks').appendChild(h(hookHtml({ kind: 'wecom', events: ['help', 'alarm'], enabled: true }, n))); };
    $('#savesettings').onclick = () => guard(async () => {
      await api('PUT', '/settings', { webhooks: readHooks(), recording_retention_days: +$('#recdays').value, audit_retention_days: +$('#auddays').value, allow_register: $('#allowreg').checked });
      toast('✅ 已保存');
    });
  } },

  notices: { title: '公告', actions: [['发布公告', 'primary', () => editNotice()]], async render() {
    const rows = await api('GET', '/notices');
    $('#page').innerHTML = `<div class="panel muted">公告会出现在客户端右上角的铃铛（消息中心）里，未读时显示红点。所有已登记的设备都能看到，请不要写密码等敏感信息。</div>` +
      table([
        ['时间', (n) => fmt(n.created_at)], ['标题', (n) => `<b>${esc(n.title)}</b>`], ['内容', (n) => esc(n.content), 'wrap'],
        ['发布人', (n) => esc(n.created_by)],
        ['', (n) => `<div class="acts"><button class="small danger" onclick="deleteNotice(${n.id})">删除</button></div>`],
      ], rows, '还没有公告');
  } },

  events: { title: '操作日志', async render() {
    pagedPage({ path: '/events', search: '（全部记录）', cols: [['时间', (r) => fmt(r.created_at)], ['类别', (r) => `<span class="tag">${esc(r.kind)}</span>`], ['内容', (r) => esc(r.text), 'wrap']] });
  } },
};

const NAV = [['overview'], ['devices'], ['help'], ['-', '审计'], ['conns'], ['files'], ['alarms'], ['recordings'], ['-', '管理'],
  ['groups'], ['users'], ['abs'], ['notices'], ['deploy'], ['settings'], ['events']];

// ------------------------------------------------------------------ actions
function readHooks() {
  return [...document.querySelectorAll('.hook')].map((el) => {
    const w = { events: [] };
    for (const i of el.querySelectorAll('[data-k]')) w[i.dataset.k] = i.type === 'checkbox' ? i.checked : i.value.trim();
    for (const i of el.querySelectorAll('[data-ev]')) if (i.checked) w.events.push(i.dataset.ev);
    return w;
  });
}
window.testHook = (i) => guard(async () => { await api('POST', '/webhooks/test', readHooks()[i]); toast('✅ 已发送，请到群里查看'); });
window.helpDone = (id) => guard(async () => { await api('POST', `/help/${id}/done`); toast('已标记处理'); route(); refreshBadge(); });

window.editDevice = (id) => guard(async () => {
  const d = await api('GET', `/devices/${encodeURIComponent(id)}`);
  GROUPS = await api('GET', '/groups');
  modal(`编辑设备 ${id}`, `
    <label>显示名称（留空则用电脑名 ${esc(d.hostname)}）<input name="alias" value="${esc(d.alias)}"></label>
    <label>分组<select name="group_name"><option value="">未分组</option>${GROUPS.map((g) => `<option ${g.name === d.group_name ? 'selected' : ''}>${esc(g.name)}</option>`).join('')}</select></label>
    <label>备注<input name="note" value="${esc(d.note)}"></label>`,
  [cancel, ['保存', 'primary', async () => { await api('PUT', `/devices/${encodeURIComponent(id)}`, { alias: val('alias'), note: val('note'), group_name: val('group_name') }); toast('已保存'); window._reload && window._reload(); }]]);
});
window.deviceDetail = (id) => guard(async () => {
  const d = await api('GET', `/devices/${encodeURIComponent(id)}`);
  const pol = Object.entries(d.policy).map(([k, v]) => `<span class="tag">${esc(k)} = ${esc(v || '（清除）')}</span>`).join('') || '<span class="muted">无（未分组或分组无策略）</span>';
  modal(`设备详情 ${id}`, `
    <p><span class="dot ${d.online ? 'on' : ''}"></span>${d.online ? '在线' : '离线，最后在线 ' + fmt(d.last_seen)} · <a href="superdesk://connection/new/${esc(d.id)}">用 super远程桌面 连接</a></p>
    <table><tbody>
      <tr><th>电脑名</th><td>${esc(d.hostname)}</td></tr><tr><th>当前用户</th><td>${esc(d.username)}</td></tr>
      <tr><th>系统</th><td class="wrap">${esc(d.os)}</td></tr><tr><th>CPU / 内存</th><td class="wrap">${esc(d.cpu)} / ${esc(d.memory)}</td></tr>
      <tr><th>客户端</th><td>${esc(d.flavor)} ${esc(d.version)} 构建 ${esc(d.build)}</td></tr><tr><th>IP</th><td class="mono">${esc(d.ip)}</td></tr>
      <tr><th>首次出现</th><td>${fmt(d.created_at)}</td></tr><tr><th>生效策略</th><td class="wrap">${pol}</td></tr>
    </tbody></table>
    <h3>最近连接</h3>${table([['时间', (r) => fmt(r.created_at)], ['方向', (r) => r.device_id === d.id ? '被控' : '主控'],
      ['对方', (r) => esc(r.device_id === d.id ? (r.peer_name + ' ' + r.peer_id) : r.device_id)], ['时长', (r) => r.closed_at ? dur(r.authorized_at || r.created_at, r.closed_at) : '-']], d.recent_conns)}`,
  [['关闭', '', () => true]], true);
});
window.disconnectDevice = (id) => guard(async () => {
  if (!confirm(`确定强制断开 ${id} 上正在进行的远程连接？`)) return;
  await api('POST', `/devices/${encodeURIComponent(id)}/disconnect`); toast('已下发断开指令（几秒内生效）');
});
window.deleteDevice = (id) => guard(async () => {
  if (!confirm(`删除设备记录 ${id}？（设备仍在线的话会重新出现）`)) return;
  await api('DELETE', `/devices/${encodeURIComponent(id)}`); window._reload && window._reload();
});
window.playRecording = (id, name) => modal(name, `<video controls autoplay src="/api/admin/recordings/${id}/file?token=${encodeURIComponent(TOKEN)}"></video>`, [['关闭', '', () => true]], true);
window.deleteRecording = (id) => guard(async () => { if (!confirm('删除这段录屏？')) return; await api('DELETE', `/recordings/${id}`); window._reload && window._reload(); });

window.editGroup = (name) => guard(async () => {
  const g = (name != null && GROUPS.find((x) => x.name === name)) || { name: '', note: '', work_hours_only: 0, work_days: '1,2,3,4,5', work_start: '08:00', work_end: '19:00', approve_mode: '', record_sessions: 0, company_only: 0, extra_options: {} };
  const days = g.work_days.split(',');
  modal(name != null ? `编辑分组 ${name}` : '新建分组', `
    <div class="row"><label>分组名<input name="name" value="${esc(g.name)}"></label><label>说明<input name="note" value="${esc(g.note)}"></label></div>
    <label class="check"><input type="checkbox" name="work_hours_only" ${g.work_hours_only ? 'checked' : ''}>只允许在工作时间被远程（其余时间任何人都连不上）</label>
    <div class="days">${['一', '二', '三', '四', '五', '六', '日'].map((d, i) => `<label class="check"><input type="checkbox" name="day${i + 1}" ${days.includes(String(i + 1)) ? 'checked' : ''}>周${d}</label>`).join('')}</div>
    <div class="row" style="margin-top:8px"><label>开始<input name="work_start" type="time" value="${esc(g.work_start)}"></label><label>结束<input name="work_end" type="time" value="${esc(g.work_end)}"></label></div>
    <label class="check"><input type="checkbox" name="company_only" ${g.company_only ? 'checked' : ''}>只允许“已登录控制台账号”的电脑连接</label>
    <label>连接验证方式<select name="approve_mode">${Object.entries(APPROVE).map(([k, v]) => `<option value="${k}" ${g.approve_mode === k ? 'selected' : ''}>${v}</option>`).join('')}</select></label>
    <label class="check"><input type="checkbox" name="record_sessions" ${g.record_sessions ? 'checked' : ''}>录制被远程的会话并上传到控制台（员工端会显示录屏提示）</label>
    <label>附加 RustDesk 配置（JSON，高级）<textarea name="extra_options" placeholder='{"enable-file-transfer": "N"}'>${esc(JSON.stringify(g.extra_options || {}, null, 1))}</textarea></label>`,
  [cancel, ['保存', 'primary', async () => {
    let extra; try { extra = JSON.parse(val('extra_options') || '{}'); } catch { throw new Error('附加配置不是合法的 JSON'); }
    const body = { name: val('name'), note: val('note'), work_hours_only: val('work_hours_only'), work_start: val('work_start'), work_end: val('work_end'),
      work_days: [1, 2, 3, 4, 5, 6, 7].filter((i) => val('day' + i)).join(','), approve_mode: val('approve_mode'), record_sessions: val('record_sessions'),
      company_only: val('company_only'), extra_options: extra };
    if (name != null) await api('PUT', `/groups/${encodeURIComponent(name)}`, body); else await api('POST', '/groups', body);
    toast('已保存，策略将随心跳下发'); route();
  }]]);
});
window.deleteGroup = (name) => guard(async () => {
  if (!confirm(`删除分组 ${name}？组内设备变为未分组，已下发的策略会被清除。`)) return;
  await api('DELETE', `/groups/${encodeURIComponent(name)}`); route();
});

window.editUser = (id) => guard(async () => {
  const u = (id != null && USERS.find((x) => x.id === id)) || { name: '', display_name: '', email: '', note: '', is_admin: 0, status: 1 };
  modal(id != null ? `编辑账号 ${u.name}` : '新建账号', `
    <div class="row"><label>用户名<input name="name" value="${esc(u.name)}" ${id != null ? 'disabled' : ''}></label><label>显示名<input name="display_name" value="${esc(u.display_name)}"></label></div>
    <div class="row"><label>邮箱<input name="email" value="${esc(u.email)}"></label><label>${id != null ? '新密码（不改留空）' : '密码（至少 8 位）'}<input name="password" type="password" autocomplete="new-password"></label></div>
    <label>备注<input name="note" value="${esc(u.note)}"></label>
    <label class="check"><input type="checkbox" name="is_admin" ${u.is_admin ? 'checked' : ''}>管理员（可登录本控制台）</label>
    <label class="check"><input type="checkbox" name="enabled" ${u.status === 1 ? 'checked' : ''}>启用</label>`,
  [cancel, ['保存', 'primary', async () => {
    const body = { name: id != null ? u.name : val('name'), display_name: val('display_name'), email: val('email'), note: val('note'),
      password: val('password'), is_admin: val('is_admin'), status: val('enabled') ? 1 : 0 };
    if (id != null) await api('PUT', `/users/${id}`, body); else await api('POST', '/users', body);
    toast('已保存'); route();
  }]]);
});
window.deleteUser = (id) => guard(async () => { if (!confirm('删除该账号？其个人通讯录也会删除。')) return; await api('DELETE', `/users/${id}`); route(); });

window.editAb = (guid) => guard(async () => {
  USERS = await api('GET', '/users');
  const a = (guid && window._abs.find((x) => x.guid === guid)) || { name: '', note: '', rules: [] };
  const ruleOf = (uid) => (a.rules.find((r) => r.user_id === uid) || {}).rule || 0;
  const sel = (n, v) => `<select name="${n}">${Object.entries(RULES).map(([k, t]) => `<option value="${k}" ${+k === v ? 'selected' : ''}>${t}</option>`).join('')}</select>`;
  modal(guid ? '编辑共享通讯录' : '新建共享通讯录', `
    <div class="row"><label>名称<input name="name" value="${esc(a.name)}"></label><label>说明<input name="note" value="${esc(a.note)}"></label></div>
    <label>所有账号的默认权限${sel('rule_all', ruleOf(null))}</label>
    ${USERS.map((u) => `<label>${esc(u.display_name || u.name)}（${esc(u.name)}）${sel('rule_' + u.id, ruleOf(u.id))}</label>`).join('')}`,
  [cancel, ['保存', 'primary', async () => {
    const rules = [];
    if (+val('rule_all')) rules.push({ user_id: null, rule: +val('rule_all') });
    for (const u of USERS) if (+val('rule_' + u.id)) rules.push({ user_id: u.id, rule: +val('rule_' + u.id) });
    const body = { name: val('name'), note: val('note'), rules };
    if (guid) await api('PUT', `/address-books/${guid}`, body); else await api('POST', '/address-books', body);
    toast('已保存'); route();
  }]]);
});
window.editNotice = () => modal('发布公告', `
    <label>标题<input name="title" maxlength="100" placeholder="例如：今晚 22:00 系统维护"></label>
    <label>内容<textarea name="content" rows="6" maxlength="5000" placeholder="公告正文（可选）"></textarea></label>`,
  [cancel, ['发布', 'primary', async () => { await api('POST', '/notices', { title: val('title'), content: val('content') }); toast('已发布'); route(); }]]);
window.deleteNotice = (id) => guard(async () => { if (!confirm('删除这条公告？')) return; await api('DELETE', `/notices/${id}`); route(); });
window.deleteAb = (guid) => guard(async () => { if (!confirm('删除这个共享通讯录？')) return; await api('DELETE', `/address-books/${guid}`); route(); });
window.abPeers = (guid) => guard(async () => {
  const peers = await api('GET', `/address-books/${guid}/peers`);
  modal('通讯录中的设备', table([['ID', (p) => `<span class="mono">${esc(p.id)}</span>`], ['名称', (p) => esc(p.alias || p.hostname)], ['标签', (p) => (p.tags || []).map((t) => `<span class="tag">${esc(t)}</span>`).join('')]], peers), [['关闭', '', () => true]], true);
});
window.abAddDevices = (guid) => guard(async () => {
  const d = await api('GET', '/devices?size=500');
  modal('添加设备到通讯录', `<label>标签（可选，逗号分隔）<input name="tags"></label>
    <div style="max-height:50vh;overflow:auto">${d.data.map((r) => `<label class="check"><input type="checkbox" name="dev" value="${esc(r.id)}">${devName(r)} <span class="mono muted">${esc(r.id)}</span> ${r.group_name ? `<span class="tag">${esc(r.group_name)}</span>` : ''}</label>`).join('')}</div>`,
  [cancel, ['添加', 'primary', async () => {
    const ids = [...document.querySelectorAll('#modal-body [name="dev"]:checked')].map((i) => i.value);
    const tags = (val('tags') || '').split(/[,，]/).map((s) => s.trim()).filter(Boolean);
    await api('POST', `/address-books/${guid}/peers`, { ids, tags }); toast(`已添加 ${ids.length} 台`); route();
  }]], true);
});

// ------------------------------------------------------------------ shell
let current = 'overview';
function route() {
  if (!TOKEN) return;
  const key = (location.hash || '#overview').slice(1);
  current = PAGES[key] ? key : 'overview';
  const p = PAGES[current];
  $('#title').textContent = p.title;
  document.title = p.title + ' · super控制台';
  for (const a of document.querySelectorAll('#nav a')) a.classList.toggle('active', a.dataset.k === current);
  const acts = $('#actions'); acts.innerHTML = '';
  for (const [label, cls, fn] of p.actions || []) { const b = document.createElement('button'); b.textContent = label; b.className = cls; b.onclick = fn; acts.appendChild(b); }
  window._reload = null;
  $('#page').innerHTML = '<p class="muted">加载中…</p>';
  $('.side').classList.remove('open');
  guard(() => p.render());
}
async function refreshBadge() {
  try {
    const d = await api('GET', '/help?status=open&size=1');
    const b = $('#nav a[data-k="help"] .badge');
    b.textContent = d.total; b.classList.toggle('hidden', !d.total);
  } catch { /* ignore */ }
}
function showApp(me) {
  $('#login').classList.add('hidden'); $('#app').classList.remove('hidden');
  $('#me').textContent = me.display_name || me.name;
  $('#nav').innerHTML = NAV.map(([k, t]) => k === '-' ? `<div class="sep">${t}</div>` :
    `<a href="#${k}" data-k="${k}">${PAGES[k].title}${k === 'help' ? '<span class="badge hidden"></span>' : ''}</a>`).join('');
  route(); refreshBadge();
  clearInterval(showApp._t); showApp._t = setInterval(refreshBadge, 30000);
}
function logout() {
  if (TOKEN) fetch('/api/admin/logout', { method: 'POST', headers: { Authorization: 'Bearer ' + TOKEN } }).catch(() => {});
  TOKEN = ''; store.del('sd_token');
  $('#app').classList.add('hidden'); $('#login').classList.remove('hidden');
}
$('#logout').onclick = (e) => { e.preventDefault(); logout(); };
$('#menu').onclick = () => $('.side').classList.toggle('open');
window.addEventListener('hashchange', route);
$('#login-form').onsubmit = async (e) => {
  e.preventDefault();
  const f = new FormData(e.target);
  $('#login-err').textContent = '';
  try {
    const d = await api('POST', '/login', { username: f.get('username'), password: f.get('password') });
    TOKEN = d.token; store.set('sd_token', TOKEN); showApp(d.user);
  } catch (err) { $('#login-err').textContent = err.message; }
};
(async () => {
  if (!TOKEN) { $('#login').classList.remove('hidden'); return; }
  try { showApp(await api('GET', '/me')); } catch { logout(); }
})();
