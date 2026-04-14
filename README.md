# sl

Claude Code 工作流市场插件 — 提供技能创建指南和预置自动化工作流。

## 安装

```bash
# 添加 Marketplace
claude plugin marketplace add ZHLX2005/sl

# 安装插件
claude plugin install sl@sl

# 重新加载使插件生效
/reload-plugins
```

## 技能列表

| 技能 | 命令 | 描述 |
|------|------|------|
| 欢迎引导 | `/welcome` | 快速入门指南 |
| 创建 Skill | `/uv` | 如何创建新的 marketplace skill |

## 快速开始

### 1. 浏览可用技能

```bash
/plugin
# 转到"发现"选项卡查看所有插件
```

### 2. 使用技能

```bash
/welcome   # 查看本引导
/uv        # 学习如何创建新技能
```

### 3. 安装额外技能

```bash
/plugin install skill-name@sl
/reload-plugins
```

## 管理命令

| 操作 | 命令 |
|------|------|
| 添加 marketplace | `/plugin marketplace add ZHLX2005/sl` |
| 安装插件 | `/plugin install sl@sl` |
| 列出已安装 | `/plugin list` |
| 重新加载 | `/reload-plugins` |
| 更新 marketplace | `/plugin marketplace update sl` |
| 更新插件 | `/plugin install sl@sl` |
| 卸载插件 | `/plugin uninstall sl@sl` |
| 删除 marketplace | `/plugin marketplace remove sl` |

## 更新插件

```bash
# 方式一：重新安装
/plugin install sl@sl

# 方式二：更新 marketplace 获取最新插件列表
/plugin marketplace update sl
```

## 完整使用流程

```bash
# 1. 添加 marketplace
/plugin marketplace add ZHLX2005/sl

# 2. 安装插件
/plugin install sl@sl

# 3. 重新加载使插件生效
/reload-plugins

# 4. 使用技能
/welcome

# 5. 学习创建新技能
/uv

# 6. 更新插件
/plugin install sl@sl
/reload-plugins
```

## 疑难解答

**Q: 安装后技能没有出现？**
```bash
/reload-plugins
```

**Q: 如何创建自己的技能？**
```bash
/uv
```

**Q: 如何卸载？**
```bash
/plugin uninstall sl@sl
/plugin marketplace remove sl
```
