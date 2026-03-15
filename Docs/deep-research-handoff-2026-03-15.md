# DeskPins 深度研究交接文档（2026-03-15）

## 1. 目标与使用方式

这份文档用于把当前 `macOS DeskPins` 项目现状、风险点、可优化方向一次性交给 GPT deep research。  
你可以直接复制第 9 节的 Prompt 进行深研，再把结果带回新的 Codex 窗口继续实现。

## 2. 项目快照

- 仓库：`/Users/lzc/Documents/科研/deskpins尝试`
- 分支：`codex/feat-screen-recording-overlay`
- 当前模式：菜单栏 App + Accessibility +（实验分支）ScreenCaptureKit 镜像覆盖层
- 核心架构：
- `App/MenuBarApp/main.swift`：交互状态机、刷新节拍、overlay lease 管理
- `App/Support/DeskPinsMenuBarStateController.swift`：pin store、排序与 overlay target 策略
- `Core/Overlay/PinnedWindowOverlayManager.swift`：preview/dragHandle/badge 三层 overlay
- `Core/Overlay/WindowPreviewCapturer.swift`：SCStream 建流与最新帧缓存
- `Core/Accessibility/*`：焦点读取、窗口激活、窗口移动

## 3. 已落地能力（当前可用）

- 支持“镜像式 pin 内容置顶”，不是纯边框方案。
- 多 pin 窗口顺序策略已落地（后 pin 在上，交互后上浮）。
- 拖动稳定性显著提升（拖动期缓存、暂停截图刷新、60Hz 合并）。
- 边界光标异常已做过一轮收敛修复。
- 已支持点击 `📌` 徽标触发 unpin。
- 新增 `Unpin All Windows` 菜单项。
- 退出终端/收到终止信号时会清空全部 pin（避免下次启动残留）。
- live focus 识别新增 `windowNumber`（`AXWindowNumber`）并接入匹配链路。

## 4. 当前痛点（待深研重点）

### P0：浏览器窗口工作区点击后优先级掉落

- 现象：pin 的 Chrome/浏览器窗口，点击工作区后会立刻被其它 pin 覆盖。
- 特征：高频复现，不是偶发。
- 影响：核心 pin 语义被破坏（“正在操作的 pin 应保持最上”）。

### P0：两个 pin 工作区切换偶发“要点两次”

- 现象：A/B 两个 pin 之间依次点击工作区，第一次点击偶尔无效，仍是旧窗口在上；第二次才切过来。
- 影响：交互切换不确定，体感像“卡输入路由”。

### P1：lease/排序状态机复杂且可能存在竞态

- 目前同时存在：
- 后台 refresh 定时器（80ms）
- lease acquiring/active 状态转移
- live focus 轮询握手
- overlay suppressed 与 direct owner 策略
- 这些路径交错时可能发生“视觉置顶”和“真实输入焦点”短时不一致。

### P1：文档与实现边界有漂移风险

- `Docs/permission-model.md` 与 MVP 文档强调“默认不请求 Screen Recording”。
- 但当前分支是镜像覆盖层实验分支，已依赖 ScreenCaptureKit。
- 需要产出更清晰的“主线/MVP vs 实验分支”边界说明，减少后续决策歧义。

## 5. 可能根因假设（供 deep research 验证）

- 假设 A：`frontmost app` 与 `focused window` 在浏览器场景切换时存在短暂不一致，导致 lease 提前清理或未激活。
- 假设 B：浏览器 Tab/WebView 标题变化、窗口属性波动导致弱匹配误判，即使已补 `windowNumber` 仍会偶发落错目标。
- 假设 C：overlay 的可见层级和输入命中层级没有严格对齐，导致视觉在 A、输入实际落到 B 或系统下层。
- 假设 D：后台 refresh 在 lease 关键窗口期回写排序，覆盖了“刚交互窗口应置顶”的即时语义。
- 假设 E：direct mode 的 drag handle/preview/badge 组合在某些 App 上仍形成“输入遮挡岛”。

## 6. 优化方向（建议优先级）

### 方向 1（P0）：强化“交互置顶锁”

- 在内容区点击触发时，对 owner 设置短时强置顶锁（例如 200~400ms）。
- 锁期内禁止任何自动排序回写覆盖 owner 的 top 状态。
- 锁释放条件：focus 确认稳定、或明确切换到其它 pin owner。

### 方向 2（P0）：建立“焦点确认握手”双通道

- 通道一：AX focused window 精确匹配（含 `windowNumber` + bounds）。
- 通道二：frontmost application + 最佳候选窗口评分。
- 两通道冲突时，采用显式状态：`acquiring` 延长/重试，而不是直接 fallback 到 `none`。

### 方向 3（P0）：输入命中与可见层严格一致

- direct owner 可交互期间，重叠竞争窗口至少 suppress preview。
- 进一步评估 suppress 时 drag layer 是否也应禁用（而非仅隐藏 preview）。
- 明确每种 `renderPolicy` 下三层窗口（preview/drag/badge）的“可见 + 可点击”矩阵。

### 方向 4（P1）：切换延迟收敛

- 减少“切换路径”对全量菜单重建的依赖，只更新 overlays。
- 将切换关键路径从“等后台 tick”改为“即时驱动 + 短轮询确认”。
- 明确区分“视觉切换成功时间”和“输入接管成功时间”。

### 方向 5（P1）：增强可观测性

- 增加关键埋点：
- content click 到 lease active 的耗时分布（P50/P95）
- lease 超时率
- owner 被覆盖事件计数
- 双击才切换事件计数
- 通过数据判断是匹配问题、排序问题还是输入层问题。

## 7. 建议 deep research 输出物（必须要求）

- 输出 1：根因优先级列表（按证据强弱排序）。
- 输出 2：推荐状态机（带状态/事件/转移条件/超时策略）。
- 输出 3：按文件粒度的改造方案（`main.swift` / `StateController` / `OverlayManager` / `FocusedWindowReader`）。
- 输出 4：最小风险分阶段实施计划（每阶段可独立回滚）。
- 输出 5：量化验收指标与压测方案（延迟、误切换率、覆盖率）。
- 输出 6：失败模式与回滚开关设计。

## 8. 技术边界与约束（必须遵守）

- 仅使用公开 API（禁止私有 API、注入、SIP 相关方案）。
- 保持现有流畅度收益，不允许回退到明显残影/卡顿。
- 保持核心产品语义：
- pin 后内容置顶
- 后 pin 在上
- 点击/拖动哪个 pinned 窗口，哪个应立即上浮
- 多窗口重叠时，视觉与输入目标必须一致
- 兼容当前实验分支 ScreenCaptureKit 路线，不推翻已有 SCStream 化成果。

## 9. 可直接复制的 GPT Deep Research Prompt（中文版）

```text
# 角色设定
你是资深 macOS Windowing + Accessibility + ScreenCaptureKit 架构工程师，擅长处理 overlay 输入路由、窗口层级竞态与交互状态机设计。

# 任务描述
我在做一个 macOS DeskPins 风格工具（分支：codex/feat-screen-recording-overlay）。目前已实现镜像覆盖层 pin，性能问题大幅改善，但仍有关键交互 bug：

1) 对 Chrome/浏览器这类窗口，点击 pinned 窗口工作区后，窗口会立刻掉到后面，被其他 pinned 窗口覆盖（高频复现）。
2) 在两个 pinned 窗口之间切换时，偶发第一次点击工作区无效，要点第二次才切换置顶。

请基于以下代码路径和架构，给出“可落地、低回归风险”的最终方案：
- App/MenuBarApp/main.swift（lease 状态机、refresh 节拍、交互事件）
- App/Support/DeskPinsMenuBarStateController.swift（pin 排序、overlay target、focus 匹配）
- Core/Overlay/PinnedWindowOverlayManager.swift（三层 overlay：preview/drag/badge）
- Core/Overlay/WindowPreviewCapturer.swift（SCStream 建流 + 最新帧缓存）
- Core/Accessibility/FocusedWindowReader.swift / FocusedWindowSnapshot.swift（live focus）

# 已知约束
- 只能用公开 API。
- 当前分支可接受 Screen Recording（已做镜像）。
- 不能回退现有流畅度（低卡顿、低残影）。
- 必须保持 pin 语义：后 pin 在上；点击/拖动哪个 pinned 窗口，哪个立即上浮。

# 你必须输出
1) 根因分析（按证据强弱排序，至少给出 3 条最可能根因）。
2) 推荐状态机（状态、事件、转移条件、超时与降级策略）。
3) 分阶段实施计划（Phase 1/2/3），每阶段包含：
   - 改哪些文件
   - 核心改动点
   - 为什么低风险
   - 如何验证
4) 关键伪代码或 Swift 代码草案（至少给出 lease 关键逻辑与排序保护逻辑）。
5) 监控与验收指标（P50/P95 切换耗时、误切换率、覆盖错误率）。
6) 回滚方案（feature flag 或开关策略）。

# 输出格式
请严格按以下 Markdown 结构输出：
## A. Root Cause Ranking
## B. Final State Machine
## C. Implementation Plan (Phase 1-3)
## D. Code-Level Changes (by file)
## E. Metrics & Test Plan
## F. Risk & Rollback

# 额外要求
- 如果你提出多个可行方案，请给出“主推方案 + 备选方案”，并明确取舍理由。
- 每个关键结论尽量给出可验证证据或验证方法，而不是泛泛建议。
```

## 10. 可选二次追问 Prompt（用于深研结果收敛）

```text
请基于你上一轮建议，继续输出“最小可实现补丁计划”：
1) 仅保留 3~6 个必要改动点；
2) 每个改动点给出伪代码与预期副作用；
3) 给出逐步上线顺序（每一步都可独立验证并可回滚）；
4) 明确哪些现有逻辑必须保留不可动（避免性能回退）。
```

