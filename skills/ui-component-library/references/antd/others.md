# 其他通用组件

按 UI 库分类列出其他常用通用组件。

## 速查表

| 用途 | Ant Design | Element Plus | Naive UI | Arco Design |
|------|------------|--------------|----------|-------------|
| 全局配置 | `ConfigProvider` | `el-config-provider` | `NConfigProvider` | `ConfigProvider` |
| 图标 | `@ant-design/icons` | `@element-plus/icons-vue` | `@vicons/*` | `@arco-design/icons` |
| 滚动条 | - | `el-scrollbar` | `NScrollbar` | - |
| 水印 | `Watermark` | `el-watermark` | `NWatermark` | `Watermark` |
| 字体排版 | `Typography` | - | - | `Typography` |
| 浮动按钮 | `FloatButton` | - | `NFloatButton` | - |
| 主题 | `theme` | - | `themeOverrides` | `theme` |
| 二维码 | `QRCode` | - | `NQrCode` | - |
| 引导 | `Tour` | `el-tour` | - | `Tour` |
| 加载指令 | - | `v-loading` | - | - |

## ConfigProvider 用法对比

### Ant Design
```tsx
import { ConfigProvider, theme } from 'antd';
import zhCN from 'antd/locale/zh_CN';

<ConfigProvider
  locale={zhCN}
  theme={{
    token: { colorPrimary: '#1677ff' },
    algorithm: theme.darkAlgorithm,
    cssVar: true,
  }}
>
  <App />
</ConfigProvider>
```

### Element Plus
```vue
<script setup>
import zhCn from 'element-plus/es/locale/lang/zh-cn';
import { ElConfigProvider } from 'element-plus';
</script>

<template>
  <el-config-provider :locale="zhCn">
    <App />
  </el-config-provider>
</template>
```

### Naive UI
```vue
<script setup>
import { NConfigProvider, darkTheme, zhCN, dateZhCN } from 'naive-ui';
const themeOverrides = {
  common: { primaryColor: '#18a058' },
};
</script>

<template>
  <n-config-provider
    :theme="darkTheme"
    :theme-overrides="themeOverrides"
    :locale="zhCN"
    :date-locale="dateZhCN"
    inline-theme-disabled
  >
    <App />
  </n-config-provider>
</template>
```

### Arco Design
```tsx
import { ConfigProvider } from '@arco-design/web-react';
import zhCN from '@arco-design/web-react/es/locale/zh-CN';

<ConfigProvider
  locale={zhCN}
  theme={{ primaryColor: '#165DFF' }}
  componentConfig={{ Button: { type: 'primary' } }}
>
  <App />
</ConfigProvider>
```

## 主题与暗色模式

| 维度 | Ant Design | Element Plus | Naive UI | Arco Design |
|------|------------|--------------|----------|-------------|
| 主题算法 | `theme.darkAlgorithm` | 引入 dark css-vars.css | `darkTheme` import | 切换 theme 对象 |
| 颜色变量 | token | CSS variables | themeOverrides | theme 对象 |
| 动态切换 | ConfigProvider | class 切换 dark | theme prop | theme prop |
| 自定义程度 | 完整 token 覆盖 | SCSS 变量覆盖 | 完整覆盖 | token + component |

## Icon 图标

### Ant Design
```tsx
import { HomeOutlined, SearchOutlined } from '@ant-design/icons';

<HomeOutlined />
<Button icon={<SearchOutlined />}>搜索</Button>
```

### Element Plus
```vue
<script setup>
import { Home, Search } from '@element-plus/icons-vue';
</script>

<template>
  <el-icon><Home /></el-icon>
  <el-button :icon="Search">搜索</el-button>
</template>
```

### Naive UI
```vue
<script setup>
import { Home, Search } from '@vicons/ionicons5';
import { NIcon } from 'naive-ui';
</script>

<template>
  <n-icon size="20"><Home /></n-icon>
  <n-button>
    <template #icon>
      <n-icon><Search /></n-icon>
    </template>
    搜索
  </n-button>
</template>
```

### Arco Design
```tsx
import { IconHome, IconSearch } from '@arco-design/web-react/icon';

<IconHome />
<Button icon={<IconSearch />}>搜索</Button>
```

## Typography 排版对比

### Ant Design Typography
```tsx
import { Typography } from 'antd';
const { Title, Paragraph, Text, Link } = Typography;

<Title level={1}>标题一</Title>
<Paragraph copyable={{ text: '可复制' }}>这是一段文字</Paragraph>
<Text type="success">成功文字</Text>
<Link href="#" target="_blank">链接</Link>
```

### Arco Design Typography
```tsx
import { Typography } from '@arco-design/web-react';

<Typography.Title heading={1}>标题一</Typography.Title>
<Typography.Paragraph copyable>这是一段文字</Typography.Paragraph>
<Typography.Text type="success">成功文字</Typography.Text>
<Typography.Text> <a href="#">链接</a> </Typography.Text>
```

## Watermark 水印

```tsx
// antd
<Watermark content="机密文档">
  <div style={{ height: 400 }}>受保护内容</div>
</Watermark>

// element-plus
<el-watermark content="机密文档">
  <div style="height: 400px">受保护内容</div>
</el-watermark>

// naive-ui
<n-watermark content="机密文档" :cross="true" :fullscreen="true">
  <div style="height: 400px">受保护内容</div>
</n-watermark>

// arco
<Watermark content="机密文档">
  <div style={{ height: 400 }}>受保护内容</div>
</Watermark>
```

## QR Code 二维码

```tsx
// antd
import { QRCode } from 'antd';
<QRCode value="https://example.com" size={200} />

// naive
<n-qr-code value="https://example.com" :size="200" />
```

## 全局 Loading 指令

```vue
<!-- element-plus v-loading -->
<div v-loading="loading">内容区域</div>
```

## 性能要点

1. **ConfigProvider**：放在应用最外层，避免深层嵌套
2. **图标**：按需 import，避免引入全部图标
3. **水印**：高频渲染会消耗性能，避免大区域使用
4. **主题切换**：动态切换可能引起所有组件重新渲染
