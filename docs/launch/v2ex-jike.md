# V2EX / 即刻 / 少数派 — 中文社区帖

## V2EX 节点
- `分享创造`（首选）
- 备用：`macOS`、`Claude`

## 标题（≤30 字）

```
[分享创造] mypet —— 一只吃你 Claude Code 额度的桌面小猫
```

## 正文

```
背景：付了 Claude Code 订阅之后，下班时段额度一直空着。想给它找个"被消耗
"的理由，于是写了这只猫。

## 它是什么

macOS 13+ 的桌面宠物。猫住在屏幕右下角，鼠标悬停 1 秒喂它一口 token：
它会调一次本地的 `claude -p`，把返回结果用气泡冒出来。

每次返回内容按权重轮换：

| 主题 | 权重 | 给你 |
|---|---|---|
| ☕ Claude Code 技巧 | 30% | 你日常用 CC 但没发现的小用法 |
| 💡 Prompt | 20% | 一条现在就能粘进 CC 的 prompt |
| 📰 科技新闻 | 18% | 一句话头条 |
| 🤓 TIL | 14% | 老兵都觉得有意思的小知识 |
| 😆 笑话 | 10% | 程序员一句话冷笑话 |
| 🍂 俳句 | 8% | 程序员俳句（5/7/5）|

## 它不是什么

- 不需要 Anthropic API key（它跑你已经登录的 `claude` CLI）
- 没遥测、没 server、没登录
- 不喂的时候 0% CPU（SwiftUI 的 TimelineView 只在交互时跑）
- 不挡操作（透明 borderless 窗口、点击穿透）

## 一些细节

- 点气泡复制 tip 到剪贴板，菜单栏 🐾 保留最近 10 条
- 拖到屏幕边缘自动吸附
- 60 秒喂一次冷却，期间会告诉你「还在消化呢」
- 单 binary：`swift build && swift run mypet`

## 开源 + 仓库

MIT。87 单测，GitHub Actions 在 macos-13 上跑：
https://github.com/anzy-renlab-ai/mypet

欢迎试，欢迎拍砖，欢迎 issue 提主题权重建议。
```

## 即刻

字数限制更紧，删掉表格只留三行：

```
给 Claude Code 订阅写了只桌面小猫。

鼠标悬停 1 秒 → 小猫吃一口 token → 气泡冒一条
tip / prompt / TIL / 俳句 / 笑话 / 头条。
零 CPU 待机，单 binary，MIT。

github.com/anzy-renlab-ai/mypet 🐾
```
配 GIF。

## 少数派

少数派欢迎结构化长文。建议结构：
1. 痛点（CC 订阅闲置）
2. 设计取舍（emoji vs 自绘、为什么轮换主题、为什么 click-to-copy）
3. 技术细节（zero-CPU 关键点、SwiftUI hover 处理 Timer 陷阱、subprocess wrapper）
4. Roadmap（自定义 prompt、贴纸支持、皮肤包）

可以把 CHANGELOG 里的"内部"段落扩出来当一节。
