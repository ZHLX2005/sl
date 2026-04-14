---
description: Guide for creating marketplace skills and how users install/update them
---

# Marketplace Skills 指南

## 如何快速扩展一个 Skill

### 1. 创建 Skill 文件结构

```
your-marketplace/
└── plugins/
    └── your-plugin/
        ├── .claude-plugin/
        │   └── plugin.json
        └── skills/
            └── your-skill/
                └── SKILL.md
```

### 2. 编写 SKILL.md

```markdown
---
description: Brief description of what this skill does
---

# Your Skill Title

Describe the skill functionality here...

## Commands

### Usage
Explain how to use it.
```

### 3. 创建 plugin.json

```json
{
  "name": "your-plugin",
  "description": "Plugin description",
  "version": "1.0.0"
}
```

### 4. 更新 marketplace.json

```json
{
  "name": "your-marketplace",
  "owner": { "name": "Your Name" },
  "plugins": [
    {
      "name": "your-plugin",
      "source": "./plugins/your-plugin",
      "description": "Your plugin description"
    }
  ]
}
```

### 5. 推送更新

```bash
git add .
git commit -m "Add new skill"
git push
```

---

## 用户如何使用你的 Marketplace

### 添加 Marketplace

**方式一：GitHub**
```shell
/plugin marketplace add owner/repo
# 例如：/plugin marketplace add ZHLX2005/sl
```

**方式二：本地路径**
```shell
/plugin marketplace add ./your-marketplace
```

**方式三：远程 URL**
```shell
/plugin marketplace add https://example.com/marketplace.json
```

### 浏览可用插件
```shell
/plugin
# 转到"发现"选项卡查看所有插件
```

---

## 安装插件

### 安装到用户范围（所有项目可用）
```shell
/plugin install plugin-name@marketplace-name
# 例如：/plugin install uv-workflow-plugin@workflow-skills
```

### 安装到项目范围（协作者共享）
```shell
/plugin install plugin-name@marketplace-name --scope project
```

### 安装到本地范围（仅自己）
```shell
/plugin install plugin-name@marketplace-name --scope local
```

---

## 更新插件和 Marketplace

### 更新单个插件
```shell
/plugin install plugin-name@marketplace-name
# 重新安装即可更新到最新版本
```

### 更新 Marketplace（获取新插件列表）
```shell
/plugin marketplace update marketplace-name
```

### 重新加载插件（使更改生效）
```shell
/reload-plugins
```

---

## 管理命令

### 列出已添加的 marketplaces
```shell
/plugin marketplace list
```

### 禁用插件（不卸载）
```shell
/plugin disable plugin-name@marketplace-name
```

### 启用已禁用的插件
```shell
/plugin enable plugin-name@marketplace-name
```

### 卸载插件
```shell
/plugin uninstall plugin-name@marketplace-name
```

### 删除 Marketplace
```shell
/plugin marketplace remove marketplace-name
```
**注意**：删除 marketplace 会同时卸载从中安装的所有插件。

---

## 示例：完整使用流程

```shell
# 1. 添加 marketplace
/plugin marketplace add ZHLX2005/sl

# 2. 安装插件
/plugin install uv-workflow-plugin@workflow-skills

# 3. 重新加载使插件生效
/reload-plugins

# 4. 使用 skill
/uv-workflow

# 5. 更新插件
/plugin install uv-workflow-plugin@workflow-skills
/reload-plugins

# 6. 更新 marketplace 获取新插件
/plugin marketplace update workflow-skills
```

---

## 快速参考

| 操作 | 命令 |
|------|------|
| 添加 marketplace | `/plugin marketplace add owner/repo` |
| 安装插件 | `/plugin install name@marketplace` |
| 重新加载 | `/reload-plugins` |
| 更新 marketplace | `/plugin marketplace update name` |
| 卸载插件 | `/plugin uninstall name@marketplace` |
| 删除 marketplace | `/plugin marketplace remove name` |
