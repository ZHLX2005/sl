# Naive UI 表单与输入组件

详细的 Naive UI 表单组件使用指南。

## 核心组件

### n-form / n-form-item
表单容器，使用 `:model` + `:rules` 实现校验。

```vue
<script setup lang="ts">
import { ref, reactive } from 'vue';
import type { FormInst, FormRules } from 'naive-ui';

const formRef = ref<FormInst | null>(null);
const form = reactive({
  username: '',
  email: '',
});

const rules: FormRules = {
  username: [
    { required: true, message: '请输入用户名', trigger: ['blur'] },
    { min: 3, max: 20, message: '长度 3-20', trigger: ['input'] },
  ],
  email: [
    { required: true, message: '请输入邮箱', trigger: ['blur'] },
    { type: 'email', message: '邮箱格式错误', trigger: ['input'] },
  ],
};

const handleSubmit = (e: Event) => {
  e.preventDefault();
  formRef.value?.validate((errors) => {
    if (!errors) console.log('valid', form);
  });
};
</script>

<template>
  <n-form ref="formRef" :model="form" :rules="rules">
    <n-form-item label="用户名" path="username">
      <n-input v-model:value="form.username" placeholder="请输入" />
    </n-form-item>
    <n-form-item label="邮箱" path="email">
      <n-input v-model:value="form.email" placeholder="请输入" />
    </n-form-item>
    <n-button type="primary" @click="handleSubmit">提交</n-button>
  </n-form>
</template>
```

### n-input
输入框，支持多种类型与状态。

```vue
<n-input v-model:value="value" placeholder="请输入" clearable />
<n-input v-model:value="pwd" type="password" show-password-on="click" />
<n-input v-model:value="text" type="textarea" :rows="4" />
<n-input v-model:value="value" status="warning" />
<n-input v-model:value="value" :input-props="{ autocomplete: 'username' }" />
```

### n-input-number
数字输入框。

```vue
<n-input-number v-model:value="value" :min="0" :max="100" :step="1" />
<n-input-number v-model:value="value" :precision="2" />
```

### n-select
下拉选择器。

```vue
<n-select
  v-model:value="value"
  :options="options"
  placeholder="请选择"
  filterable
  clearable
  remote
  :loading="loading"
  @search="handleSearch"
/>
```

options 格式：
```ts
const options = [
  { label: '选项一', value: '1' },
  { label: '选项二', value: '2' },
];
```

### n-cascader
级联选择器。

```vue
<n-cascader
  v-model:value="value"
  :options="options"
  check-strategy="child"
  expand-trigger="hover"
  filterable
/>
```

### n-date-picker
日期选择器，类型丰富。

```vue
<n-date-picker v-model:value="date" type="date" />
<n-date-picker v-model:value="range" type="daterange" />
<n-date-picker v-model:value="datetime" type="datetime" />
<n-date-picker v-model:value="month" type="month" />
<n-date-picker v-model:value="year" type="year" />
```

### n-time-picker
时间选择器。

```vue
<n-time-picker v-model:value="time" />
```

### n-upload
文件上传。

```vue
<n-upload
  :default-upload="false"
  :file-list="fileList"
  list-type="image-card"
  :max="5"
  @change="handleChange"
>
  点击上传
</n-upload>
```

自定义上传请求：
```ts
import type { UploadCustomRequestOptions } from 'naive-ui';

const customRequest = ({ file, onFinish, onError }: UploadCustomRequestOptions) => {
  const formData = new FormData();
  formData.append('file', file.file as File);
  fetch('/api/upload', { method: 'POST', body: formData })
    .then(() => onFinish())
    .catch(() => onError());
};
```

### n-checkbox / n-radio
复选框与单选框。

```vue
<n-checkbox v-model:checked="checked">同意</n-checkbox>
<n-checkbox-group v-model:value="selected">
  <n-checkbox value="A">A</n-checkbox>
  <n-checkbox value="B">B</n-checkbox>
</n-checkbox-group>

<n-radio-group v-model:value="radio">
  <n-radio value="1">选项一</n-radio>
  <n-radio value="2">选项二</n-radio>
</n-radio-group>
```

### n-switch / n-slider / n-rate

```vue
<n-switch v-model:value="enabled" />
<n-slider v-model:value="value" :min="0" :max="100" />
<n-rate v-model:value="rating" />
```

### n-color-picker
颜色选择器。

```vue
<n-color-picker v-model:value="color" :show-alpha="true" />
```

### n-input-otp（验证码输入）

```vue
<n-input-otp v-model:value="otp" :length="6" />
```

### n-dynamic-tags / n-dynamic-input

```vue
<n-dynamic-tags v-model:value="tags" />
<n-dynamic-input v-model:value="value" :on-update:value="handleUpdate" />
```

## 性能要点

1. **大列表 Select**：使用 `virtual-scroll` 属性开启虚拟滚动
2. **大表单**：用 `n-form-item` 拆分，使用 `form.shouldDisplay` 控制
3. **动态表单**：用 `n-dynamic-input` 或 `n-dynamic-tags`
4. **高频输入**：使用 `debounce` 或 `throttle` 控制响应

## 常见问题

### Q: 表单校验失败如何获取错误？
A: `validate()` 回调中 `errors` 字段会返回校验错误对象。

### Q: n-form-item path 与 prop 的关系？
A: Naive UI 用 `path` 字段指向 model 中的字段路径（支持点号嵌套）。

### Q: n-date-picker 默认值？
A: 默认是时间戳数字。可通过 `value-format` 调整。

### Q: n-input-number 精度问题？
A: 设置 `:precision="2"` 控制小数位数。
