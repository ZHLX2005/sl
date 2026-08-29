# Flood-Fill 去白底 + 色块岛屿提取（图像处理专项脚本）

> 何时读：用户要求"洪涌法去白边/去白底"、"抠图保留中心图案"、"提取色块岛屿"、"connected component / 连通域分离"或从图标合集图中分离各个图案时触发。
>
> 本文为图像处理类脚本的专项指导——配合 `tool-isolation` 主文档的 `.tool/` 隔离规范使用：脚本与依赖必须落在 `.tool/image-extractor/` 等隔离目录下，不进入项目源码。

## 触发场景

- "使用洪涌法去除白边，只保留中心图案"
- "去白底 / 抠图 / 提取透明 PNG"
- "获取所有色块岛屿 / 分离每个图案 / connected components"
- 图标合集图（sprite sheet）中把每个图案分离出来

## 与 tool-isolation 主规范的衔接

| 场景 | 路径 | 说明 |
|---|---|---|
| 单次图像处理脚本 | `.tool/image-extractor/scripts/extract.py` + `requirements.txt` | 按 `tool-isolation` 的 Python 工具流程走：`uv venv` → `uv pip install` → `uv run python3` |
| 多图批量处理 | `.tool/image-extractor/scripts/` 下加多个 `.py`，共享同一个 `.venv/` | 同一工具目录内复用 `requirements.txt` |
| 需要 GUI 预览 | `.tool/image-extractor/scripts/preview.py`（pillow 自带 `Image.show()`） | 不引入额外 GUI 依赖 |
| 产物输出 | `.tool/image-extractor/output/`（透明 PNG） | `.gitignore` 子目录模式加入 |

> 关键：图像处理脚本可能装 PIL/numpy/scipy 等较大依赖，必须隔离在 `.tool/` 下，否则污染项目 `requirements.txt` / `pyproject.toml`。

## 核心逻辑（洪涌法 / flood-fill）

**关键洞察**：只删「与图像边框连通的白」，而不是删「所有白」。
内部白（眼睛、肚皮、牙齿）不与边框相连，因此天然保留。

三步：
1. **白色候选**：`np.all(rgb >= WHITE_THRESHOLD, axis=2)`（阈值≈235）。
2. **洪涌**：`scipy.ndimage.label` 标记白色连通块，凡触及首/末行、首/末列的
   label 判为背景 → alpha=0；其余白保留。
3. **取岛屿**：对前景 `~bg` 再做一次 `ndimage.label`，每个连通块 = 一个岛屿，
   按 bounding box 裁剪导出透明 PNG。用最小面积阈值滤掉水印/杂点。

阅读顺序编号：`sort(key=(round(y0/行高), 中心x))` → 从上到下、从左到右。

## 参考实现骨架

```python
import numpy as np
from PIL import Image
from scipy import ndimage

rgb = np.asarray(Image.open(SRC).convert("RGB"))
is_white = np.all(rgb >= 235, axis=2)

# 洪涌：边框连通白 = 背景
lbl, _ = ndimage.label(is_white)
border = set(lbl[0]) | set(lbl[-1]) | set(lbl[:, 0]) | set(lbl[:, -1])
border.discard(0)
bg = np.isin(lbl, list(border))
fg = ~bg

# 整图去白底
full = np.dstack([rgb, np.where(fg, 255, 0).astype(np.uint8)])

# 岛屿 = 前景连通域
lbl2, n = ndimage.label(fg)
for idx in range(1, n + 1):
    m = lbl2 == idx
    if m.sum() < MIN_AREA:            # 滤水印/杂点
        continue
    ys, xs = np.where(m)
    y0, y1, x0, x1 = ys.min(), ys.max()+1, xs.min(), xs.max()+1
    crop = np.zeros((y1-y0, x1-x0, 4), np.uint8)
    crop[..., :3] = rgb[y0:y1, x0:x1]
    crop[..., 3] = np.where(m[y0:y1, x0:x1], 255, 0)
    Image.fromarray(crop, "RGBA").save(...)
```

## 关键前置确认（最高频返工点）

**动手前必须先问清两件事**，否则极易返工：

1. **是否要预先切网格分块？** 默认**不要切**——洪涌法本身就能靠背景分离图案。
   只有用户明确说「切 N 块」才切。
2. **输出形态**：整图透明底？还是每个岛屿单独一张？还是单一 bounding box 裁剪？
   「色块岛屿」= 每个连通域单独导出，不是整体一个 bbox。

## 环境坑

- 路径像 Windows（`D:\...`）但环境可能是 Git Bash：先 `pwd; ls` 探明，
  用 `/d/...` 形式的 POSIX 路径。
- **Python 一律用 `uv run python3`**（与 tool-isolation 主文档两铁律对齐），装包用
  `uv add pillow numpy scipy` 或 `uv pip install -r requirements.txt`，
  绝不用裸 `python` / `pip`。
- 工具目录初始化顺序（与 tool-isolation 主文档的「Python 工具流程」一致）：
  ```bash
  mkdir -p .tool/image-extractor/scripts
  cd .tool/image-extractor
  uv venv
  cat > requirements.txt <<'EOF'
  pillow>=10.0
  numpy>=1.24
  scipy>=1.11
  EOF
  uv pip install -r requirements.txt
  uv run python3 scripts/extract.py /d/path/to/source.png
  ```

## 错误案例

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| 删「所有白像素」而非「边框连通白」 | 眼睛、肚皮等内部白被抠穿 | 从边框种子 flood-fill，只删边框连通白 |
| 默认先切 8 块网格 | 用户其实要整图直接洪涌，返工 | 动手前先确认是否分块 |
| 用单一 bounding box 裁剪当成「岛屿」 | 只得到整体一张图，非各图案 | 对前景做连通域 label，逐个导出 |
| 裸跑 `python` / `pip install` | 违反 uv 规则、环境不一致 | `uv run python3` / `uv add` |
| 假设 macOS 直接写路径 | 实为 Windows Git Bash，路径错 | 先 `pwd; ls` 探明环境 |
| 未设最小面积阈值 | 水印、噪点混进岛屿列表 | 加 `MIN_AREA` 过滤 |
| 脚本写到项目根目录 | 污染项目源码、依赖进入 `requirements.txt` | 一律落到 `.tool/image-extractor/scripts/` |

## 成功标准检查清单

- [ ] 工具目录已建：`.tool/image-extractor/` 含 `requirements.txt` + `.venv/`
- [ ] 动手前已确认「是否分块」和「输出形态」
- [ ] 洪涌只删边框连通白，内部白保留
- [ ] 岛屿由 `ndimage.label(fg)` 得到，逐个透明裁剪导出
- [ ] 有最小面积阈值滤水印/杂点
- [ ] 全程 `uv run python3`，依赖装在 `.tool/image-extractor/.venv/`
- [ ] 至少 Read 一张输出图做视觉验证