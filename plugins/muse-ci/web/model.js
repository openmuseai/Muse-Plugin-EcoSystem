/* Local preview adapter. Never talks to Host, AI providers or distribution services. */
(function (root) {
  'use strict';
  const clone = value => JSON.parse(JSON.stringify(value));
  const evidence = [
    { id: 'audit', title: '发行依赖检查', kind: '检查', status: '示例通过', file: 'mobile-closure.json', detail: '示例报告：检查排除依赖、资源路径和压缩清单。正式结果应绑定最终发行包摘要。', result: { scope: 'preview-fixture', excludedPackages: [], finalArtifactVerified: false } },
    { id: 'source', title: '源码与版本记录', kind: '源码', status: '待冻结', file: 'source-set.json', detail: '当前仅展示输入清单的结构。跨仓库版本与外部原生库必须在正式构建前冻结。', result: { scope: 'preview-fixture', sourceFrozen: false, repositories: ['Muse-Client', 'Muse-Plugin-Ecosystem'] } },
    { id: 'privacy', title: 'AI 数据共享验收', kind: '检查', status: '待补充', file: 'privacy-review.json', detail: '仍需真实接收方、发送前授权与撤回的设备验证。记录示例决定不构成隐私验收通过。', result: { scope: 'preview-fixture', recipientVerified: false, deviceEvidence: null } },
    { id: 'device', title: 'iOS 真机验证', kind: '设备', status: '未执行', file: 'device-report.json', detail: '应覆盖首次启动、拒绝授权、切换模型、断线重连。原型没有连接设备。', result: { scope: 'preview-fixture', executed: false } }
  ];
  const stages = ['需求范围', '开发冻结', '隐私整改', '功能测试', '签名构建', '发行包验证', '审核物料', '上传安装', '正式提审', '审核跟进', '分批发布', '观察归档'];
  function initial() { return { schema: 1, goal: '移出 Mobile 的第三方文档实现，完成 AI 数据共享整改并准备 iOS 重新提审。', budget: 80, type: '审核整改', revision: 1, connected: true, run: null, selected: 'overview', decisions: { brand: '', privacy: '' }, tasks: [
    { title: '梳理依赖与发行边界', detail: '确认 SiYuan / GenOffice 的插件隔离范围', status: 'done', area: '开发' },
    { title: '切换文档组件入口', detail: '将本机入口统一到 SmartDocument', status: 'done', area: '开发' },
    { title: '完善 AI 数据共享流程', detail: '接收方、发送前授权和撤回行为', status: 'todo', area: '隐私' },
    { title: '核验功能与设备行为', detail: '运行检查并收集真机证据', status: 'todo', area: '测试' },
    { title: '整理候选版本与审核材料', detail: '所有关口齐备后准备发布', status: 'todo', area: '发布' }
  ], events: [{ title: '交付范围已载入', detail: '本地示例，尚未提交任何实际任务', time: '初始状态' }] }; }
  function validate(s) { return s && s.schema === 1 && typeof s.goal === 'string' && Number.isFinite(s.budget) && s.budget > 0 && Number.isInteger(s.revision) && Array.isArray(s.tasks) && s.tasks.length === 5 && s.tasks.every(t => typeof t.title === 'string' && ['done', 'running', 'todo'].includes(t.status)) && s.decisions && typeof s.decisions.brand === 'string' && typeof s.decisions.privacy === 'string' && typeof s.connected === 'boolean' && Array.isArray(s.events) && s.events.every(e => e && typeof e.title === 'string' && typeof e.detail === 'string' && typeof e.time === 'string') && (s.run === null || ['running', 'paused', 'needs_decision', 'completed', 'canceled'].includes(s.run.status)); }
  function pending(s) { return Object.keys(s.decisions).filter(k => !s.decisions[k]); }
  function event(s, title, detail) { s.events.unshift({ title, detail, time: new Date().toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' }) }); s.events = s.events.slice(0, 30); }
  function requireConnection(s) { if (!s.connected) throw Error('请先连接示例后端，再操作运行。'); }
  function active(s) { return s.run && ['running', 'paused', 'needs_decision'].includes(s.run.status); }
  function save(s, goal, budget, type) { if (active(s)) throw Error('运行中的计划已固定，请先结束当前示例运行。'); if (!goal.trim()) throw Error('请填写交付目标。'); if (!Number.isFinite(budget) || budget < 1 || budget > 1000) throw Error('预算应为 1 到 1000 元。'); s.goal = goal.trim(); s.title = Array.from(s.goal).slice(0,28).join(''); s.decisions = { brand: '', privacy: '' }; s.tasks = initial().tasks; s.budget = budget; s.type = type; s.revision++; s.run = null; event(s, '计划已保存', `版本 ${s.revision}，等待运行`); }
  function start(s) { requireConnection(s); if (active(s)) throw Error('当前交付已有活跃运行。'); s.run = { id: `CI-${String(s.revision + 41)}`, revision: s.revision, status: 'running', steps: 0 }; s.tasks.forEach((t, i) => t.status = i < 2 ? 'done' : i === 2 ? 'running' : 'todo'); event(s, '示例运行已创建', `绑定计划版本 ${s.revision}，没有执行真实 CI`); }
  function pause(s) { requireConnection(s); if (s.run?.status !== 'running') throw Error('只有运行中的任务可以暂停。'); s.run.status = 'paused'; event(s, '示例运行已暂停', '下一项任务暂不推进'); }
  function resume(s) { requireConnection(s); if (!s.run || !['paused', 'needs_decision'].includes(s.run.status)) throw Error('当前运行不能恢复。'); if (s.run.status === 'needs_decision' && pending(s).length) throw Error('请先处理待决定事项。'); s.run.status = 'running'; event(s, '示例运行已恢复', '继续固定版本的计划'); }
  function next(s) { requireConnection(s); if (s.run?.status !== 'running') throw Error('当前运行不能推进。'); if (pending(s).length) { s.run.status = 'needs_decision'; event(s, '需要产品与隐私决定', '本地决定不会替代正式检查和发布授权'); return; } const current = s.tasks.findIndex(t => t.status === 'running'); if (current < 0) throw Error('没有可推进的步骤。'); s.tasks[current].status = 'done'; s.run.steps++; if (current + 1 < s.tasks.length) s.tasks[current + 1].status = 'running'; else s.run.status = 'completed'; event(s, s.run.status === 'completed' ? '示例执行完成' : '示例步骤完成', s.tasks[current].title + '；未产生真实测试或签名制品'); }
  function cancel(s) { requireConnection(s); if (!active(s)) throw Error('没有可取消的运行。'); s.run.status = 'canceled'; s.tasks.forEach(t => { if (t.status === 'running') t.status = 'todo'; }); event(s, '示例运行已取消', '保留当前计划和事件记录'); }
  function decide(s, key, value) { if (!Object.hasOwn(s.decisions, key) || !value.trim()) throw Error('请选择并说明一个决定。'); s.decisions[key] = value.trim(); event(s, '本地决定已记录', key === 'brand' ? '名称路线已记录，权利与元数据仍待验收' : '数据共享方案已记录，真实行为仍待验收'); }
  root.CIModel = { initial, validate, pending, active, save, start, pause, resume, next, cancel, decide, evidence, stages, clone };
})(globalThis);
