---
name: naive-ui-reference
description: |
  Naive UI 是 TypeScript-first 的 Vue 3 组件库，由图森未来开源，尤雨溪推荐。
  当用户在 Vue 3 + TypeScript 项目中使用 NButton/NDataTable/NForm 等组件、
  配置主题、解决 Naive UI 集成问题、询问组件 API 时加载本 ref。
---

# Naive UI 使用技能

> 本文档是 [[naive-ui]] 的专项参考。原为独立 skill，已合并至 ui-component-library 主索引。

## 适用场景
- Vue 3 + TypeScript 项目需要严格类型推导的 UI 库
- 需要自定义主题（覆盖 themeOverrides）实现暗黑模式 / 品牌色定制
- 询问 NButton / NDataTable / NForm / NMessageProvider / NDialog 等组件的 API
- 寻求一个无运行时 CSS 依赖、tree-shaking 友好的 UI 库

## 不适用
- React 项目
- Vue 2 项目
- 不需要 TypeScript 的简单 Vue 3 项目（可考虑 Element Plus）

## 快速链接
- 组件级详细文档：[form](./form.md)
- 官方文档：https://www.naiveui.com

## 安装与初始化

```bash
npm install -D naive-ui
# 需要 Vue 3.4+
```

### 基础使用
```ts
import { createApp } from 'vue';
import naive from 'naive-ui';

const app = createApp(App);
app.use(naive);
```

### 按需导入（推荐）
```ts
import { NButton, NConfigProvider, NMessageProvider } from 'naive-ui';
```
Naive UI 默认 tree-shaking 友好，按需 import 即可。

## 常用组件导入示例

### NButton
```vue
<template>
  <n-button type="primary" @click="handleClick">Primary</n-button>
  <n-button strong secondary>Secondary</n-button>
</template>
```

### NConfigProvider（必装顶层）
```vue
<template>
  <n-config-provider :theme="darkTheme" :theme-overrides="overrides">
    <n-message-provider>
      <n-dialog-provider>
        <App />
      </n-dialog-provider>
    </n-message-provider>
  </n-config-provider>
</template>
```

### NDataTable
```vue
<script setup lang="ts">
import { h } from 'vue';
import { NDataTable } from 'naive-ui';

const columns = [
  { title: 'Name', key: 'name' },
  { title: 'Age', key: 'age' },
];

const data = [{ name: 'Alice', age: 30 }];
</script>

<template>
  <n-data-table :columns="columns" :data="data" :pagination="false" />
</template>
```

### NForm
```vue
<script setup lang="ts">
import { ref } from 'vue';
import { NForm, NFormItem, NInput, NButton, useMessage } from 'naive-ui';

const formRef = ref();
const message = useMessage();

const handleSubmit = () => {
  message.success('提交成功');
};
</script>

<template>
  <n-form ref="formRef" :model="form" :rules="rules">
    <n-form-item label="姓名" path="name">
      <n-input v-model:value="form.name" />
    </n-form-item>
    <n-button type="primary" @click="handleSubmit">提交</n-button>
  </n-form>
</template>
```

### NDialog / useDialog
```ts
import { useDialog } from 'naive-ui';

const dialog = useDialog();
dialog.warning({
  title: '警告',
  content: '确定要删除吗？',
  positiveText: '确定',
  negativeText: '取消',
  onPositiveClick: () => { /* ... */ },
});
```

### NMessage / useMessage
```ts
import { useMessage } from 'naive-ui';
const message = useMessage();
message.success('成功');
message.error('失败');
```

## 主题定制

```ts
import { darkTheme } from 'naive-ui';

const overrides = {
  common: {
    primaryColor: '#18a058',
    primaryColorHover: '#36ad6a',
    primaryColorPressed: '#0c7a43',
  },
  Button: {
    heightMedium: '36px',
  },
};

<n-config-provider :theme="darkTheme" :theme-overrides="overrides">
  <App />
</n-config-provider>
```

## TypeScript 支持

Naive UI 完全 TypeScript-first，组件 Props 全部有类型导出：

```ts
import type { ButtonProps, DataTableColumns } from 'naive-ui';

const columns: DataTableColumns<User> = [
  { title: 'Name', key: 'name' },
];
```

## 国际化

```ts
import { zhCN, dateZhCN } from 'naive-ui';

<n-config-provider :locale="zhCN" :date-locale="dateZhCN">
  <App />
</n-config-provider>
```

支持的语言：zhCN, enUS, jaJP, koKR, ruRU, etc.

## 常见问题

### Q: N 前缀是什么？
A: Naive UI 组件约定以 `N` 开头（NButton、NInput 等）以便在模板中清晰识别。所有非 N 前缀的（如 useMessage / useDialog）都是 composable。

### Q: 找不到 useMessage 的上下文？
A: useMessage / useDialog / useNotification 必须在 NMessageProvider / NDialogProvider / NNotificationProvider 包裹的子树内调用。

### Q: 暗黑模式如何启用？
A: 引入 `darkTheme` 并通过 NConfigProvider 传入 `:theme="darkTheme"`。

### Q: 如何减小打包体积？
A: Naive UI 默认 tree-shaking，按需 import。NConfigProvider 必须在最外层。

## 版本信息
- 当前版本：2.44.1
- 兼容：Vue 3.4+, TypeScript 4.5+
