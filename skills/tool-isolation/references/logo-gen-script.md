# Logo 生成脚本（撞色字母图标 + favicon 全套）

> 何时读：用户要求"生成 logo / 图标 / favicon"、"换个撞色配色的 logo"、"改 logo 字母重新出图"，或任何「纯色底 + 字母」类图标生成需求时触发。脚本模板与撞色方案表以本 ref 为准。

## 定位

`tool-isolation` 主文档管「工具放哪、怎么隔离」；本 ref 管「logo 生成这一类脚本怎么写、撞色方案有哪些、有哪些坑」。参考实现已在 nx-rp 项目落地并验证：`.tool/logo-gen/scripts/gen_logo.py`（pillow 单文件，无系统字体依赖问题用回退链解决）。

## 工具目录初始化

```
mkdir -p .tool/logo-gen/scripts
cd .tool/logo-gen
uv venv
echo "pillow>=11.0" > requirements.txt
uv pip install -r requirements.txt
uv run python scripts/gen_logo.py --letters rp          # 默认方案 mars
uv run python scripts/gen_logo.py --letters abc --scheme klein
```

产物 6 件套（输出 `<项目根>/src/web/frontend/public/`，`--out` 可覆盖）：
`logo.png`（透明底字标）、`logo-rounded.png`（512px 圆角卡片）、`favicon-{16,32,48}.png`、`favicon.ico`（多尺寸 16/32/48）。

## 撞色方案表（背景 bg + 字母 fg）

撞色关系落在「背景 vs 字母」上——**先问清用户撞色在哪**：是底和字母撞，还是字母之间撞（前者：单色字母；后者：透明底/浅底多色字母）。经典撞色短名单（默认 mars）：

| scheme | 背景 | 字母 | 色值（bg / fg） |
| --- | --- | --- | --- |
| `klein` | 克莱因蓝 | 松花黄 | `#002EA6` / `#FFE76F` |
| `mars` ★默认 | 马尔斯绿 | 玫瑰粉 | `#01847F` / `#F9D2E4` |
| `hermes` | 爱马仕橙 | 深蓝 | `#FF770F` / `#000026` |
| `tiffany` | 蒂芙尼蓝 | 奶酪色 | `#80D1C8` / `#F8F5D6` |
| `red` | 中国红 | 淡黄 | `#FF0000` / `#FAEAD3` |
| `vandyke` | 凡戴克棕 | 浅卡其 | `#492D22` / `#D8C7B5` |
| `prussian` | 普鲁士蓝 | 雾灰 | `#003153` / `#E5DDD7` |

新增方案 = 在脚本 `SCHEMES` 字典加一行 + 本表补一行。

## 实现要点（每条都踩过坑）

| # | 要点 | 说明 |
| --- | --- | --- |
| 1 | **自绘字形 vs 系统字体** | 自绘多边形轮廓「任何机器像素级一致」但字形僵硬（r 臂、p 碗生硬）；系统粗体字形漂亮但依赖机器字体。**默认用系统字体回退链**（verdanab → arialbd → segoeuib → calibrib → DejaVuSans-Bold），`--font` 可覆盖。追求极致一致才自绘 |
| 2 | **字号自适应用包围盒缩放** | probe 字号 100 → `textbbox` 量包围盒 → 按 `min(box_w/bb_w, box_h/bb_h)` 等比缩放。不要猜字号 |
| 3 | **4x 超采样 + LANCZOS** | 所有几何按 4x 画再缩小，16px favicon 边缘依然干净 |
| 4 | **文字着色走 L 蒙版 paste** | `mask` 上画白字 → `canvas.paste(纯色图, (0,0), mask)`。直接 `draw.text(fill=色)` 在 RGBA 上会有灰边 |
| 5 | **透明底字标先量 bbox 再裁** | 大字号画出字母 → `textbbox` → 裁包围盒 + 边距 → 缩放到目标宽。宽度固定、高度随字数自然变化 |
| 6 | **默认输出路径锚定脚本位置** | `Path(__file__).resolve().parents[3]` 推导项目根，与 CWD 无关。相对路径默认值会在工具目录下再建一套 `src/web/...`（真踩过） |
| 7 | **ico 多尺寸一次生成** | `img.save("favicon.ico", sizes=[(16,16),(32,32),(48,48)])`，源图用 48px 缩好的，浏览器自己挑 |
| 8 | **favicon 全套都出** | PNG 16/32/48 + ico + apple-touch-icon（用 logo-rounded），index.html 挂 `<link rel="icon">` 三连 |

## 前端接入（nx-rp 实测）

```html
<!-- index.html -->
<link rel="icon" type="image/png" sizes="32x32" href="/favicon-32.png" />
<link rel="icon" type="image/png" sizes="16x16" href="/favicon-16.png" />
<link rel="icon" type="image/x-icon" href="/favicon.ico" />
<link rel="apple-touch-icon" href="/logo-rounded.png" />
```

```jsx
// header brand（App.jsx）
<div className="brand"><img src="/logo-rounded.png" alt="" />nx-rp<span className="sub">…</span></div>
```

```css
/* style.css —— 22px 小图展示 */
.brand { display: inline-flex; align-items: center; gap: 8px; }
.brand img { width: 22px; height: 22px; border-radius: 6px; display: block; }
```

## 错误案例

| 错误操作 | 实际后果 | 正确做法 |
| --- | --- | --- |
| `--out` 默认值写相对路径 | 从工具目录跑时产物写进 `.tool/logo-gen/src/web/...`，真目标没更新 | 默认路径用 `Path(__file__)` 锚定项目根 |
| Windows Git Bash 跑 `uv run python3` | WindowsApps 的 python3 存根 exit 49（无输出） | 该机器用 `uv run python`；脚本内逻辑不受影响 |
| 撞色理解错方向（字母间撞 vs 底字撞） | 出图后返工重画 | 动手前确认撞色关系落在哪 |
| 自绘多边形字形硬上 | 字形僵硬、调试坐标耗时 | 默认系统字体回退链，`--font` 兜底 |
| 生成了新图没视觉验证 | 旧图/错色悄悄上线 | 产物必须 Read 一张确认（参照主文档清单） |
| 报错中文在控制台乱码 | 以为脚本坏了 | Windows 控制台 GBK 显示问题，逻辑正常；关键报错可写英文 |

## 成功标准检查清单

- [ ] 工具在 `.tool/logo-gen/`，依赖走 `uv`（`.venv/` 内）
- [ ] 已确认撞色关系（底字撞 or 字母间撞）与方案（默认 mars）
- [ ] 字母 1~5 位限制生效，字号自适应居中
- [ ] 6 件套齐全：logo.png / logo-rounded.png / favicon-{16,32,48}.png / favicon.ico
- [ ] 默认输出锚定项目根 public/，与 CWD 无关
- [ ] 至少 Read 一张产物做视觉验证
- [ ] index.html / brand 样式已接入（如为首接入）

## 关联引用

- `tool-isolation` 主文档：`.tool/` 隔离规范、Python 两铁律（uv + python3）、验证清单
- [[flood-fill-image-script]]：同类图像处理专项脚本（抠图/岛屿提取）
