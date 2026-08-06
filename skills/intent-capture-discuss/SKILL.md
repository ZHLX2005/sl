---
name: intent-capture-discuss
description: 当用户希望整理需求、明确目的、描述问题，或要求"生成文档"、"整理意图"、"明确现象"时触发。用于通过多轮对话收集和整理需求，不执行任何代码修改。
---
1. 添加一个讨论模式 在 .claude/repo/_self/ 下面创建目录 让ai分析当前的结构 进行讨论
   并且按照一个主题的版本号-日期-主题进行命名,这个skill进行重构  用户讨论当前的项目结构和完成程度 生成文档 , 最后的产出是文档
   ,以及把用户的意图也生成文档 一个主题 里面两个目录 一个project 一个intent意图 ,然后 主题/project这个里面就是版本号-日期-主题的文档




结构案例: 


```
.claude/repo/_self/docx-thesis-style-pipeline-design/project/2026-06-02-v1
.claude/repo/_self/docx-thesis-style-pipeline-design/project /2026-06-02-v2
.claude/repo/_self/docx-thesis-style-pipeline-design/project  /2026-06-03-v3
.claude/repo/_self/docx-thesis-style-pipeline-design/intent/ ask
```




# case

添加
