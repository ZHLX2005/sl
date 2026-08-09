# Element Plus 表单与输入组件

详细的 Element Plus 表单组件使用指南。

## 核心组件

### el-form / el-form-item
表单容器，使用 `:model` + `:rules` 实现数据双向绑定与校验。

```vue
<script setup lang="ts">
import { reactive, ref } from 'vue';
import type { FormInstance, FormRules } from 'element-plus';

const formRef = ref<FormInstance>();
const form = reactive({
  username: '',
  email: '',
});

const rules: FormRules = {
  username: [
    { required: true, message: '请输入用户名', trigger: 'blur' },
    { min: 3, max: 20, message: '长度 3-20' },
  ],
  email: [
    { required: true, message: '请输入邮箱' },
    { type: 'email', message: '邮箱格式错误' },
  ],
};

const submitForm = async () => {
  if (!formRef.value) return;
  await formRef.value.validate((valid, fields) => {
    if (valid) console.log('submit', form);
    else console.log('error', fields);
  });
};
</script>

<template>
  <el-form ref="formRef" :model="form" :rules="rules" label-width="120px">
    <el-form-item label="用户名" prop="username">
      <el-input v-model="form.username" />
    </el-form-item>
    <el-form-item label="邮箱" prop="email">
      <el-input v-model="form.email" type="email" />
    </el-form-item>
    <el-form-item>
      <el-button type="primary" @click="submitForm">提交</el-button>
    </el-form-item>
  </el-form>
</template>
```

### el-input
输入框，支持多种类型：`text`、`password`、`textarea`、`number`。

```vue
<el-input v-model="value" placeholder="请输入" clearable />
<el-input v-model="pwd" type="password" show-password />
<el-input v-model="text" type="textarea" :rows="4" />
<el-input v-model="num">
  <template #prepend>Http://</template>
  <template #append>.com</template>
</el-input>
```

### el-select / el-option
下拉选择器，支持单选、多选、远程搜索、可清空。

```vue
<el-select v-model="value" placeholder="请选择" filterable clearable>
  <el-option label="选项一" value="1" />
  <el-option label="选项二" value="2" />
</el-select>

<!-- 远程搜索 -->
<el-select
  v-model="value"
  :remote-method="remoteSearch"
  :loading="loading"
  filterable
  remote
  reserve-keyword
>
  <el-option v-for="item in options" :key="item.id" :label="item.name" :value="item.id" />
</el-select>
```

### el-cascader
级联选择器，常用于省市区、分类树。

```vue
<el-cascader
  v-model="value"
  :options="options"
  :props="{ value: 'id', label: 'name', children: 'children' }"
/>
```

### el-date-picker
日期选择器，类型丰富。

```vue
<el-date-picker v-model="date" type="date" placeholder="选择日期" />
<el-date-picker v-model="range" type="daterange" range-separator="至" />
<el-date-picker v-model="datetime" type="datetime" />
<el-date-picker v-model="month" type="month" />
```

### el-time-picker / el-time-select
时间选择器。

```vue
<el-time-picker v-model="time" />
<el-time-select v-model="time" start="08:00" end="20:00" step="00:30" />
```

### el-upload
文件上传，支持多种上传方式与钩子。

```vue
<el-upload
  action="/api/upload"
  :headers="{ Authorization: token }"
  :on-success="handleSuccess"
  :before-upload="beforeUpload"
  :file-list="fileList"
  list-type="picture-card"
>
  <el-icon><Plus /></el-icon>
</el-upload>
```

### el-checkbox / el-radio
复选框与单选框，支持组。

```vue
<el-checkbox v-model="checked">同意协议</el-checkbox>
<el-checkbox-group v-model="selected">
  <el-checkbox value="A">A</el-checkbox>
  <el-checkbox value="B">B</el-checkbox>
</el-checkbox-group>

<el-radio-group v-model="radio">
  <el-radio value="1">选项一</el-radio>
  <el-radio value="2">选项二</el-radio>
</el-radio-group>
```

### el-switch / el-slider
开关与滑块。

```vue
<el-switch v-model="enabled" />
<el-slider v-model="value" :min="0" :max="100" />
```

### el-color-picker
颜色选择器。

```vue
<el-color-picker v-model="color" show-alpha />
```

## 性能要点

1. **大列表 Select**：使用 `virtualization` 开启虚拟滚动（v2.6+）
2. **大列表 Cascader**：使用 `lazy` 懒加载模式
3. **大文件 Upload**：分片上传 + 并发控制
4. **高频 Input**：使用 `debounce` 包一层或 `v-model.lazy`

## 常见问题

### Q: el-form 校验不生效？
A: 检查 `el-form-item` 的 `prop` 是否与 `:model` 中的字段名一致。

### Q: el-select 远程搜索不显示 loading？
A: 设置 `:loading="loading"` 并在 `remote-method` 中切换状态。

### Q: el-upload 自动上传失败？
A: 检查 `action` 是否返回正确响应格式；可使用 `:http-request` 自定义上传逻辑。
