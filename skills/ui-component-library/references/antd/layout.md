# 布局组件

按 UI 库分类列出最常用的布局组件。

## 速查表

| 用途 | Ant Design | Element Plus | Naive UI | Arco Design |
|------|------------|--------------|----------|-------------|
| 布局容器 | `Layout` | `el-container` | `NLayout` | `Layout` |
| 头部 | `Layout.Header` | `el-header` | `NLayoutHeader` | `Layout.Header` |
| 侧边栏 | `Layout.Sider` | `el-aside` | `NLayoutSider` | `Layout.Sider` |
| 内容 | `Layout.Content` | `el-main` | `NLayoutContent` | `Layout.Content` |
| 底部 | `Layout.Footer` | `el-footer` | `NLayoutFooter` | `Layout.Footer` |
| 栅格 | `Row` + `Col` | `el-row` + `el-col` | `NGrid` + `NGi` | `Row` + `Col` |
| 间距 | `Space` | `el-space` | `NSpace` | `Space` |
| 分割线 | `Divider` | `el-divider` | `NDivider` | `Divider` |
| Flex | `Flex` | - | `NFlex` | `Flex` |
| 分割面板 | `Splitter` | - | - | `Split` / `ResizeBox` |

## Layout 用法对比

### Ant Design Layout
```tsx
import { Layout } from 'antd';
const { Header, Sider, Content, Footer } = Layout;

<Layout style={{ minHeight: '100vh' }}>
  <Sider collapsible>
    <div className="logo" />
    <Menu theme="dark" mode="inline" items={menuItems} />
  </Sider>
  <Layout>
    <Header style={{ background: '#fff', padding: 0 }}>Header</Header>
    <Content style={{ margin: '16px' }}>Content</Content>
    <Footer style={{ textAlign: 'center' }}>Footer ©2024</Footer>
  </Layout>
</Layout>
```

### Element Plus Container
```vue
<el-container style="height: 100vh">
  <el-aside width="200px">Aside</el-aside>
  <el-container>
    <el-header>Header</el-header>
    <el-main>Main</el-main>
    <el-footer>Footer</el-footer>
  </el-container>
</el-container>
```

### Naive UI Layout
```vue
<n-layout style="height: 100vh" has-sider>
  <n-layout-sider bordered>Aside</n-layout-sider>
  <n-layout>
    <n-layout-header bordered>Header</n-layout-header>
    <n-layout-content>Content</n-layout-content>
    <n-layout-footer bordered>Footer</n-layout-footer>
  </n-layout>
</n-layout>
```

### Arco Design Layout
```tsx
import { Layout } from '@arco-design/web-react';
const { Header, Sider, Content, Footer } = Layout;

<Layout>
  <Sider>Aside</Sider>
  <Layout>
    <Header>Header</Header>
    <Content>Content</Content>
    <Footer>Footer</Footer>
  </Layout>
</Layout>
```

## Grid / Row-Col 栅格对比

### Ant Design
```tsx
import { Row, Col } from 'antd';

<Row gutter={[16, 16]} justify="space-between" align="middle">
  <Col span={8} xs={24} sm={12} md={8} lg={6}>col-1</Col>
  <Col span={8} xs={24} sm={12} md={8} lg={6}>col-2</Col>
  <Col span={8} xs={24} sm={12} md={8} lg={6}>col-3</Col>
</Row>
```

### Element Plus
```vue
<el-row :gutter="20" justify="space-between" align="middle">
  <el-col :span="8" :xs="24" :sm="12" :md="8">col-1</el-col>
  <el-col :span="8" :xs="24" :sm="12" :md="8">col-2</el-col>
  <el-col :span="8" :xs="24" :sm="12" :md="8">col-3</el-col>
</el-row>
```

### Naive UI
```vue
<n-grid :cols="12" :x-gap="16" :y-gap="16" responsive="screen">
  <n-gi span="8 m:6 l:4">col-1</n-gi>
  <n-gi span="8 m:6 l:4">col-2</n-gi>
  <n-gi span="8 m:6 l:4">col-3</n-gi>
</n-grid>
```

### Arco Design
```tsx
<Row gutter={20} justify="space-between" align="center">
  <Col span={8} xs={24} sm={12} md={8} lg={6}>col-1</Col>
  <Col span={8} xs={24} sm={12} md={8} lg={6}>col-2</Col>
  <Col span={8} xs={24} sm={12} md={8} lg={6}>col-3</Col>
</Row>
```

## 关键差异

| 维度 | Ant Design | Element Plus | Naive UI | Arco Design |
|------|------------|--------------|----------|-------------|
| 响应式语法 | `xs sm md lg xl xxl` | `xs sm md lg xl` | 字符串模板 `m:6 l:4` | `xs sm md lg xl xxl` |
| 间距字段 | `gutter` | `gutter` | `x-gap / y-gap` | `gutter` |
| 总列数 | 24 | 24 | 自定义 | 24 |
| 偏移 | `offset={2}` | `:offset="2"` | `:offset="2"` | `offset={2}` |

## Space 间距用法对比

### Ant Design
```tsx
<Space size="middle" direction="horizontal" align="center" wrap>
  <Button>1</Button>
  <Button>2</Button>
  <Button>3</Button>
</Space>
```

### Element Plus
```vue
<el-space :size="10" direction="horizontal" alignment="center" wrap>
  <el-button>1</el-button>
  <el-button>2</el-button>
  <el-button>3</el-button>
</el-space>
```

### Naive UI
```vue
<n-space :size="10" vertical>
  <n-button>1</n-button>
  <n-button>2</n-button>
  <n-button>3</n-button>
</n-space>
```

### Arco Design
```tsx
<Space size="medium" direction="horizontal">
  <Button>1</Button>
  <Button>2</Button>
  <Button>3</Button>
</Space>
```

## 性能要点

1. **Layout 嵌套**：避免超过 3 层嵌套，使用 CSS Grid 替代
2. **响应式**：移动端优先，PC 端特殊处理
3. **栅格**：`gutter` 会创建间距但不影响布局计算
4. **Space vs CSS gap**：Space 组件更适合动态间距，CSS gap 更适合固定布局
