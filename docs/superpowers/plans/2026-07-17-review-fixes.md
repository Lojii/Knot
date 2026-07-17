# Knot Review 修复实现计划

> **For agentic workers:** 按 superpowers:executing-plans 逐任务执行。每个任务独立可验证。

**Goal:** 修复代码 review 发现的安全严重问题、正确性 bug、资源泄漏与热路径性能问题。

**Architecture:** 分 Swift（KnotWebService / TunnelServices，均可 `swift build` 验证）与 Dart（`dart analyze` + `flutter test` 验证）两侧。按安全 → 正确性 → 泄漏 → 性能顺序推进，每项独立提交。

**Tech Stack:** Swift NIO, SQLite; Flutter + GetX。

**状态（2026-07-17）：** 阶段 1–4 全部完成；阶段 5 完成 payload 真流式（C3），DB 下 event loop（C2/H4）仍待定；阶段 6 完成数据保留（含 4 个新 Swift 测试）。验证：`dart analyze` 干净、Flutter 487 测试通过、KnotStorage 12 测试通过、三个 Swift 包全部编译通过。另修复了一个阻断 TunnelServices 编译的历史遗留问题（删除孤立的 BreakpointHandler.swift）。

**验证命令：**
- Dart: `cd <root> && dart analyze lib test && flutter test`
- KnotWebService: `cd native/KnotWebService && swift build`
- TunnelServices: `cd native/TunnelServices && swift build`

---

## 阶段 1 — 安全：本地 API 鉴权 + 收紧 CORS

### Task 1.1: 生成会话 token 并注入 KnotWebServer

**Files:**
- Modify: `native/KnotWebService/Sources/KnotWebService/Server/KnotWebServer.swift`
- Modify: `native/KnotWebService/Sources/KnotWebService/Server/HTTPRouter.swift`
- Modify: `native/KnotWebService/Sources/KnotWebService/Routes/ResponseHelper.swift`
- Modify: `macos/Runner/AppDelegate.swift`
- Modify: `lib/api/api_client.dart`, `lib/api/ws_client.dart`, `lib/api/proxy_channel.dart`, `lib/controllers/task_controller.dart`

**做法：**
1. `KnotWebServer` 增加 `authToken: String`（构造时传入，AppDelegate 用 `UUID().uuidString` 生成）。
2. `HTTPRouter` 持有 token；在 `route()` 入口对所有 `/api/*` 校验 `Authorization: Bearer <token>`（或 `?token=`），失败返回 401。`GET /`（dashboard）放行。
3. WebSocket 升级 `shouldUpgrade` 校验同一 token（query 参数）。
4. `ResponseHelper` 去掉 `access-control-allow-origin: *`（本地 + token 后不再需要 CORS 放开；dashboard 同源）。补 `OPTIONS` 预检返回 204。
5. AppDelegate `startInProcess` 把 token 通过 method channel 结果 `["port":..., "token":...]` 回传 Flutter。
6. Dart 侧 `startProxy()` 读取 token，`ApiClient`/`WsClient` 每次请求带上。

**验证：** `swift build`（KnotWebService）+ `dart analyze`。

---

## 阶段 2 — 正确性 + 泄漏：SessionRecorder 幂等 + WS 生命周期

### Task 2.1: recordClosed 幂等化

**Files:** Modify `native/TunnelServices/Sources/TunnelServices/Framework/SessionRecorder.swift`

在 `recordClosed()` 顶部加 `private var closed = false` 守卫，已关闭直接 return，避免重复 `closeTask` 双减引用计数。

**验证：** `swift build`（TunnelServices）。

### Task 2.2: 停止抓包断开 WS + 修复退避溢出

**Files:** Modify `lib/controllers/task_controller.dart`, `lib/api/ws_client.dart`

- `toggleCapture` 停止分支加 `Get.find<LiveController>().ws.disconnect()`，并 try/catch 回滚 `isCapturing`。
- `ws_client.dart` 退避 `1 << min(_reconnectAttempts, 5)`；加 `_intentionalClose` 标志，`disconnect()` 后不重连。

**验证：** `dart analyze && flutter test`（含 ws_client_test）。

---

## 阶段 3 — 正确性：任务切换重绑定 + 加载 generation token

### Task 3.1: selectTask 重新绑定推送路由

**Files:** Modify `lib/controllers/task_controller.dart`, `lib/controllers/live_controller.dart`

`selectTask` 改为调用 `LiveController.connectToTask(task.id)` 而非仅 `ws.switchTask`，使监听闭包重新捕获新 taskId。

### Task 3.2: _loadAllFlows 加载代号

**Files:** Modify `lib/controllers/flow_controller.dart`

引入 `int _loadGeneration`；`setTaskId` 自增；分页循环每次 `await` 后检查代号是否过期，过期则放弃。

**验证：** `dart analyze && flutter test`（flow_controller_test, task_controller_test, live_controller_test）。

---

## 阶段 4 — 性能：Dart 热路径

### Task 4.1: flowId→index 映射 + 排序进 controller

**Files:** Modify `lib/controllers/flow_controller.dart`, `lib/controllers/flow_table_controller.dart`, `lib/pages/capture/flow_table.dart`

- `FlowController` 维护 `Map<String,int>`，`updateFlowFromPush` O(1) 查找 + 走防抖路径。
- 排序移入 `FlowTableController.reapplyFilters`（sort 状态变化时也重排）；view 层 `flow_table.dart` 去掉每次 rebuild 的 `toList()+_applySorting`，选中高亮下沉到行级。
- ListView 加 `itemExtent`。

### Task 4.2: body 解压/解码下 isolate

**Files:** Modify `lib/controllers/detail_controller.dart`

`_decompress` 超过阈值（~256KB）走 `compute()`；两个方向 payload 独立错误处理；缓存 decode 后文本。

**验证：** `dart analyze && flutter test`。

---

## 阶段 5 — 性能：Web 服务下 event loop（评估后决定）

Web 服务 SQLite/文件 I/O 移出 NIO event loop、payload 真流式。改动面大、回归风险高，作为独立阶段，需单独确认后再做。

---

## 阶段 6 — 数据保留策略

新增定期清理任务（按任务数/年龄上限），任务停止时 `wal_checkpoint`。独立阶段。
