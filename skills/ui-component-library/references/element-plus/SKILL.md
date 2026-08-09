---
name: element-plus-reference
description: |
  Element Plus 是 Vue 3 生态最流行的中后台 UI 组件库（原 Element UI 的 Vue 3 版本）。
  当用户在 Vue 3 项目中使用 el-* 组件、配置主题、解决 element-plus 集成问题、
  询问组件导入方式或 API 时加载本 ref。
---

# Element Plus 使用技能

> 本文档是 [[element-plus]] 的专项参考。原为独立 skill，已合并至 ui-component-library 主索引。

## 适用场景
- Vue 3 项目中需要中后台 UI 组件（表单、表格、弹窗、导航等）
- 询问 el-button / el-form / el-table / el-dialog / el-date-picker 等组件的 API
- 配置 Element Plus 主题（CSS 变量 / SCSS 覆盖）、国际化（70+ 语言包）
- 按需引入、自动导入（unplugin-vue-components）、SSR 集成
- 与 Element UI（Vue 2 版本）的差异、迁移问题
- 解决打包体积、样式不生效、暗色模式等问题

## 不适用
- React 项目（请用 antd 或 arco）
- Vue 2 项目（请用 Element UI，非 Plus）

## 快速链接
- 组件级详细文档：[form](./form.md)
- 官方在线文档：https://element-plus.org/
- 中文镜像：https://cn.element-plus.org/zh-CN/

## 基本信息
- **类型**：Vue 3 UI 组件库（pnpm monorepo，TypeScript）
- **License**：MIT
- **首版**：2022-02-07
- **Node 要求**：>= 20
- **Vue 兼容**：^3.3.7

## 安装与初始化

### 包安装
```bash
# npm
npm install element-plus @element-plus/icons-vue
# pnpm (推荐)
pnpm add element-plus @element-plus/icons-vue
```

### 完整引入
```ts
// main.ts
import { createApp } from 'vue';
import ElementPlus from 'element-plus';
import 'element-plus/dist/index.css';
import * as ElementPlusIconsVue from '@element-plus/icons-vue';
import App from './App.vue';

const app = createApp(App);
app.use(ElementPlus);
for (const [key, component] of Object.entries(ElementPlusIconsVue)) {
  app.component(key, component);
}
app.mount('#app');
```

### 按需引入（推荐）

**1. 安装自动导入插件：**
```bash
pnpm add -D unplugin-vue-components unplugin-auto-import
```

**2. 配置 Vite（vite.config.ts）：**
```ts
import { defineConfig } from 'vite';
import AutoImport from 'unplugin-auto-import/vite';
import Components from 'unplugin-vue-components/vite';
import { ElementPlusResolver } from 'unplugin-vue-components/resolvers';

export default defineConfig({
  plugins: [
    AutoImport({ resolvers: [ElementPlusResolver()] }),
    Components({ resolvers: [ElementPlusResolver()] }),
  ],
});
```

之后直接在模板使用 `<el-button>` 即可，无需手动 import。

## 组件清单概览

| 类别 | 组件 |
|------|------|
| 表单与输入 | button, input, input-number, input-tag, input-otp, checkbox, checkbox-group, checkbox-button, radio, radio-group, radio-button, select, select-v2, cascader, cascader-panel, switch, slider, form, form-item, date-picker, time-picker, time-select, upload, autocomplete, mention, transfer, tree-select, color-picker, rate, check-tag |
| 布局 | container, header, aside, main, footer, row, col, space, divider, card, page-header, collapse, collapse-item, splitter, carousel, carousel-item |
| 导航 | menu, menu-item, sub-menu, breadcrumb, breadcrumb-item, pagination, steps, step, dropdown, dropdown-item, anchor, anchor-link |
| 数据展示 | table, table-column, table-v2, avatar, avatar-group, badge, tag, calendar, timeline, tree, tree-v2, tabs, tab-pane, image, image-viewer, descriptions, empty, statistic, countdown, segmented, skeleton, tour, link, text |
| 反馈 | alert, dialog, drawer, message, message-box, notification, popconfirm, popover, tooltip, result, loading, progress, infinite-scroll |
| 其他 | affix, app, backtop, button-group, config-provider, icon, scrollbar, watermark |

## 常用组件示例

### Button
```vue
<template>
  <el-button type="primary" @click="onClick">主要按钮</el-button>
  <el-button type="success" round>成功按钮</el-button>
  <el-button type="danger" plain>危险按钮</el-button>
  <el-button :icon="Edit" circle />
</template>

<script setup lang="ts">
import { Edit } from '@element-plus/icons-vue';
const onClick = () => console.log('clicked');
</script>
```

### Form
```vue
<script setup lang="ts">
import { ref, reactive } from 'vue';
import type { FormInstance, FormRules } from 'element-plus';

const formRef = ref<FormInstance>();
const form = reactive({ name: '', age: 18 });
const rules: FormRules = {
  name: [{ required: true, message: '请输入', trigger: 'blur' }],
};
const submit = async () => {
  await formRef.value?.validate();
  console.log('valid');
};
</script>

<template>
  <el-form ref="formRef" :model="form" :rules="rules" label-width="100px">
    <el-form-item label="用户名" prop="name">
      <el-input v-model="form.name" />
    </el-form-item>
    <el-form-item label="年龄" prop="age">
      <el-input-number v-model="form.age" :min="0" :max="120" />
    </el-form-item>
    <el-button type="primary" @click="submit">提交</el-button>
  </el-form>
</template>
```

### Table
```vue
<template>
  <el-table :data="rows" stripe border>
    <el-table-column prop="id" label="ID" width="80" />
    <el-table-column prop="name" label="姓名" />
    <el-table-column label="操作" width="160">
      <template #default="{ row }">
        <el-button size="small" @click="edit(row)">编辑</el-button>
        <el-button size="small" type="danger">删除</el-button>
      </template>
    </el-table-column>
  </el-table>
</template>
```

### Dialog
```vue
<script setup lang="ts">
import { ref } from 'vue';
const open = ref(false);
</script>

<template>
  <el-button @click="open = true">打开弹窗</el-button>
  <el-dialog v-model="open" title="提示" width="500px">
    <span>内容</span>
    <template #footer>
      <el-button @click="open = false">取消</el-button>
      <el-button type="primary" @click="open = false">确定</el-button>
    </template>
  </el-dialog>
</template>
```

### DatePicker
```vue
<template>
  <el-date-picker
    v-model="date"
    type="daterange"
    range-separator="至"
    start-placeholder="开始日期"
    end-placeholder="结束日期"
    value-format="YYYY-MM-DD"
  />
</template>

<script setup lang="ts">
import { ref } from 'vue';
const date = ref<[string, string]>(['', '']);
</script>
```

## 主题定制

### 方式一：CSS 变量覆盖
```css
:root {
  --el-color-primary: #409eff;
  --el-color-success: #67c23a;
  --el-color-warning: #e6a23c;
  --el-color-danger: #f56c6c;
  --el-border-radius-base: 4px;
  --el-border-color: #dcdfe6;
  --el-font-size-base: 14px;
}
```

### 方式二：SCSS 变量覆盖（推荐）
```bash
pnpm add -D sass
```
```scss
/* src/styles/element-plus.scss */
@forward 'element-plus/theme-chalk/src/common/var.scss' with (
  $colors: (
    'primary': ('base': #42b883),
  ),
  $border-radius: (
    'base': 6px,
  )
);
```
```ts
// main.ts
import './styles/element-plus.scss';
```

### 暗黑模式
```ts
import 'element-plus/theme-chalk/dark/css-vars.css';
document.documentElement.classList.add('dark');
```

## 国际化

内置 70+ 语言包，覆盖中文、英文、日韩、欧洲多语言、阿拉伯语等。

```ts
import zhCn from 'element-plus/es/locale/lang/zh-cn';
import en from 'element-plus/es/locale/lang/en';
import { ElConfigProvider } from 'element-plus';

// 方式一：全局
app.use(ElConfigProvider, { locale: zhCn });

// 方式二：局部包裹
<el-config-provider :locale="zhCn">
  <App />
</el-config-provider>
```

## TypeScript 支持

完整类型定义，位于 `es/index.d.ts`。常用类型：

```ts
import type {
  FormInstance, FormRules, FormItemRule,
  TableInstance, TableColumnInstance,
  UploadInstance, UploadRawFile, UploadUserFile,
  CascaderOption, TreeOption,
  SelectOption, SelectInstance,
} from 'element-plus';
```

组件 props / events / slots 全部类型化，IDE 自动补全友好。

## 常用导入路径速查

```ts
// 组件
import { ElButton, ElForm, ElTable } from 'element-plus';

// 命令式 API
import { ElMessage, ElMessageBox, ElNotification, ElLoading } from 'element-plus';

// 图标
import { Edit, Delete, Search } from '@element-plus/icons-vue';
```

## 核心依赖（关键第三方库）

| 库 | 用途 |
|----|------|
| `@popperjs/core` / `@floating-ui/dom` | 弹层定位 |
| `@vueuse/core` | 组合式工具集 |
| `async-validator` | 表单异步校验 |
| `dayjs` | 日期处理 |
| `@ctrl/tinycolor` | 颜色处理（ColorPicker） |
| `lodash-es` / `memoize-one` | 工具与记忆化 |

## 常见问题

### Q: 样式不生效？
A: 完整引入需 `import 'element-plus/dist/index.css'`。按需引入由 unplugin 自动处理样式。

### Q: Element Plus 与 Element UI 的区别？
A: Element Plus 仅支持 Vue 3；Element UI 仅支持 Vue 2。API 高度相似但不完全一致（如 `el-icon` 写法、slot 命名）。

### Q: 如何减小打包体积？
A: 按需引入 + 启用 tree-shaking。生产构建使用 ES module 入口（`es/index.mjs`）。

### Q: icon 怎么用？
A: 必须单独安装 `@element-plus/icons-vue`，按需引入或全局注册。

### Q: 表单校验失败如何定位？
A: 使用 `formRef.value?.validate((valid, fields) => ...)`，第二个参数拿到失败字段。

## 包结构

Element Plus 是 monorepo 结构，按包组织：

- `element-plus/component/` — 主包聚合导出
- `@element-plus/icons-vue` — 图标包（独立）
- 官方主题样式：SCSS 源 + 预编译 CSS

## 版本信息
- 当前版本：2.x（稳定版）
- 兼容：Vue ^3.3.7
- Node：>= 20
