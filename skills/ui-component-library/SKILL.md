---
name: ui-component-library
description: |
  UI 组件库参考索引 - 主流前端组件库（Ant Design / Element Plus / Naive UI / Arco Design）
  的使用方式、导入路径、组件文档地图。当用户询问 antd / element-plus / naive-ui /
  arco 等组件库使用、查找组件导入方式、选择合适的 UI 框架、或询问具体组件用法时
  使用本技能入口。详细使用文档在 references/ 子目录下按库分别组织。
---

# UI 组件库技能索引

主文档仅承担**入口映射**作用，具体使用方式与组件文档全部迁移至 `references/<lib>/` 扁平目录下（无 components/ 子目录嵌套）。

## 触发场景

- 用户询问 antd / element-plus / naive-ui / arco-design 等组件库的安装与导入方式
- 需要选择合适的前端 UI 框架
- 查询具体组件的 API（Form / Table / Modal / DatePicker 等）
- 配置主题、国际化、按需引入
- 解决组件库集成报错、版本升级问题

## 组件库映射表

| 组件库 | 框架 | 仓库版本 | references 入口 |
|--------|------|----------|-----------------|
| **Ant Design** | React | 6.5.2 | [[antd]] |
| **Element Plus** | Vue 3 | 2.x | [[element-plus]] |
| **Naive UI** | Vue 3 | 2.44.1 | [[naive-ui]] |
| **Arco Design** | React | 2.66.16 | [[arco-design]] |

## 选型速查

| 项目场景 | 推荐组件库 | 理由 |
|---------|-----------|------|
| React 中后台 + 大型团队 | **Ant Design** | 生态成熟、社区最大、企业首选 |
| React + 字节系设计语言 | **Arco Design** | 字节跳动内部风格、TypeScript 完整 |
| Vue 3 + 中文友好社区 | **Element Plus** | 文档详尽、组件最全 |
| Vue 3 + TypeScript 严格 | **Naive UI** | TypeScript-first、主题覆盖完整 |

## 路由工作流

1. 用户提出 UI 组件库相关问题 → 查上方映射表确定框架对应库
2. 点击 `[[<lib>]]` 跳转至对应 references 子目录（每个子目录包含 SKILL.md + 扁平的组件主题文档）

## References 索引（按需加载）

每个 UI 库的 references 包含主文档 SKILL.md 和扁平的组件主题文档：

| ref | 何时读取 | 路径 |
|-----|----------|------|
| [[antd]] | React 项目使用 antd、配置主题、查询 API | references/antd/SKILL.md |
| [[antd-form]] | 查询 antd 表单与输入组件 | references/antd/form.md |
| [[antd-data-display]] | 查询 antd 数据展示组件 | references/antd/data-display.md |
| [[antd-feedback]] | 查询 antd 反馈与提示组件 | references/antd/feedback.md |
| [[antd-navigation]] | 查询 antd 导航组件 | references/antd/navigation.md |
| [[antd-layout]] | 查询 antd 布局组件 | references/antd/layout.md |
| [[antd-others]] | 查询 antd 其他通用组件 | references/antd/others.md |
| [[element-plus]] | Vue 3 项目使用 Element Plus（el-* 组件） | references/element-plus/SKILL.md |
| [[element-plus-form]] | 查询 Element Plus 表单与输入组件 | references/element-plus/form.md |
| [[naive-ui]] | Vue 3 + TS 项目使用 Naive UI（N 前缀组件） | references/naive-ui/SKILL.md |
| [[naive-ui-form]] | 查询 Naive UI 表单与输入组件 | references/naive-ui/form.md |
| [[arco-design]] | React 项目使用 Arco Design（字节跳动） | references/arco-design/SKILL.md |
| [[arco-design-form]] | 查询 Arco Design 表单与输入组件 | references/arco-design/form.md |

## 关联 Skill（工具链）

- `key_board_3` — Skill References 优化器（合并 / 拆分的标准流程）
