# DualSense Codex

用 PS5 DualSense 手柄控制 macOS 上的 Codex / ChatGPT 桌面会话：按住听写、选择会话、排队或立即发送消息、滚动聊天内容，以及接收回合结束震动提醒。

[English](README.en.md) · [MIT License](LICENSE) · [贡献指南](CONTRIBUTING.md) · [更新记录](CHANGELOG.md)

这是社区开发的原生菜单栏工具，使用 Swift、AppKit、GameController 和 Core Haptics，无第三方运行依赖、账号或 API Key。与 Sony、OpenAI 无隶属关系。

## 兼容性

- macOS 12 或更新版本；需要带 Swift 编译器和 macOS SDK 的 Xcode Command Line Tools 或 Xcode。
- PS5 DualSense，蓝牙或 USB 数据线连接。标准 DualSense 已在 Apple Silicon Mac 上实机使用；DualSense Edge 依赖同一系统接口，但未实机验证。Intel 构建未实机验证。
- **目标应用的 bundle ID 必须是 `com.openai.codex`**。开发环境中的应用名称为 ChatGPT，但并非所有名为 ChatGPT 的应用都具有此 ID。普通浏览器网页和其他 bundle ID 不在支持范围内。
- 快捷键按开发时的桌面版本实现；应用更新或自定义快捷键可能改变行为。当前源码版本：`0.6.2`。

## 安装

```sh
xcode-select --install # 已有开发工具可跳过
bash build.sh "$HOME/Applications/DualSense Codex.app"
open "$HOME/Applications/DualSense Codex.app"
```

菜单栏出现 🎮 后，在 **系统设置 → 隐私与安全性 → 辅助功能** 添加并启用刚构建的应用。部分新版 macOS 将这一页面称为 **Device Control and Data Access**。授权状态会在 🎮 菜单中自动刷新。

建议构建到上述个人 Applications 目录。某些同步目录会为 `.app` 添加 Finder 属性，导致签名校验失败。

构建使用 **ad hoc 临时签名**，不是 Developer ID 签名或公证分发。重新编译后 macOS 可能不再认可原来的辅助功能授权；即使设置开关仍开启，也可能需要删除旧条目并重新添加当前应用。这是已知限制。

## 按键

映射只在目标应用位于前台、且 🎮 菜单的「启用按键映射」开启时工作。

| 控件 | 功能 |
| --- | --- |
| □ | 按住听写（Control + Shift + D），松开结束 |
| △ | 启动语音对话（Control + Shift + V） |
| × | Return：选择菜单项、发送消息或确认当前界面操作 |
| ○ | Escape：返回、取消或执行当前界面的 Escape 行为 |
| Options / 菜单键 | 打开命令菜单，包含最近会话（Command + Shift + P） |
| 方向键 | 在菜单中选择；其他界面使用原生方向键行为 |
| 左摇杆 | 滚动聊天内容；Options 菜单中选择项目 |
| L1 / R1 | 上一个 / 下一个标签（Command + Shift + `[` / `]`），行为由焦点决定 |
| R2 轻按并松开 | 排队发送（Enter） |
| R2 深按 | 立即介入正在执行的任务（Command + Enter） |

**× 和 ○ 是实际键盘事件，并非只作用于聊天框。** 在确认或审批界面中，它们可能执行相应的确认或取消操作，请根据当前界面使用。

### R2：轻按排队，深按立即发送

先聚焦消息输入框并结束听写。R2 超过 18% 行程记为有效轻按，回到 8% 以下时发送；到达 82% 时立即发送一次，此后松开不会再次发送。菜单、输入框失焦、切出应用或暂停会取消待发送手势。这里读取的是扳机行程，不是敲击力度。

这组映射要求 ChatGPT 设置为 **Enter 发送、任务进行中默认排队**。改变 Enter 行为或后续消息默认模式后，两个快捷键的含义可能互换。立即发送表示提交介入指令，不保证任务马上响应。

### 左摇杆与聊天区域

先点击一次对话输入框。工具根据它的辅助功能边界定位同一列上方的聊天内容，每次滚动重新读取位置，以适应侧边栏、分栏和窗口移动。摇杆回中停止，推得越远滚动越快，中心死区为 22%。

定位是基于输入框几何信息的启发式方法，不是 ChatGPT 官方滚动 API。多个编辑器、隐藏输入框或特殊布局仍可能无法识别；此时 🎮 菜单会提示重新聚焦输入框。鼠标关闭 Options 菜单后若导航模式没有清除，可点击对话输入框或切出再切回应用。

### 麦克风和触摸板

本工具不录音、不控制系统麦克风静音，也不会出现独立麦克风菜单栏图标。录音由目标应用处理，请使用 Mac 或耳机麦克风；不要依赖 DualSense 内置麦克风在 macOS 上收音。触摸板滑动和按下当前没有映射。

## 可选：回合结束震动

菜单栏 🎮 →「测试：两次短震动」可测试硬件。震动不要求目标应用位于前台；主工具必须运行且手柄已连接。

```sh
python3 install-hooks.py
```

安装器把 [hooks.example.json](hooks.example.json) 中的一个 `Stop` hook 合并到 `$CODEX_HOME/hooks.json`（默认 `~/.codex/hooks.json`），保留其他 hooks，并在首次修改已有文件时备份为 `hooks.json.before-dualsense`。它不会覆盖现有 `notify` 配置。示例命令假设应用安装在 `~/Applications`。

安装后，通过支持 hooks 的 Codex 客户端审阅并信任该 hook；CLI 中可使用 `/hooks`。客户端版本与 hook 格式必须兼容，可能需要重新加载会话。不要直接修改信任记录。

流程：`Stop` JSON → `DualSenseNotify` → 本地通知 → 两次短震动。只读取事件类型、session ID 和 turn ID，不读取回复正文；去重并限制提醒频率。

**Stop 是一轮回复结束事件，不是项目验收成功的证明。** 其他 hook 仍可能要求继续运行。辅助程序的输入校验已测试；自动提醒是否执行还取决于客户端支持与 hook 信任状态，尚未完成所有客户端版本的端到端验证。

## 开发与检查

```sh
bash test.sh                         # 无手柄、无 UI 操作、无发送消息
bash build.sh                       # 构建到 build/DualSense Codex.app
```

`test.sh` 检查听写按键生命周期、R2 阈值与取消、菜单模式、侧边栏坐标计算、hook 输入和安装器的合并/幂等行为。GitHub Actions 在 macOS 上运行这些检查并构建应用。单元测试通过不等同于所有布局和硬件都已验证。

诊断模式会监听 15 秒，不发送键盘事件：

```sh
"$HOME/Applications/DualSense Codex.app/Contents/MacOS/DualSenseCodex" --diagnose
```

运行前先退出菜单栏工具，避免两个实例并行监听。诊断输出可以确认按键、连接和接口能力；诊断进程的权限归属可能不同，GUI 菜单中的授权状态才是实际工具的状态。

## 隐私与权限

应用没有网络请求、遥测或云端账号。辅助功能权限用于读取当前窗口与输入控件的角色/位置，并发送键盘、滚动事件。它不保存聊天内容。语音录制、转写以及发送消息仍由目标应用处理，遵循该应用的数据政策。

本地震动通知不是身份认证接口；同一登录会话中的其他进程也能发送同名通知。它只触发震动，不执行命令或接收聊天正文。

## 卸载

1. 从 🎮 菜单退出工具，删除 `~/Applications/DualSense Codex.app`。
2. 在系统辅助功能设置中移除它的条目。
3. 如安装过 hook，仅从 `hooks.json` 删除命令指向 `DualSenseNotify` 的那一项，保留其他 hooks。

没有安装开机启动项或后台服务。
