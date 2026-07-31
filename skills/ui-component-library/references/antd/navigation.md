# 导航组件

按 UI 库分类列出最常用的导航组件。

## 速查表

| 用途 | Ant Design | Element Plus | Naive UI | Arco Design |
|------|------------|--------------|----------|-------------|
| 顶部/侧边菜单 | `Menu` | `el-menu` | `NMenu` | `Menu` |
| 面包屑 | `Breadcrumb` | `el-breadcrumb` | `NBreadcrumb` | `Breadcrumb` |
| 分页 | `Pagination` | `el-pagination` | `NPagination` | `Pagination` |
| 步骤条 | `Steps` | `el-steps` | `NSteps` | `Steps` |
| 下拉菜单 | `Dropdown` | `el-dropdown` | `NDropdown` | `Dropdown` |
| 锚点 | `Anchor` | `el-anchor` | `NAnchor` | `Anchor` |
| 固钉 | `Affix` | `el-affix` | `NAffix` | `Affix` |
| 返回顶部 | `BackTop` | `el-backtop` | - | `BackTop` |
| 页头 | `PageHeader` | `el-page-header` | `NPageHeader` | `PageHeader` |

## Menu 用法对比

### Ant Design Menu
```tsx
import { Menu } from 'antd';
import { useState } from 'react';

const items = [
  { key: '1', label: '首页' },
  { key: '2', label: '产品' },
  { key: '3', label: '关于' },
];

<Menu
  mode="horizontal"
  selectedKeys={[current]}
  items={items}
  onClick={({ key }) => setCurrent(key)}
/>
```

### Element Plus Menu
```vue
<el-menu mode="horizontal" :default-active="active" @select="handleSelect">
  <el-menu-item index="1">首页</el-menu-item>
  <el-menu-item index="2">产品</el-menu-item>
  <el-menu-item index="3">关于</el-menu-item>
</el-menu>
```

### Naive UI Menu
```vue
<script setup>
const menuOptions = [
  { label: '首页', key: '1' },
  { label: '产品', key: '2' },
  { label: '关于', key: '3' },
];
</script>

<template>
  <n-menu mode="horizontal" :options="menuOptions" :value="active" @update:value="handleSelect" />
</template>
```

### Arco Design Menu
```tsx
import { Menu } from '@arco-design/web-react';

const items = [
  { key: '1', title: '首页' },
  { key: '2', title: '产品' },
  { key: '3', title: '关于' },
];

<Menu mode="horizontal" selectedKeys={[active]} onClickMenuItem={handleSelect}>
  {items.map(item => (
    <MenuItem key={item.key}>{item.title}</MenuItem>
  ))}
</Menu>
```

## 关键差异

| 维度 | Ant Design | Element Plus | Naive UI | Arco Design |
|------|------------|--------------|----------|-------------|
| 数据格式 | items 数组 | 子组件 | options 数组 | 子组件或 items |
| 选中字段 | `selectedKeys` | `default-active` / `v-model` | `value` | `selectedKeys` |
| 模式 | `mode` | `mode` | `mode` | `mode` |
| 子菜单 | nested items | `el-sub-menu` | nested options | nested |

## Pagination 分页用法对比

### Ant Design
```tsx
<Pagination
  current={page}
  pageSize={pageSize}
  total={total}
  showSizeChanger
  showQuickJumper
  onChange={(page, pageSize) => {
    setPage(page);
    setPageSize(pageSize);
  }}
/>
```

### Element Plus
```vue
<el-pagination
  v-model:current-page="page"
  v-model:page-size="pageSize"
  :total="total"
  :page-sizes="[10, 20, 50]"
  layout="total, sizes, prev, pager, next, jumper"
  @size-change="handleSizeChange"
  @current-change="handlePageChange"
/>
```

### Naive UI
```vue
<n-pagination
  v-model:page="page"
  v-model:page-size="pageSize"
  :item-count="total"
  :page-sizes="[10, 20, 50]"
  show-size-picker
/>
```

### Arco Design
```tsx
<Pagination
  current={page}
  pageSize={pageSize}
  total={total}
  sizeCanChange
  showJumper
  onChange={(page, pageSize) => {
    setPage(page);
    setPageSize(pageSize);
  }}
/>
```

## Steps 步骤条

四个库都用 `current` + `status` 控制步骤进度：

```tsx
// antd
const steps = [
  { title: '步骤一', content: '内容一' },
  { title: '步骤二', content: '内容二' },
  { title: '步骤三', content: '内容三' },
];
<Steps current={current} items={steps} />
```

## Anchor 锚点

```tsx
// antd
<Anchor>
  <Link href="#part-1" title="第一部分" />
  <Link href="#part-2" title="第二部分" />
</Anchor>
```

## 性能要点

1. **大量菜单项**：使用 `lazyRender` 或 `virtual-list`
2. **路由集成**：使用对应 UI 库的 `react-router-dom` / `vue-router` 适配
3. **嵌套菜单**：层级不超过 3 层，避免视觉混乱
4. **响应式菜单**：移动端用 `Drawer + Menu` 替代传统菜单
