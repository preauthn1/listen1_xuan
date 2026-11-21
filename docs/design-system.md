# Listen1 Xuan 桌面 UI 设计系统

来源：taste-skill（单一系统、真实品牌色、语义对比度）与 ui-ux-pro-max（Flutter stack、Touch/Accessibility 规则）。

## 规则

- **一套控件**：所有 Filled/Elevated/Outlined/Text 按钮统一为胶囊形，最小 40px 高，水平 16px 内边距，标签 `labelLarge` w500，不加文本装饰。主题定义在 `lib/controllers/theme.dart`，页面不得再写第二套按钮样式。
- **间距**：只用 4/8/12/16/24/32。相邻可点击控件之间至少 8px，列表行之间 12px，分隔线上下 12–16px。
- **颜色**：界面以中性色为主，颜色只来自主题 `ColorScheme`。次要文字用 `onSurfaceVariant`，禁止 `Colors.grey` 等原始灰色。禁用态保持可读，并在旁边写明原因。
- **品牌图标**：第三方平台 logo 保留原有品牌色，不做染色或灰度处理。哔哩哔哩使用 `#FB7299`。
- **文字**：正文不小于 12px。中英文之间加空格（`WebSocket 服务器`、`设置 Cookie`）。按钮标签单行显示，不换行。
- **信息分配**：行左侧放平台名称和状态，右侧只放简短动作（`登录`、`登录 / Cookie`）。
- **标题栏**：Windows 上只保留一层自定义标题栏，按钮从左到右为：置顶 → 最小化 → 最大化/还原 → 关闭。
- **动效**：悬停 150ms 进、120ms 出，不使用回弹效果，也不对宽高做动画。
