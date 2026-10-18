# 3D 建模提示词（以剑兵初版为准）

## 思路

初版剑兵定了画风：**大头盔盖住大半个头、脸是一块没有五官的土黄色、粗短身材、偏灰的低饱和配色（暖灰钢、暗红盔缨、褐色盾、深棕腿）、平涂 + 一层暗部、粗深褐描边**。

流程：
1. 用出图工具把初版扩成**三视图**（第 1 步）。
2. 丢进图生 3D（Tripo / Meshy / Rodin 都行）出模型（第 2 步）。
3. 自动绑骨 + 套动作（第 3 步）。
4. 导出 GLB 给我。我在 Godot 里用固定的王国保卫战视角相机 + 两层卡通明暗 + 黑色描边**渲成 2D 序列帧**，这样每个动作、每一帧画风都一致。

> 描边、明暗都在渲染时加，**模型贴图里不要画描边、不要画阴影**。

---

## 第 1 步：三视图（出图工具，垫初版图）

### 1a 剑兵本体（不拿武器，方便绑骨）

```
Character turnaround sheet of the attached character: exactly the same design, colors and proportions. Four views left to right: front, left side, back, right side. Orthographic, no perspective, same height in every view, plain white background.
Neutral A-pose: arms straight and angled 45 degrees down away from the body, open empty hands, legs slightly apart, standing straight. No sword, no shield.
Keep: oversized round steel kettle helmet with a dark red plume, featureless ochre face in the helmet opening (no eyes, no mouth), stubby body, short thick legs, big hands, muted desaturated colors.
Flat colors with one soft shade tone, even lighting, no cast shadows, no ground, no text.
```

### 1b 武器单独出（我在引擎里挂到手上）

```
Prop sheet in the same art style as the attached character, plain white background, orthographic, each prop shown from front and side:
a short broad steel sword with a brown leather-wrapped grip and a small crossguard; a kite-shaped wooden shield with a muted taupe face and a light grey steel rim.
Flat colors with one soft shade tone, no cast shadows, no text.
```

---

## 第 2 步：图生 3D

**上传**：1a 的正 / 侧 / 背视图（工具支持多视图就全传，不支持就只传正面）。

**文字提示词**（Meshy / Tripo 的 prompt 框）：

```
stylized chibi medieval footman soldier, oversized round steel kettle helmet with a red plume covering most of the head, featureless ochre face inside the helmet opening, stubby round body, short thick legs, big hands, A-pose, hand-painted flat color texture, muted desaturated palette, low poly, game-ready, clean topology, single mesh
```

**反向提示词**：

```
realistic, detailed face, eyes, nose, mouth, PBR metal, glossy, reflections, noisy texture, painted outlines, baked shadows, thin limbs, tall proportions, base, pedestal, ground plane, weapon fused to hand
```

**设置**：
| 项 | 建议 |
|---|---|
| 风格 | Stylized / Cartoon / Hand-painted（别选 Realistic / PBR） |
| 面数 | 3k–8k 三角面 |
| 贴图 | 开，1024，只要 Base Color |
| 对称 | 开 |
| 姿势 | A-pose |

武器（1b）同样流程各出一个，面数 500–1500，提示词：
`stylized chunky cartoon short sword, hand-painted flat colors, low poly` / `stylized chunky cartoon kite shield, taupe wooden face, grey steel rim, hand-painted flat colors, low poly`

**验收**：在工具里转一圈看——头盔要占全身高度的 40–45%，脸上不能长出眼睛鼻子，背面不能糊。不行就重出，或换一张三视图。

---

## 第 3 步：绑骨 + 动作

用 Meshy 自带的 Rigging / Animation，或者把模型传到 Mixamo（免费）。动作都选**原地**（In Place），帧率 30。

| 角色 | 需要的动作（名字照抄） |
|---|---|
| 剑兵 swordsman | `idle` `walk` `attack`（单手劈砍）`death` |
| 弓箭手 archer | `idle` `walk` `attack`（拉弓射箭）`death` |
| 农民 worker | `idle` `walk` `work`（挥镐/砍树）`carry`（扛着走）|
| 工程师 engineer | `idle` `walk` `attack`（双手锤砸下）`death` `build`（锤东西）|
| 史莱姆 goo | 不用绑骨，只要一个模型，动作我在引擎里用挤压拉伸做 |

---

## 第 4 步：导出给我

- 格式 **GLB**（贴图打包在里面），一个角色一个文件，动作都在同一个文件里
- 文件名：`models/swordsman.glb`、`models/archer.glb`、`models/worker.glb`、`models/engineer.glb`、`models/goo.glb`、`models/sword.glb`、`models/shield.glb`、`models/bow.glb`、`models/pickaxe.glb`、`models/hammer.glb`
- 角色脚底在原点，正面朝前，身高别管（我统一缩放）

---

## 其余角色：先出 2D 初版（垫剑兵初版当风格参考），再走上面 1–4 步

通用前缀：

```
A new character in exactly the same art style as the attached footman: same thick dark brown outline, flat colors with one shade tone, muted desaturated palette, same stubby proportions with an oversized head or headgear about 45% of total height, featureless ochre face with no eyes, nose or mouth, 3/4 front view, full body, plain white background, no text.
```

| 角色 | 接在前缀后面 |
|---|---|
| 弓箭手 | `a hooded archer: deep muted green hood and short cape hiding most of the head, brown leather jerkin and bracers, quiver on the back, short wooden recurve bow` |
| 农民 | `a peasant miner: wide floppy brown felt hat covering most of the head, beige rough tunic with a small muted blue sash, brown boots, a pickaxe` |
| 工程师英雄 | `a dwarf engineer hero, a little more detailed: round riveted iron helmet with brass goggles, huge bushy muted orange beard covering the lower face, leather apron over muted blue sleeves, tool belt, a big two-handed war hammer` |
| 史莱姆 | `a monster enemy: a squat toxic slime blob, murky olive green jelly with darker green shade, a few bone spikes on its back, two narrow mean yellow eyes and a jagged mouth (monsters may have faces)` |
