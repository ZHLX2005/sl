---
name: arco-design-reference
description: |
  Arco Design 是字节跳动开源的 React UI 组件库，配套物料市场与设计语言。
  当用户在 React 项目中使用 Arco 组件、配置主题、解决 Arco 集成问题、
  询问组件导入方式或 API 时加载本 ref。
---

# Arco Design 使用技能

> 本文档是 [[arco-design]] 的专项参考。原为独立 skill，已合并至 ui-component-library 主索引。

## 适用场景
- React 项目中需要企业级 UI 组件（与字节跳动中后台风格一致）
- 询问 Button / Table / Form / Modal / DatePicker.RangePicker 等组件的 API
- 配置 Arco 主题（ConfigProvider + token）、暗黑模式、国际化
- 寻找 antd 之外的 React UI 备选

## 不适用
- Vue 项目（请用 element-plus 或 naive-ui）
- 移动端 H5（应使用 Arco Mobile）

## 快速链接
- 组件级详细文档：[form](./form.md)
- 官网文档：https://arco.design/react/components/overview
- 物料市场：https://arco.design/material
- 主题配置平台：https://arco.design/themes

## 安装与初始化

```bash
npm install @arco-design/web-react
# 图标包
yarn add @arco-design/icons   # 推荐 yarn（仓库使用 yarn 1.22）
pnpm add @arco-design/web-react
```

### 全量引入
```tsx
import '@arco-design/web-react/dist/css/arco.css';
import { Button, ConfigProvider } from '@arco-design/web-react';

<ConfigProvider>
  <Button type="primary">Primary</Button>
</ConfigProvider>
```

### 按需引入（推荐）
```tsx
import Button from '@arco-design/web-react/es/Button';
import '@arco-design/web-react/es/Button/style';
```

配合 `babel-plugin-import`：

```bash
npm install -D babel-plugin-import
```

```json
// .babelrc
{
  "plugins": [
    ["import", {
      "libraryName": "@arco-design/web-react",
      "libraryDirectory": "es",
      "style": true
    }]
  ]
}
```

或使用官方插件 `arco-plugin-style` 自动按需样式。

## 组件清单概览

60+ 组件，按场景分类：

- **表单输入**：Input / InputNumber / InputTag / VerificationCode / AutoComplete / Checkbox / Radio / Select / Switch / Slider / Rate / Form / DatePicker / TimePicker / Upload / Mentions / Transfer / TreeSelect / Cascader / ColorPicker
- **布局**：Layout（Header/Footer/Sider/Content）/ Grid（Row/Col，24 栅格）/ Space / Divider / Card / PageHeader / Collapse / ResizeBox / Split
- **导航**：Menu / Breadcrumb / Pagination / Steps / Dropdown / Anchor / Affix / BackTop
- **数据展示**：Table（含 TableInstance 引用 API、虚拟滚动）/ List / Avatar / Badge / Tag / Calendar / Timeline / Tree / Tabs / Image / Descriptions / Empty / Statistic / Skeleton / Carousel
- **反馈**：Alert / Modal / Drawer / Message / Notification / Popconfirm / Popover / Tooltip / Result / Spin / Progress
- **其他**：Button / ConfigProvider / Icon / Link / Portal / Trigger / Typography / Watermark

## 常用组件导入示例

### Button
```tsx
import { Button, Space } from '@arco-design/web-react';

<Space>
  <Button type="primary" status="danger" loading>Primary Danger</Button>
  <Button type="dashed">Dashed</Button>
  <Button type="text">Text</Button>
  <Button type="secondary" shape="round" size="large">取消</Button>
</Space>
```

类型：`default | primary | secondary | dashed | text | outline`
状态：`default | warning | danger | success`
尺寸：`mini | small | default | large`
形状：`square | circle | round`

### Table
```tsx
import { Table } from '@arco-design/web-react';

const columns = [
  { title: 'Name', dataIndex: 'name' },
  { title: 'Age', dataIndex: 'age', sorter: true, filterable: true },
];

<Table
  columns={columns}
  data={data}
  rowKey="id"
  pagination={{ pageSize: 10, current: 1, total: 200 }}
  scroll={{ x: 1000, y: 400 }}
  rowSelection={{ type: 'checkbox' }}
  virtualized
  stripe
  hover
/>
```

特性：树形数据（`childrenColumnName`）、列固定（`fixed: 'left'|'right'`）、受控/非受控排序、虚拟滚动、行展开、可拖拽列。

### Form + Form.Item
```tsx
import { Form, Input, Button, Message } from '@arco-design/web-react';

const [form] = Form.useForm();

<Form
  form={form}
  labelCol={{ span: 6 }}
  wrapperCol={{ span: 18 }}
  onSubmit={(v) => Message.success('提交成功')}
>
  <Form.Item field="name" label="用户名" rules={[{ required: true, minLength: 3 }]}>
    <Input placeholder="请输入用户名" />
  </Form.Item>
  <Form.Item field="email" label="邮箱"
    rules={[{ required: true, type: 'email' }]}
    triggerPropName="value">
    <Input />
  </Form.Item>
  <Form.List field="items">
    {(fields, { add, remove }) => fields.map((f, i) => (
      <Form.Item key={f.key} {...f}>
        <Input suffix={<Button onClick={() => remove(i)}>删除</Button>} />
      </Form.Item>
    ))}
  </Form.List>
  <Button htmlType="submit" type="primary">提交</Button>
</Form>
```

特性：`Form.useForm()`、`Form.List` 动态字段、`dependencies` 联动校验、`Form.Provider` 跨表单通信、`scrollToFirstError`、自定义校验模板（`validateMessages`）。

### Modal.useModal
```tsx
import { Modal } from '@arco-design/web-react';

// 命令式
Modal.confirm({
  title: '确认',
  content: '确定删除？',
  onOk: () => {},
});

// Hook 方式
const [modal, contextHolder] = Modal.useModal();
modal.info({ title: '提示', content: '已更新' });
return <>{contextHolder}<App /></>;

// 声明式
<Modal title="编辑" visible={v} onCancel={() => setV(false)} onOk={onOk} confirmLoading={loading}>
  <Form>...</Form>
</Modal>
```

### DatePicker.RangePicker
```tsx
import { DatePicker } from '@arco-design/web-react';

<DatePicker showTime defaultValue="2024-01-01"
  format="YYYY-MM-DD HH:mm:ss" onChange={console.log} />

<DatePicker.RangePicker
  showTime={{ defaultValue: ['00:00:00', '23:59:59'] }}
  shortcuts={[
    { text: '最近 7 天', value: () => [dayjs().subtract(7, 'day'), dayjs()] },
  ]}
/>
```

子组件：`DatePicker` / `.RangePicker` / `.MonthPicker` / `.YearPicker` / `.WeekPicker` / `.QuarterPicker`，基于 dayjs。

## 主题定制

### 方案一：ConfigProvider token（动态主题，推荐）
```tsx
import { ConfigProvider } from '@arco-design/web-react';

<ConfigProvider
  componentConfig={{
    Button: { type: 'primary' },
  }}
  theme={{
    token: {
      colorPrimary: '#165DFF',
      successColor: '#00B42A',
      borderRadius: 4,
    },
  }}
>
  <App />
</ConfigProvider>
```

Token 级别覆盖品牌色、圆角、字体、间距；组件级别可深度定制。

### 方案二：Less 变量覆盖（搭配 arco-plugin-style）
```less
@primary-color: #ff7e00;
@import '@arco-design/web-react/es/Button/style/index.less';
```

### 暗黑模式
```tsx
<ConfigProvider theme={{ ...isDark ? darkTheme : lightTheme, token: { ... } }}>
  <App />
</ConfigProvider>
```

`theme='dark'` 或动态 token，`algorithmic` 自动反演灰阶。建议使用 https://arco.design/themes 风格配置平台导出主题包。

## 国际化

支持 21 种语言包，位于 `components/locale/`。

```tsx
import { ConfigProvider } from '@arco-design/web-react';
import zhCN from '@arco-design/web-react/es/locale/zh-CN';

<ConfigProvider locale={zhCN}>
  <App />
</ConfigProvider>
```

可用语言：`zh-CN` / `zh-HK` / `zh-TW` / `en-US` / `ja-JP` / `ko-KR` / `ar-EG` / `de-DE` / `es-ES` / `fr-FR` / `it-IT` / `pt-BR` / `pt-PT` / `ru-RU` / `th-TH` / `tr-TR` / `vi-VN` / `id-ID` / `ms-MY`。

支持 **RTL**：`ConfigProvider rtl={true}`。日期组件基于 dayjs，切换语言包自动加载 `dayjs/locale/<lang>`。

## TypeScript

- 所有组件使用 `.tsx` + `interface.ts`，类型随包发布（`./es/index.d.ts`）
- 顶层导出组件 Props 类型：`ButtonProps` / `TableProps` / `FormInstance` 等
- 兼容 React 16/17/18/19；提供 `es/_util/react-19-adapter.js` 适配 React 19
- 推荐 `tsconfig.json`：`"strict": true`、`"jsx": "react-jsx"`

## 常见问题

### Q: Arco 与 antd 的主要区别？
A: Arco 设计语言更现代，组件 API 与 antd 类似但细节不同（如 `Form.useForm`、`Modal.useModal` 等 hook 风格 API）。Arco 内置 token 主题系统与暗黑模式，与字节跳动中后台设计语言保持一致。

### Q: 样式不生效？
A: 全局 CSS `import '@arco-design/web-react/dist/css/arco.css'` 必须引入。按需引入依赖 `babel-plugin-import` 或 `arco-plugin-style`。

### Q: 如何减小打包体积？
A: 使用按需引入 + tree-shaking。Arco 各组件独立打包。

## 版本信息
- 当前版本：2.66.16
- 兼容：React 16/17/18/19
- 仓库使用 yarn 1.22（非 monorepo）
