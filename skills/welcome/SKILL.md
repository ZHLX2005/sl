---
name: welcome
description: workflow-marketplace 快速入门指南
---

# workflow-marketplace 快速入门

## 安装

```shell
# 添加 Marketplace
/plugin marketplace add ZHLX2005/workflow-marketplace

# 安装插件
/plugin install sl@workflow-skills

# 重新加载使插件生效
/reload-plugins
```

## 功能概览

| 技能 | 描述 |
|------|------|
| `/welcome` | 显示本引导 |
| `/uv` | 如何创建新的 marketplace skill |

## 快速开始

### 1. 浏览可用技能

```shell
/plugin
# 转到"发现"选项卡查看所有插件
```

### 2. 安装新技能

```shell
/plugin install skill-name@workflow-skills
```

### 3. 创建自己的 Skill

参考 `/uv` 技能了解如何扩展 marketplace。

## 管理命令

| 操作 | 命令 |
|------|------|
| 添加 marketplace | `/plugin marketplace add ZHLX2005/workflow-marketplace` |
| 安装插件 | `/plugin install name@workflow-skills` |
| 列出已安装 | `/plugin list` |
| 重新加载 | `/reload-plugins` |
| 更新 marketplace | `/plugin marketplace update workflow-skills` |
| 卸载插件 | `/plugin uninstall name@workflow-skills` |

## 语言切换

本 marketplace 支持中文和英文引导。

- 默认语言跟随 Claude Code 设置
- 如需切换语言，请在 Claude Code 设置中调整
