# DeskPins Release Draft `v0.1.0-beta.1`

This file is a copy-ready release draft for GitHub Releases in both English and Chinese.

## English (Copy-ready)

### Title

`DeskPins v0.1.0-beta.1 — Public Beta (Menu Bar Pinning for macOS)`

### Release Body

DeskPins is an open-source macOS menu bar utility for pinning important windows in front of your workflow using public APIs.

This beta focuses on interaction stability, predictable pin ordering, and cleaner repository structure for open-source collaboration.

#### Highlights

- Menu bar-first pinning workflow
- Pin current focused window, or pin from the visible-window list
- Multi-window pin management with interaction-aware ordering
- Overlay architecture with preview / drag / badge layers
- Global shortcut support (`Control-Option-Command-P`)
- Persisted pin state in Application Support

#### Stability Improvements in This Beta

- Improved lease transition behavior for pinned-window interaction handoff
- Suppression logic now applies in a safer interaction phase
- Better overlap filtering to reduce accidental suppression
- Reduced hot-path persistence pressure to improve responsiveness
- Expanded smoke tests for lease/suppression regression coverage

#### Open-Source Repository Improvements

- Refined README for faster onboarding
- Added `CONTRIBUTING.md`
- Added issue templates for bug reports and feature requests
- Removed temporary deep-research handoff artifacts from the public repo

#### Permissions

- Baseline mode: Accessibility
- Experimental mirrored-content mode: Accessibility + Screen Recording

#### Known Boundary

DeskPins does not promise absolute system-level always-on-top semantics for every third-party window object.  
It follows a public-API-first approach and prioritizes overlay consistency and recoverable behavior.

#### Verification

- `./Scripts/verify.sh` passes
- SwiftPM build passes
- Smoke test executables pass

#### Feedback

If you hit a bug, please open an issue and include:

- macOS version
- reproduction steps
- expected vs actual behavior
- logs or screenshots when possible

---

## 中文（可直接复制）

### 标题

`DeskPins v0.1.0-beta.1 — 公测版（macOS 菜单栏置顶工具）`

### 发布正文

DeskPins 是一个开源的 macOS 菜单栏窗口置顶工具，基于公开 API 实现，强调轻量、可解释和可维护。

本次 Beta 重点放在交互稳定性、置顶顺序可预期性，以及开源仓库可读性。

#### 主要能力

- 菜单栏优先的 pin/unpin 交互
- 支持“置顶当前焦点窗口”与“从可见窗口列表置顶”
- 支持多窗口置顶管理（基于交互的排序策略）
- overlay 三层结构：preview / drag / badge
- 全局快捷键支持（默认 `Control-Option-Command-P`）
- 置顶状态持久化（Application Support）

#### 本次 Beta 的稳定性优化

- 改进了 pinned 窗口交互切换时的 lease 转移行为
- 将 suppression 的生效阶段调整为更安全的交互阶段
- 优化窗口重叠判定，降低误 suppress
- 降低高频交互路径写盘压力，改善响应体验
- 增补 lease/suppression 相关 smoke 测试，增强回归防护

#### 开源仓库可用性优化

- 重构 README，提高首次上手效率
- 新增 `CONTRIBUTING.md`
- 新增 issue 模板（Bug / Feature Request）
- 清理仅供内部流转的深研交接文档

#### 权限说明

- 基础模式：Accessibility
- 实验镜像模式：Accessibility + Screen Recording

#### 已知边界

DeskPins 不承诺对所有第三方窗口提供绝对系统级 always-on-top 语义。  
项目遵循公开 API 优先路线，核心目标是 overlay 一致性与可恢复行为。

#### 验证状态

- `./Scripts/verify.sh` 已通过
- SwiftPM 构建通过
- Smoke tests 全通过

#### 反馈建议

提交 issue 时请尽量附带：

- macOS 版本
- 复现步骤
- 预期行为 vs 实际行为
- 日志或截图（若有）
