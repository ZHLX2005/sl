# 反馈与提示组件

按 UI 库分类列出最常用的反馈组件。

## 速查表

| 用途 | Ant Design | Element Plus | Naive UI | Arco Design |
|------|------------|--------------|----------|-------------|
| 对话框 | `Modal` | `el-dialog` | `NDialog` | `Modal` |
| 抽屉 | `Drawer` | `el-drawer` | `NDrawer` | `Drawer` |
| 消息提示 | `message` | `ElMessage` | `useMessage` | `Message` |
| 通知 | `notification` | `ElNotification` | `useNotification` | `Notification` |
| 气泡确认 | `Popconfirm` | `el-popconfirm` | `NPopconfirm` | `Popconfirm` |
| 气泡卡片 | `Popover` | `el-popover` | `NPopover` | `Popover` |
| 工具提示 | `Tooltip` | `el-tooltip` | `NTooltip` | `Tooltip` |
| 警告 | `Alert` | `el-alert` | `NAlert` | `Alert` |
| 加载中 | `Spin` | `el-skeleton` / `v-loading` | `NSpin` | `Spin` |
| 骨架屏 | `Skeleton` | `el-skeleton` | `NSkeleton` | `Skeleton` |
| 进度条 | `Progress` | `el-progress` | `NProgress` | `Progress` |
| 结果页 | `Result` | `el-result` | `NResult` | `Result` |
| 加载条 | - | `v-loading` | `NLoadingBar` | - |

## Modal 对话框用法对比

### Ant Design Modal
```tsx
import { Modal, Button } from 'antd';
import { useState } from 'react';

const [open, setOpen] = useState(false);

<Button onClick={() => setOpen(true)}>Open</Button>
<Modal
  title="标题"
  open={open}
  onOk={() => setOpen(false)}
  onCancel={() => setOpen(false)}
  okText="确定"
  cancelText="取消"
>
  内容
</Modal>
```

### Element Plus Dialog
```vue
<template>
  <el-button @click="visible = true">打开</el-button>
  <el-dialog
    v-model="visible"
    title="标题"
    width="500px"
    :before-close="handleClose"
  >
    <span>内容</span>
    <template #footer>
      <el-button @click="visible = false">取消</el-button>
      <el-button type="primary" @click="onConfirm">确定</el-button>
    </template>
  </el-dialog>
</template>
```

### Naive UI Dialog
```vue
<script setup>
import { ref } from 'vue';
import { NDialog, NButton } from 'naive-ui';
const show = ref(false);
</script>

<template>
  <n-button @click="show = true">打开</n-button>
  <n-dialog
    v-model:show="show"
    title="标题"
    positive-text="确定"
    negative-text="取消"
    @positive-click="onConfirm"
  >
    内容
  </n-dialog>
</template>
```

### Arco Design Modal
```tsx
import { Modal, Button } from '@arco-design/web-react';

const [visible, setVisible] = useState(false);

<Button onClick={() => setVisible(true)}>打开</Button>
<Modal
  title="标题"
  visible={visible}
  onOk={() => setVisible(false)}
  onCancel={() => setVisible(false)}
  okText="确定"
  cancelText="取消"
>
  内容
</Modal>
```

## Message / Notification 用法对比

### Ant Design（需 App 包裹）
```tsx
import { App, Button } from 'antd';
const { message, notification, modal } = App.useApp();

<Button onClick={() => message.success('操作成功')}>成功</Button>
<Button onClick={() => notification.info({ message: '通知' })}>通知</Button>
<Button onClick={() => modal.confirm({ title: '确认' })}>确认</Button>
```

### Element Plus（直接函数调用）
```ts
import { ElMessage, ElNotification, ElMessageBox } from 'element-plus';

ElMessage.success('操作成功');
ElNotification({ title: '通知', message: '内容' });
ElMessageBox.confirm('确认删除？', '提示');
```

### Naive UI（需 Provider + useXxx）
```ts
import { useMessage, useNotification, useDialog } from 'naive-ui';

const message = useMessage();
const notification = useNotification();
const dialog = useDialog();

message.success('成功');
notification.info({ title: '通知', content: '内容' });
dialog.warning({ title: '警告', content: '内容' });
```

### Arco Design（两种方式）
```tsx
import { Message, Notification, Modal } from '@arco-design/web-react';

// 方式一：静态调用
Message.success('成功');
Notification.info({ title: '通知', content: '内容' });
Modal.confirm({ title: '确认', content: '内容' });

// 方式二：Hook 风格
const [modal, contextHolder] = Modal.useModal();
modal.confirm({ title: '确认' });
return <>{contextHolder}</>;
```

## 关键差异

| 维度 | Ant Design | Element Plus | Naive UI | Arco Design |
|------|------------|--------------|----------|-------------|
| 上下文依赖 | 需 App 包裹 | 静态函数 | 需 Provider + use | 两种风格都可 |
| 调用风格 | Hook | 静态 | Hook | 双模式 |
| 静态调用 | ❌ | ✅ | ❌ | ✅ |
| 类型安全 | ✅ | ✅ | ✅ | ✅ |

## Tooltip / Popover / Popconfirm

四个库均有，但参数命名略有差异：

```tsx
// antd
<Tooltip title="提示">
  <Button>Hover</Button>
</Tooltip>

// el-plus
<el-tooltip content="提示">
  <el-button>Hover</el-button>
</el-tooltip>

// naive
<n-tooltip>
  <template #trigger>
    <n-button>Hover</n-button>
  </template>
  提示
</n-tooltip>

// arco
<Tooltip content="提示">
  <Button>Hover</Button>
</Tooltip>
```

## 性能要点

1. **Modal/Drawer 嵌套**：避免多层嵌套，会导致 z-index 与焦点混乱
2. **大量消息**：限制 message/notification 并发数量，避免用户疲劳
3. **长内容**：用 `Modal` 的 `content` 配合懒加载组件
4. **动画性能**：复杂动画用 CSS `transform` 而非 `top/left`
