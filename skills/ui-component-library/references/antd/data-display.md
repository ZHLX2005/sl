# 数据展示组件

按 UI 库分类列出最常用的数据展示组件，按需查阅。

## 速查表

| 用途 | Ant Design | Element Plus | Naive UI | Arco Design |
|------|------------|--------------|----------|-------------|
| 表格 | `Table` | `el-table` | `NDataTable` | `Table` |
| 虚拟表格 | - | `el-table-v2` | `NDataTable` + virtual-scroll | `Table` + virtualListProps |
| 列表 | `List` | `el-list` | `NList` | `List` |
| 卡片 | `Card` | `el-card` | `NCard` | `Card` |
| 树 | `Tree` | `el-tree` | `NTree` | `Tree` |
| 级联 | `Cascader` | `el-cascader` | `NCascader` | `Cascader` |
| 标签页 | `Tabs` | `el-tabs` | `NTabs` | `Tabs` |
| 描述列表 | `Descriptions` | `el-descriptions` | `NDescriptions` | `Descriptions` |
| 头像 | `Avatar` | `el-avatar` | `NAvatar` | `Avatar` |
| 徽章 | `Badge` | `el-badge` | `NBadge` | `Badge` |
| 标签 | `Tag` | `el-tag` | `NTag` | `Tag` |
| 日历 | `Calendar` | `el-calendar` | `NCalendar` | `Calendar` |
| 时间线 | `Timeline` | `el-timeline` | `NTimeline` | `Timeline` |
| 图片 | `Image` | `el-image` | `NImage` | `Image` |
| 空状态 | `Empty` | `el-empty` | `NEmpty` | `Empty` |
| 统计数值 | `Statistic` | `el-statistic` | `NStatistic` | `Statistic` |
| 折叠面板 | `Collapse` | `el-collapse` | `NCollapse` | `Collapse` |
| 分段器 | `Segmented` | `el-segmented` | - | `Segmented` |
| 评论 | `Comment` | - | - | `Comment` |

## Table 用法对比

### Ant Design Table
```tsx
import { Table } from 'antd';
import type { TableColumnsType } from 'antd';

const columns: TableColumnsType<DataType> = [
  { title: 'Name', dataIndex: 'name', key: 'name' },
  { title: 'Age', dataIndex: 'age', key: 'age', sorter: (a, b) => a.age - b.age },
  { title: 'Address', dataIndex: 'address', key: 'address' },
];

<Table columns={columns} dataSource={data} rowKey="id" />
```

### Element Plus Table
```vue
<el-table :data="tableData" stripe border style="width: 100%">
  <el-table-column prop="name" label="Name" />
  <el-table-column prop="age" label="Age" sortable />
  <el-table-column prop="address" label="Address" />
</el-table>
```

### Naive UI DataTable
```vue
<script setup lang="ts">
import { h } from 'vue';
import { NDataTable } from 'naive-ui';
import type { DataTableColumns } from 'naive-ui';

const columns: DataTableColumns<DataType> = [
  { title: 'Name', key: 'name' },
  { title: 'Age', key: 'age', sorter: 'default' },
  { title: 'Address', key: 'address' },
];

const data: DataType[] = [...];
</script>

<template>
  <n-data-table :columns="columns" :data="data" :pagination="false" />
</template>
```

### Arco Design Table
```tsx
import { Table } from '@arco-design/web-react';

const columns = [
  { title: 'Name', dataIndex: 'name' },
  { title: 'Age', dataIndex: 'age', sorter: (a, b) => a.age - b.age },
  { title: 'Address', dataIndex: 'address' },
];

<Table columns={columns} data={data} rowKey="id" pagination={false} />
```

## 关键差异

| 维度 | Ant Design | Element Plus | Naive UI | Arco Design |
|------|------------|--------------|----------|-------------|
| 列定义 | columns | `el-table-column` 子组件 | columns | columns |
| 排序 | `sorter: (a,b) => ...` | `sortable` 属性 | `sorter: 'default'` | `sorter: (a,b) => ...` |
| 虚拟滚动 | v5+ 内置 | `el-table-v2` | `virtual-scroll` | `virtualListProps` |
| 分页 | `pagination={{ pageSize: 10 }}` | `el-pagination` | `pagination` | `pagination={{ pageSize: 10 }}` |
| 数据字段 | `dataSource` | `data` | `data` | `data` |
| 行键 | `rowKey` | `row-key` | `rowKey` | `rowKey` |
| 树形数据 | `dataIndex + children` | `:tree-props="{ children: 'children' }"` | `:children-key="'children'"` | `dataIndex + children` |

## 性能要点

1. **大数据量**：使用虚拟滚动版本（各库均有）
2. **固定列**：使用 `fixed` 属性，但会增加渲染开销
3. **可编辑行**：行内编辑用 `Cell` 渲染自定义组件
4. **列宽自适应**：避免使用 `width="100%"`，使用 min-content 策略

## 列表与卡片

四个库的 List / Card 组件高度相似：

```tsx
<Card title="标题" extra={<a href="#">更多</a>}>
  <List
    dataSource={data}
    renderItem={(item) => (
      <List.Item>
        <List.Item.Meta title={item.title} description={item.desc} />
      </List.Item>
    )}
  />
</Card>
```
