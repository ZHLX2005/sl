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

## 关键 API 速查（项目无关）

去白底 + 岛屿提取涉及的核心 API 全在 `numpy` + `scipy.ndimage` + `PIL` 标准组合里。
下表列出每个 API 的精确用法与适用环节，按"流水线顺序"组织：

| # | API | 来源 | 作用 | 典型用法 |
|---|-----|------|------|---------|
| 1 | `Image.open(p).convert("RGB")` | PIL | 读图 → RGB（剥离 alpha/调色板） | 入口 |
| 2 | `np.asarray(rgb_img)` | numpy | PIL → (H,W,3) uint8 ndarray | 入口 |
| 3 | `np.all(arr >= T, axis=2)` | numpy | 沿通道维"全部满足" → (H,W) bool | 白色候选 |
| 4 | `np.max(arr, axis=2)` / `np.min(arr, axis=2)` | numpy | 通道最大/最小 → (H,W) | 颜色阈值 |
| 5 | `ndimage.label(mask)` | scipy | 连通域标记 → `(lbl, n)`，lbl 同 label 同号 | 洪涌 / 岛屿 |
| 6 | `np.isin(lbl, list)` | numpy | label 集合成员 → (H,W) bool | 边框连通筛选 |
| 7 | `ndimage.gaussian_filter(arr, sigma=s)` | scipy | 高斯模糊 → 软蒙版（边缘抗锯齿） | 蒙版优化 |
| 8 | `np.where(cond, x, y)` | numpy | 条件选择 | 软阈值化（>0.5 → 255） |
| 9 | `np.dstack([rgb, alpha])` | numpy | 沿第三轴堆叠 → (H,W,4) RGBA | 构造输出 |
| 10 | `Image.fromarray(arr, "RGBA").save(p)` | PIL | (H,W,4) → 透明 PNG | 写出 |
| 11 | `arr[py0:py1, px0:px1]` | numpy | bbox 切片 → crop | 岛屿裁剪 |
| 12 | `arr[..., 0]` / `arr[..., 2]` | numpy | 取 R / B 通道 | 暖色判别 |
| 13 | `arr.astype(int)` / `.astype(np.float32)` | numpy | 类型提升（避免 uint8 减法下溢） | 通道差计算 |
| 14 | `&` `|` `~` | numpy | element-wise 布尔运算 | 多蒙版合并 |

**易错点**：
- `np.all(arr >= T, axis=2)`：通道维 axis 是 **2**（HWC 布局），不是 -1。
- `ndimage.label(mask)` 输入必须是 **bool 或 0/1 int**，不能是浮点 0/1。
- 通道差 `(R - B).astype(int)` 必须先 `astype(int)`——uint8 减法会下溢（255 → 1）。
- `gaussian_filter` 输入浮点，输出浮点；最后 `> 0.5` 阈值化回 uint8。

## 典型变体（实战沉淀）

> 以下 4 个变体是真实场景提炼，与"骨架代码"正交——按需叠加。

### 变体 1：按颜色精修蒙版（剔除阴影 / 保留装饰色）

**问题**：原图含浅灰阴影、金/银装饰、杂色等"非白非黑"前景，直接连通域会把它们一起切走。

**解法**：分两层蒙版——先识别「主体色」再「剔除干扰色」。

```python
# 通道极值
max_v = np.max(crop_rgb, axis=2)
min_v = np.min(crop_rgb, axis=2)

# 浅灰阴影判别：max > 180 且 max-min ≤ 15（亮度高但饱和度极低）
SHADOW_MAX, SHADOW_RANGE = 180, 15
is_shadow = (max_v > SHADOW_MAX) & ((max_v - min_v) <= SHADOW_RANGE)

# 黑色主体判别：暗像素 OR 暖色像素（金边 R-B > 30）
BLACK_PIECE_MAX_RGB, GOLD_R_MINUS_B = 150, 30
is_dark = max_v <= BLACK_PIECE_MAX_RGB
is_warm = (crop_rgb[..., 0].astype(int) - crop_rgb[..., 2].astype(int)) > GOLD_R_MINUS_B
is_piece = is_dark | is_warm

# 蒙版 = 主体 ∩ 非阴影 ∩ 原前景
refined = is_piece & ~is_shadow & crop_mask
```

**关键洞察**：不要一次性 `mask = ~is_white` 把所有非白当主体。要分"主体 / 干扰"两层。
**适用场景**：图标含阴影、棋盘金边、UI 含高光/反光等。

### 变体 2：高斯模糊 + 重阈值（边缘抗锯齿）

**问题**：裁剪出来的透明 PNG 边缘锯齿明显（png 256 级 alpha 没有中间值）。

**解法**：把布尔蒙版转 float → 高斯模糊 → 0.5 阈值回 uint8。

```python
soft = ndimage.gaussian_filter(rough.astype(np.float32), sigma=0.7)
alpha = np.where(soft > 0.5, 255, 0).astype(np.uint8)
```

**σ 经验值**：

| σ | 效果 |
|---|------|
| 0.0 | 不模糊，保留锯齿 |
| 0.5 | 极轻微平滑，硬边缘首选 |
| 0.7 | 标准抗锯齿（推荐） |
| 1.0 | 边缘明显柔化 |
| ≥ 2.0 | 细节丢失，仅适合超写实风格 |

**进阶**：要真透明渐变（半透明描边）可省掉 `> 0.5` 阈值，直接 `soft * 255`。

### 变体 3：岛屿排序（按行优先 + 列次之）

**问题**：连通域 label 顺序随机（按扫描顺序），用户看到的岛屿列表顺序不符合视觉阅读习惯。

**解法**：按 bbox 中心坐标做 `(row, cx)` 二元排序——"先上后下、先左后右"。

```python
def sort_key(item: dict) -> tuple[int, int]:
    cy, cx = item["center"][1], item["center"][0]
    # 上下两段式（适合双排棋盘/双行图）
    row = 0 if cy < h // 2 else 1
    return (row, cx)

islands.sort(key=sort_key)
```

**替代方案**：
- 固定行高：`row = cy // ROW_HEIGHT`（适合规整表格）
- 自适应行高：先 KMeans 聚类 cy，再按聚类顺序排 cx
- 阅读顺序（中文 / 英文 / 数字）：按 `cy` 升序，同行按 `cx` 升序。

### 变体 4：bbox + padding 留白（避免切到棋子边）

**问题**：bbox 紧贴前景边缘，裁出来的图没有视觉呼吸空间。

**解法**：bbox 各边外扩 N 像素，越界用 `max(0, ...)` / `min(h, ...)` 截断。

```python
PADDING = 20
py0, py1 = max(0, y0 - PADDING), min(h, y1 + PADDING)
px0, px1 = max(0, x0 - PADDING), min(w, x1 + PADDING)
```

**PADDING 经验值**：

| 图幅尺寸 | PADDING | 说明 |
|---------|---------|------|
| < 200px | 10 | 小图标紧凑留白 |
| 200-500px | 20 | 标准图标 |
| 500-1500px | 30-50 | 大图 / 棋子 |
| > 1500px | 80+ | 海报级 |

## 参数调优速查

按"问题 → 调哪个参数 → 方向"组织：

| 现象 | 调谁 | 方向 |
|------|------|------|
| 浅灰阴影没被剔除（残留在透明底上） | `SHADOW_MAX` ↑ / `SHADOW_RANGE` ↓ | 收紧阴影条件 |
| 金边 / 装饰色被当作阴影误删 | `GOLD_R_MINUS_B` ↓ | 放宽暖色判别 |
| 棋子深色边缘丢失（半透明变全透明） | `BLACK_PIECE_MAX_RGB` ↑ | 提亮主体判别 |
| 小图标被 `MIN_AREA` 滤掉 | `MIN_AREA` ↓ | 按目标岛屿大小调 |
| 透明 PNG 边缘锯齿 | `EDGE_SMOOTH_SIGMA` ↑（如 0.7 → 1.0） | 增加模糊 |
| 内部白（如眼睛高光）被洪涌误删 | 加大 `WHITE_THRESHOLD` 没用（洪涌只看边框连通）→ 改用更宽松的内部白保留策略：把 `np.all(rgb >= T)` 换成 `np.mean(rgb, axis=2) >= T` | 改白色定义 |
| 边框留白有水印残留 | 加 MAX_BOTTOM_Y 或 MAX_TOP_Y 排除指定行 | Y 范围过滤 |
| 岛屿列表顺序不符合视觉习惯 | 用变体 3 的 sort_key 调整 | 改排序键 |
| 裁剪图边缘顶到边界 | 加大 `PADDING` | 留白扩展 |

## 反模式速查

| 反模式 | 为何不行 |
|--------|---------|
| `mask = (rgb != [255,255,255]).all(axis=2)` | 直接反色——内部白（眼睛、肚皮）一起被删 |
| `mask = np.all(rgb >= 200, axis=2)` 一次完成 | 把"白候选"和"非白前景"混为一谈，无法做边框洪涌 |
| 手动遍历 `for y in range(h): for x in range(w):` | O(H*W) Python 循环太慢，必须走 numpy 矢量化 |
| `from PIL import Image` 直接转 numpy 用 `np.array` | `np.array` 会复制但保留 dtype，`np.asarray` 在可能时共享内存（更快） |
| 不用 `convert("RGB")` 直接读 | PNG 带 alpha / 调色板会得到 RGBA / P 模式，shape 不一致会爆 |
| `gaussian_filter(mask, sigma=0.7)` 直接传 bool | bool 不支持模糊，必须先 `.astype(np.float32)` |