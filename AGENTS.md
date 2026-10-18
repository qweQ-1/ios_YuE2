# AI 协作规则

- 本项目用 [ios-ci-workflows](https://github.com/wenjinliuu/ios-ci-workflows) 编译和测试；本地不跑 Xcode。改完代码 push，读 Build & Test 的测试报告再修。
- App 仓库结构：`YuE2Studio/`（SwiftUI 源码，XcodeGen 工程由 `project.yml` 生成）、`YuE2StudioTests/`（逻辑测试）、`server/`（Python 服务端）、`ci/`（本机不跑的辅助脚本可留空说明）、`.ios-ci.yml`（CI 配置）。
- 新功能必须带测试；能用逻辑测试验证的不写成 UI 测试；UI 测试按条件等待，不用 sleep 固定等。
- 删测试只有三种理由：功能已删除、和另一个测试完全重复、已被更便宜的测试覆盖；删测试、改断言的预期值都要在提交里写明理由。
- 有意改了界面：手动运行 Build & Test 并勾选 record_snapshots，再跑一次确认变绿，并说明改了哪些页面。
- PR 上只跑快线（逻辑、迁移、快照）；改了界面交互、关键流程或 UI 测试时，合并前手动跑一次 Build & Test 的 ui（或 full）。
- **API 契约在 `docs/API.md`**：iOS 客户端（`YuE2Studio/Networking/YuE2Client.swift`）与 Python 服务端（`server/`）都按它实现；改契约必须同步两边和文档，并各带测试。
- 服务端测试：`cd server && python -m pytest tests -q`（stub 模式不依赖 GPU；GitHub Actions 的 Server Tests 会跑）。真模型路径仅在 GPU 机器验证。
- 部署只走 git → CI；不要在工作流 YAML、日志或提交里写明文密钥。
- 更多细节见 ios-ci-workflows 的 Skill：skills/ios-ci-workflows/SKILL.md。
