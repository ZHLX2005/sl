---
name: antd-reference
description: |
  Ant Design (antd) 是 React 生态最成熟的中后台 UI 组件库。
  当用户在 React 项目中使用 antd 组件、配置主题、解决 antd 集成问题、
  询问 antd 组件的导入方式或 API 时加载本 ref。
---

# Ant Design 使用技能

> 本文档是 [[antd]] 的专项参考。原为独立 skill，已合并至 ui-component-library 主索引。

## 适用场景
- React 项目中需要中后台 UI 组件
- 询问 antd 组件的导入方式、API、Props
- 配置 antd 主题、暗黑模式、国际化
- 与 antd v4/v5/v6 版本升级相关的问题

## 不适用
- Vue 项目（请用 element-plus 或 naive-ui）
- 非 UI 类需求

## 快速链接
- 组件级详细文档：[form](./form.md) / [data-display](./data-display.md) / [feedback](./feedback.md) / [navigation](./navigation.md) / [layout](./layout.md) / [others](./others.md)
- 官方文档：https://ant.design

## 安装与初始化

### npm / pnpm / yarn
```bash
npm install antd --save
# 或 pnpm add antd
# 或 yarn add antd
```

### 完整引入
```tsx
import React from 'react';
import { Button, ConfigProvider } from 'antd';
import 'antd/dist/reset.css';

const App = () => (
  <ConfigProvider theme={{ token: { colorPrimary: '#1677ff' } }}>
    <Button type="primary">Primary</Button>
  </ConfigProvider>
);
```

### 按需引入（推荐）
- antd v5/v6 默认支持 tree-shaking，无需额外插件。
- 仅 import 需要的组件即可，Webpack/Vite 会自动 tree-shake。

## 常用组件导入示例

### Button
```tsx
import { Button, Space } from 'antd';
<Space>
  <Button type="primary">Primary</Button>
  <Button>Default</Button>
  <Button type="dashed">Dashed</Button>
</Space>
```

### Form
```tsx
import { Form, Input, Button } from 'antd';
const [form] = Form.useForm();
<Form form={form} onFinish={(values) => console.log(values)}>
  <Form.Item name="username" rules={[{ required: true }]}>
    <Input />
  </Form.Item>
  <Button htmlType="submit">提交</Button>
</Form>
```

### Table
```tsx
import { Table } from 'antd';
import type { TableColumnsType } from 'antd';

const columns: TableColumnsType = [
  { title: 'Name', dataIndex: 'name' },
  { title: 'Age', dataIndex: 'age' },
];
<Table columns={columns} dataSource={data} rowKey="id" pagination={{ pageSize: 10 }} />
```

### Modal（受控）
```tsx
import { Modal, Button } from 'antd';
import { useState } from 'react';

const [open, setOpen] = useState(false);
<Button onClick={() => setOpen(true)}>Open</Button>
<Modal
  open={open}
  onOk={() => setOpen(false)}
  onCancel={() => setOpen(false)}
>
  content
</Modal>
```

### DatePicker
```tsx
import { DatePicker } from 'antd';
import dayjs from 'dayjs';

<DatePicker />
<DatePicker.RangePicker />
<DatePicker defaultValue={dayjs()} format="YYYY-MM-DD" showTime />
```

## 组件分类速查
完整的 84+ 组件清单请参考各分类主题文档：

- Form & Input：[form](./form.md)
- Layout：[layout](./layout.md)
- Navigation：[navigation](./navigation.md)
- Data Display：[data-display](./data-display.md)
- Feedback：[feedback](./feedback.md)
- Other：[others](./others.md)

- Form & Input：`Button`、`Form`、`Input`、`Select`、`DatePicker`、`Upload` 等
- Layout：`Row`、`Col`、`Flex`、`Grid`、`Layout`、`Space`、`Splitter`
- Navigation：`Menu`、`Dropdown`、`Pagination`、`Breadcrumb`、`Steps`
- Data Display：`Table`、`Card`、`List`、`Tabs`、`Tree`、`Typography`
- Feedback：`Alert`、`Drawer`、`Message`、`Modal`、`Notification`、`Progress`、`Spin`
- Other：`App`、`ConfigProvider`、`ColorPicker`、`FloatButton`、`QRCode`、`Tour`、`Watermark`

## 主题定制

```tsx
import { ConfigProvider, theme } from 'antd';

<ConfigProvider
  theme={{
    token: {
      colorPrimary: '#1677ff',
      borderRadius: 6,
    },
    algorithm: theme.darkAlgorithm, // 暗黑模式
    cssVar: true, // CSS 变量模式
    hashed: true, // className 哈希
  }}
>
  <App />
</ConfigProvider>
```

支持 `theme.defaultAlgorithm`（默认）、`theme.darkAlgorithm`（暗黑）和 `theme.compactAlgorithm`（紧凑）。

## 国际化

```tsx
import { ConfigProvider } from 'antd';
import zhCN from 'antd/locale/zh_CN';
import enUS from 'antd/locale/en_US';

<ConfigProvider locale={zhCN}>
  <App />
</ConfigProvider>
```

支持 150+ 种语言，常见语言包包括 `zh_CN`、`en_US`、`ja_JP`、`ko_KR`、`zh_TW`、`fr_FR` 和 `de_DE`。

## TypeScript
antd 完全支持 TypeScript，可直接导入组件 Props 和业务类型：

```tsx
import type { ButtonProps, FormInstance, TableColumnsType } from 'antd';
```

## 样式优先级

根节点样式优先级：ConfigProvider `styles.root` < ConfigProvider `style` < 组件 `styles.root` < 组件 `style`。

## 常见问题

### Q: antd 在 React 19 下报错？
A: antd v6 已内置支持 React 19，不需要补丁。较新的 v5 也已支持；如使用 v5 老版本，可升级 antd 或按对应版本文档使用 `@ant-design/v5-patch-for-react-19`。

### Q: 如何减小打包体积？
A: antd v5/v6 默认 tree-shaking，按需 import 即可。注意不要整体引入未使用的模块。

### Q: 样式不生效？
A: 确认引入 `'antd/dist/reset.css'`；使用 ConfigProvider 时确保包裹在最外层，并检查全局 CSS 或 CSS-in-JS 的样式优先级。

### Q: 如何使用 message、notification 或 modal 的上下文？
A: 在应用顶层使用 antd 的 `App` 组件包裹业务内容，再通过其上下文 API 调用反馈组件。

## 版本信息
- 当前版本：6.5.2
- 兼容：React 18+、TypeScript
- 模块入口：CommonJS `lib/index.js`、ES Module `es/index.js`
- 官方文档：https://ant.design
