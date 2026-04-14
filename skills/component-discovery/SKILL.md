---
name: component-discovery
description: Vue 3 + Vite 组件自动发现机制规范。当用户提到"添加组件"、"创建component.js"、"自动发现"、"component配置"、或需要在 src/components 下创建新的组件目录时，必须使用此skill。
---

# Vue 3 + Vite 组件自动发现机制

本项目使用完全自动化的组件发现系统。只需按照规范创建文件，系统会自动识别、注册路由并在首页展示。

## 目录结构

```
src/components/
└── YourComponent/           # 目录名必须与 component.js 中的 name 一致
    ├── component.js         # 组件配置（必需）
    └── index.vue            # 组件实现（必需）
```

## component.js 配置详解

```javascript
export default {
  // === 基础信息 ===
  name: 'YourComponent',      // 【必需】唯一标识符，必须与目录名一致
  title: '显示标题',           // 【必需】在 UI 中显示的名称
  description: '组件描述',     // 【必需】组件功能描述
  version: '1.0.0',            // 【必需】语义化版本

  // === 分组与分类 ===
  group: 'DataTable',         // 【必需】主分组，如 'Three.js', 'DataTable', 'Basic'
  category: 'Spreadsheet',     // 【必需】子分类
  tags: ['tag1', 'tag2'],      // 【必需】搜索/过滤标签

  // === 入口文件 ===
  component: './index.vue',    // 【必需】组件文件路径（相对路径）

  // === 路由配置（可选）===
  route: {
    path: '/custom-path',     // 自定义路由路径，默认 /components/{name}
    meta: {
      title: '页面标题',      // 页面标题
      icon: '🎨'              // 图标 emoji
    }
  },

  // === 显示选项（可选）===
  fullscreen: true,           // 是否全屏显示，默认 true

  // === 依赖（可选）===
  dependencies: [],           // 外部依赖，如 ['three']

  // === 默认属性（可选）===
  defaultProps: {}           // 默认 props
}
```

## 必填字段验证

系统会自动验证以下字段，缺少任何一个都会导致组件无法被发现：

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | string | 唯一标识符 |
| `title` | string | 显示名称 |
| `description` | string | 组件描述 |
| `version` | string | 版本号 |
| `group` | string | 主分组 |
| `category` | string | 子分类 |
| `tags` | array | 标签数组 |
| `component` | string | 组件文件路径 |

## index.vue 模板

```vue
<script setup>
// 组件逻辑
defineProps({
  // 定义你的 props
})

// 组合式 API
import { ref } from 'vue'
const count = ref(0)
</script>

<template>
  <div class="your-component">
    <!-- 组件内容 -->
  </div>
</template>

<style scoped>
.your-component {
  /* 样式 */
}
</style>
```

## 自动发现流程

1. **Vite 构建时**：使用 `import.meta.glob('../components/**/component.js')` 扫描所有配置文件
2. **运行时**：`ComponentDiscovery.scanComponents()` 加载并验证每个配置
3. **路由注册**：根据 `route.path` 或默认路径 `/components/{name}` 自动注册路由
4. **首页展示**：组件自动出现在首页网格中，支持搜索和过滤

## 分组规范

常用 `group` 值：
- `Three.js` - Three.js 相关组件
- `DataTable` - 数据表格类组件
- `Basic` - 基础组件
- `Animation` - 动画组件
- `Effects` - 特效组件

## 注意事项

1. **目录名必须与 `name` 一致**（大小写敏感）
2. **不要手动配置路由** - 系统自动处理
3. **不要在 `dependencies` 中添加已内置的包**（如 vue, vue-router, three 已内置）
4. **组件默认全屏显示** - ComponentView 无导航栏

## 示例：创建一个新组件

假设要创建"我的表格"组件：

```bash
mkdir src/components/MyTable
```

**src/components/MyTable/component.js**：
```javascript
export default {
  name: 'MyTable',
  title: '我的表格',
  description: '一个自定义数据表格组件',
  version: '1.0.0',
  group: 'DataTable',
  category: 'Table',
  tags: ['table', 'data', 'custom'],
  component: './index.vue',
  route: {
    path: '/my-table',
    meta: {
      title: '我的表格',
      icon: '📊'
    }
  }
}
```

**src/components/MyTable/index.vue**：
```vue
<script setup>
defineProps({
  data: { type: Array, default: () => [] }
})
</script>

<template>
  <div class="my-table">
    <table>
      <slot />
    </table>
  </div>
</template>
```

创建完成后，重新运行 `npm run dev`，组件会自动出现在首页。
