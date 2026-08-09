# Arco Design 表单与输入组件

详细的 Arco Design 表单组件使用指南。

## 核心组件

### Form / Form.Item
表单容器，使用 `Form.useForm()` 创建实例。

```tsx
import { Form, Input, Button } from '@arco-design/web-react';
import { useRef } from 'react';

interface FormValues {
  username: string;
  email: string;
}

const [form] = Form.useForm<FormValues>();
const formRef = useRef(null);

const onSubmit = async (values: FormValues) => {
  try {
    await form.validate();
    console.log('valid', values);
  } catch (error) {
    console.log('invalid', error);
  }
};

<Form
  form={form}
  style={{ width: 480 }}
  onSubmit={onSubmit}
  autoComplete="off"
>
  <Form.Item field="username" label="用户名" rules={[{ required: true }]}>
    <Input placeholder="请输入用户名" />
  </Form.Item>
  <Form.Item field="email" label="邮箱" rules={[{ required: true, type: 'email' }]}>
    <Input placeholder="请输入邮箱" />
  </Form.Item>
  <Form.Item>
    <Button type="primary" htmlType="submit">提交</Button>
  </Form.Item>
</Form>
```

### Input
输入框。

```tsx
<Input placeholder="请输入" allowClear />
<Input.Password placeholder="请输入密码" />
<Input.TextArea placeholder="多行文本" rows={4} maxLength={200} showWordLimit />
<Input
  prefix={<IconUser />}
  suffix={<IconSearch />}
  placeholder="搜索"
/>
<Input
  addBefore="Http://"
  addAfter=".com"
  placeholder="域名"
/>
```

### InputNumber
数字输入框。

```tsx
<InputNumber min={0} max={100} step={1} placeholder="请输入" />
<InputNumber mode="button" precision={2} />
```

### Select
下拉选择器。

```tsx
import { Select } from '@arco-design/web-react';
const Option = Select.Option;

<Select placeholder="请选择" allowClear>
  <Option value="1">选项一</Option>
  <Option value="2">选项二</Option>
</Select>

<Select
  mode="multiple"
  placeholder="多选"
  allowClear
  filterOption
  showSearch
>
  {options.map(opt => (
    <Option key={opt.value} value={opt.value}>{opt.label}</Option>
  ))}
</Select>

<Select
  mode="tags"
  placeholder="输入后回车"
  tokenSeparators={[',']}
/>
```

### Cascader
级联选择器。

```tsx
<Cascader
  placeholder="请选择"
  options={options}
  allowClear
  expandTrigger="hover"
/>
```

### TreeSelect
树形选择器。

```tsx
import { TreeSelect } from '@arco-design/web-react';

<TreeSelect
  placeholder="请选择"
  treeData={treeData}
  allowClear
  multiple
  treeCheckable
/>
```

### AutoComplete / Mention
自动完成与提及。

```tsx
<AutoComplete
  placeholder="搜索"
  data={['北京', '上海', '广州', '深圳']}
  filterOption
/>

<Mention
  placeholder="@提及"
  data={['张三', '李四', '王五']}
/>
```

### DatePicker / TimePicker
日期与时间选择。

```tsx
import { DatePicker } from '@arco-design/web-react';
const { RangePicker } = DatePicker;

<DatePicker placeholder="选择日期" />
<RangePicker
  shortcuts={[
    { text: '今天', value: () => [dayjs(), dayjs()] },
    { text: '近7天', value: () => [dayjs().subtract(7, 'day'), dayjs()] },
    { text: '近30天', value: () => [dayjs().subtract(30, 'day'), dayjs()] },
  ]}
/>

<TimePicker placeholder="选择时间" />
```

### Upload
文件上传。

```tsx
import { Upload } from '@arco-design/web-react';

<Upload
  action="/api/upload"
  listType="picture-card"
  multiple
  limit={5}
  onExceedLimit={(files) => console.log('超过限制', files)}
  beforeUpload={(file) => {
    if (file.size > 5 * 1024 * 1024) {
      Message.warning('文件超过 5MB');
      return false;
    }
    return true;
  }}
/>
```

### Checkbox / Radio
复选框与单选框。

```tsx
<Checkbox>同意协议</Checkbox>

<Checkbox.Group
  value={selected}
  onChange={setSelected}
  direction="horizontal"
>
  <Checkbox value="A">选项A</Checkbox>
  <Checkbox value="B">选项B</Checkbox>
</Checkbox.Group>

<Radio.Group value={radio} onChange={setRadio}>
  <Radio value="1">选项一</Radio>
  <Radio value="2">选项二</Radio>
</Radio.Group>
```

### Switch / Slider / Rate

```tsx
<Switch checkedText="开" uncheckedText="关" />
<Slider min={0} max={100} step={1} range />
<Rate character="★" />
```

### ColorPicker
颜色选择器。

```tsx
<ColorPicker showAlpha format="hex" />
```

### VerificationCode
验证码输入。

```tsx
<VerificationCode length={6} onChange={setOtp} />
```

### InputTag
标签输入。

```tsx
<InputTag label="标签" placeholder="输入后回车" />
```

### Transfer
穿梭框。

```tsx
<Transfer
  dataSource={dataSource}
  targetKeys={targetKeys}
  onChange={setTargetKeys}
  showSearch
/>
```

## 性能要点

1. **大列表 Select**：使用 `virtualListProps` 开启虚拟滚动
2. **大表单**：拆分 `Form.Item`，使用 `Form.useWatch` 精确订阅
3. **动态字段**：用 `Form.List`（Arco 内置支持）
4. **高频校验**：使用 `trigger="onChange"` 改为 `onBlur` 减少校验次数

## 常见问题

### Q: Form.Item field 与 name 的区别？
A: Arco 用 `field`，antd 用 `name`，ElPlus 用 `prop`，Naive 用 `path`。语义一致。

### Q: 自定义上传如何写？
A: 设置 `customRequest` 替代 `action`，返回 Promise 控制成功/失败。

### Q: 表单字段动态增删？
A: 使用 `Form.List`，类似 antd 的 API。

### Q: Arco 与 antd 的 Form 区别？
A: API 高度相似；Arco 默认将 Form.useForm 返回的 form 实例传 `<Form form={form}>`。
