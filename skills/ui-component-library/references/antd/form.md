# 表单与输入组件（Form & Input）

按 UI 库分类列出最常用的表单组件，按需查阅。

## 速查表

| 用途 | Ant Design | Element Plus | Naive UI | Arco Design |
|------|------------|--------------|----------|-------------|
| 按钮 | `Button` | `el-button` | `NButton` | `Button` |
| 输入框 | `Input` | `el-input` | `NInput` | `Input` |
| 数字输入 | `InputNumber` | `el-input-number` | `NInputNumber` | `InputNumber` |
| 文本域 | `Input.TextArea` | `el-input type="textarea"` | `NInput type="textarea"` | `Input.TextArea` |
| 密码 | `Input.Password` | `el-input type="password"` | `NInput type="password"` | `Input.Password` |
| 复选框 | `Checkbox` | `el-checkbox` | `NCheckbox` | `Checkbox` |
| 单选框 | `Radio` | `el-radio` | `NRadio` | `Radio` |
| 选择器 | `Select` | `el-select` | `NSelect` | `Select` |
| 级联选择 | `Cascader` | `el-cascader` | `NCascader` | `Cascader` |
| 树选择 | `TreeSelect` | `el-tree-select` | `NTreeSelect` | `TreeSelect` |
| 开关 | `Switch` | `el-switch` | `NSwitch` | `Switch` |
| 滑块 | `Slider` | `el-slider` | `NSlider` | `Slider` |
| 日期选择 | `DatePicker` | `el-date-picker` | `NDatePicker` | `DatePicker` |
| 时间选择 | `TimePicker` | `el-time-picker` | `NTimePicker` | `TimePicker` |
| 日期范围 | `DatePicker.RangePicker` | `el-date-picker type="daterange"` | `NDatePicker type="daterange"` | `DatePicker.RangePicker` |
| 上传 | `Upload` | `el-upload` | `NUpload` | `Upload` |
| 自动完成 | `AutoComplete` | `el-autocomplete` | `NAutoComplete` | `AutoComplete` |
| 提及 | `Mentions` | `el-mention` | - | `Mentions` |
| 穿梭框 | `Transfer` | `el-transfer` | `NTransfer` | `Transfer` |
| 颜色选择 | `ColorPicker` | `el-color-picker` | `NColorPicker` | `ColorPicker` |
| 评分 | - | `el-rate` | `NRate` | `Rate` |
| 验证码 | - | - | `NInputOtp` | `VerificationCode` |
| 标签输入 | - | - | `NDynamicTags` | `InputTag` |
| 表单 | `Form` | `el-form` | `NForm` | `Form` |

## Form 用法对比

### Ant Design Form
```tsx
import { Form, Input, Button } from 'antd';
const [form] = Form.useForm();

<Form form={form} onFinish={onFinish}>
  <Form.Item name="username" rules={[{ required: true, message: '请输入' }]}>
    <Input />
  </Form.Item>
  <Button htmlType="submit">提交</Button>
</Form>
```

### Element Plus Form
```vue
<el-form ref="formRef" :model="form" :rules="rules">
  <el-form-item label="用户名" prop="username" :rules="[{ required: true }]">
    <el-input v-model="form.username" />
  </el-form-item>
  <el-button type="primary" @click="submit">提交</el-button>
</el-form>
```

### Naive UI Form
```vue
<n-form ref="formRef" :model="form" :rules="rules">
  <n-form-item label="用户名" path="username" :rule="[{ required: true }]">
    <n-input v-model:value="form.username" />
  </n-form-item>
  <n-button type="primary" @click="submit">提交</n-button>
</n-form>
```

### Arco Design Form
```tsx
import { Form, Input, Button } from '@arco-design/web-react';
const [form] = Form.useForm();

<Form form={form} onSubmit={onSubmit}>
  <Form.Item field="username" rules={[{ required: true }]}>
    <Input />
  </Form.Item>
  <Button htmlType="submit" type="primary">提交</Button>
</Form>
```

## 关键差异

| 维度 | Ant Design | Element Plus | Naive UI | Arco Design |
|------|------------|--------------|----------|-------------|
| Form 实例 | `Form.useForm()` | `ref` 拿到 form 实例 | `ref` 拿到 form 实例 | `Form.useForm()` |
| 字段路径 | `Form.Item name` | `el-form-item prop` | `n-form-item path` | `Form.Item field` |
| 验证规则位置 | `Form.Item rules` | `el-form-item :rules` | `n-form-item :rule` | `Form.Item rules` |
| 获取值 | `form.getFieldsValue()` | `formRef.value.model` | `formRef.value.model` | `form.getFieldsValue()` |
| 重置 | `form.resetFields()` | `formRef.value.resetFields()` | `formRef.value.restoreValidation()` | `form.resetFields()` |

## 表单校验

四个库都基于 `async-validator` 或类似实现，规则语法高度相似：

```js
{
  required: true,
  message: '必填',
  min: 3,
  max: 20,
  pattern: /^[a-zA-Z]/,
  validator: async (rule, value) => { /* 自定义 */ },
}
```

## 性能建议

1. **大表单**：拆分 `Form.Item`，使用 `useWatch` 精确订阅
2. **动态字段**：用 `Form.List`（antd）/ `Form.useFormList` 等动态 API
3. **高频输入**：使用 `Form.Item shouldUpdate` 控制重渲染
4. **复杂联动**：将表单状态抽到外层 store（pinia / zustand / redux）
