# 《旗与铁》美术素材需求单（王国保卫战风格）

> 给生图模型用。按本文逐条出图，**文件名照抄**，全部放进一个 `art/` 文件夹打包即可。
> 共 **58 张**：P0 必做 32 张（做完游戏就能换皮）· P1 建议 18 张 · P2 锦上添花 8 张。

---

## 0. 全局规则（每张图都要遵守）

### 0.1 统一风格前缀（每条提示词前面都加上这段）

```
Kingdom Rush style 2D game asset, hand-painted cartoon fantasy, thick dark brown outline (#2A1A0E),
cel shading with soft gradients, warm vibrant saturated colors, chunky exaggerated proportions,
light coming from top-left, clean readable silhouette, high detail, mobile strategy game art,
isolated on a plain solid background, no text, no watermark, no frame
```

### 0.2 视角

| 类型 | 视角 |
|---|---|
| 单位（人物 / 怪物） | **侧面略俯视（3/4 俯视）**，身体**朝右**，能看到正脸的 3/4、头顶一点点 |
| 建筑 / 资源 / 装饰 | **正面斜上方 45° 俯视**，能同时看到正立面和屋顶 |
| 地图 | **正上方略斜的俯视**，和王国保卫战关卡地图一样 |
| UI | 正视，平面 |

### 0.3 技术要求

- **背景**：能出透明背景就出透明 PNG；不能就用**纯品红 `#FF00FF`** 纯色背景（我来抠图）。**不要**白底、不要渐变底、不要场景。
- **不要画地面投影**（阴影我在游戏里统一加）。地图除外。
- **一张图只画一个物体**，主体居中，四周留 8% 空白，不要被裁切。
- 画布：单位 / 建筑 / 资源 **1024×1024**；小物件 **512×512**；地图 **2560×1440**（或 16:9 最大尺寸）。
- 同一类素材（比如 5 个单位）**大小比例要一致**：建议先出一张满意的当“风格参考图”，后面每张都垫这张图（图生图 / 参考图 / 风格锁定）。

### 0.4 配色基调（让整套图像一家人）

| 阵营 | 主色 |
|---|---|
| 我方（人类王国） | 宝蓝 `#3A6FD8` + 米白 + 原木棕，金色点缀 |
| 敌方（Goo 黏液怪） | 毒绿 `#7BC843` + 暗紫 `#4A2E5C`，带尖刺 |
| 自然 | 草绿 `#6FAE4A`、土路暖黄 `#D9B57A` |

---

## 1. 单位（P0，共 10 张）

每个单位 **2 张**：`_idle` 常态站姿 + `_act` 动作姿势（游戏里两张交替 + 程序加弹跳/挤压，就能动起来）。
身高约占画布 **75%**，**朝右**。Q 版：大头（头身比约 1:2.5）、粗手粗脚。

| 文件名 | 内容 | 提示词（接在前缀后面） |
|---|---|---|
| `units/worker_idle.png` | 农民·站立 | `a cheerful medieval peasant worker, big straw hat, brown tunic with rope belt, holding a pickaxe on his shoulder, standing, facing right` |
| `units/worker_act.png` | 农民·挥镐 | `the same peasant worker swinging the pickaxe down mid-strike, dynamic pose, facing right` |
| `units/engineer_idle.png` | 英雄工程师·站立 | `a heroic dwarf-like engineer, shiny yellow hard hat, orange work vest over blue shirt, leather tool belt, big hammer in right hand, confident hero pose, facing right` |
| `units/engineer_act.png` | 工程师·抡锤 | `the same engineer raising the hammer high above his head ready to strike, facing right` |
| `units/swordsman_idle.png` | 剑士·站立 | `a stout human footman, steel helmet with red plume, blue tabard over chainmail, round wooden shield with blue emblem on left arm, short sword in right hand, guard stance, facing right` |
| `units/swordsman_act.png` | 剑士·劈砍 | `the same footman slashing the sword forward, lunging, facing right` |
| `units/archer_idle.png` | 弓手·站立 | `a nimble human archer, green hood, leather jerkin, quiver of arrows on back, longbow held at side, facing right` |
| `units/archer_act.png` | 弓手·拉弓 | `the same archer drawing the bow fully, arrow nocked and aimed to the right` |
| `units/goo_idle.png` | Goo·常态 | `a cute but menacing slime monster, toxic green jelly blob with darker purple core, a few small bone spikes on top, two glowing yellow eyes, slightly squashed, facing right` |
| `units/goo_act.png` | Goo·扑咬 | `the same slime monster stretching and lunging forward with a wide toothy mouth, facing right` |

---

## 2. 建筑（P0，共 7 张）

建筑占画布 **85%**，带一小块石头 / 泥土地基（地基也算建筑的一部分，不要画大片草地）。

| 文件名 | 内容 | 提示词 |
|---|---|---|
| `buildings/base.png` | 基地（城堡） | `a small fairy-tale stone castle keep, two round towers with pointed blue cone roofs, blue banner flags, big wooden arched gate, warm lit windows, stone foundation` |
| `buildings/barracks.png` | 兵营 | `a medieval barracks, timber-frame building with red tiled roof, crossed swords and shield emblem over the door, weapon rack and training dummy beside it` |
| `buildings/warehouse.png` | 仓库 | `a wooden storage warehouse with brown plank roof, big open double doors, stacked crates, barrels and sacks in front` |
| `buildings/smelter.png` | 熔炉 | `a stone smelting furnace building, tall brick chimney, glowing orange molten fire inside the opening, anvil and pile of iron ingots beside it` |
| `buildings/workshop.png` | 木工台 | `an open-air carpenter workshop with green roof on wooden posts, big workbench with saw, stacked planks and logs` |
| `buildings/hive.png` | Goo 巢穴（敌方） | `an evil slime monster hive, dark purple organic mound covered in green goo drips, bone spikes, a glowing red cave mouth in the center, creepy` |
| `buildings/site.png` | 工地 | `a construction site, square dirt foundation with wooden scaffolding frame, ropes, a pile of stones and planks, small toolbox` |

---

## 3. 资源点（P0，共 6 张）

占画布 **70%**。

| 文件名 | 内容 | 提示词 |
|---|---|---|
| `resources/ore_full.png` | 矿堆·满 | `a big gray boulder pile with shiny gold ore crystals sticking out, rich mining node` |
| `resources/ore_half.png` | 矿堆·半 | `the same gold ore boulder pile, half mined, smaller, fewer crystals, some rubble` |
| `resources/ore_low.png` | 矿堆·快空 | `a small leftover pile of rubble with one tiny gold crystal` |
| `resources/tree_1.png` | 树 1 | `a round lush cartoon oak tree, puffy layered green canopy, thick brown trunk` |
| `resources/tree_2.png` | 树 2 | `a tall cartoon pine tree, layered dark green triangular canopy` |
| `resources/tree_3.png` | 树 3 | `a cartoon birch-like tree with light green bushy canopy and pale trunk` |

---

## 4. 地图（P0，1 张）

| 文件名 | 内容 |
|---|---|
| `map/map.png` | 整关地图底图，**2560×1440** |

**一定要拿 `map_layout.png`（随本文档附上）当构图参考图**（图生图 / ControlNet / 参考图），土路走向和空地位置要对上。

提示词：
```
Kingdom Rush style top-down level map, hand-painted, a lush green meadow with varied grass patches,
a winding sandy dirt road from the bottom-left corner to the top-right corner,
dense cartoon forest border along all four edges of the map, small flowers, pebbles and bushes scattered,
open clear grass clearings around the road, no buildings, no characters, no text, bright cheerful lighting
```

注意：
- 地图上**不要画**城堡、巢穴、矿、树（这些是独立素材，游戏里会摆上去）；示意图里圆圈和方框的位置留**空草地**。
- 边缘一圈密林可以画，顶部 128px、底部 240px 会被 UI 部分遮挡。

---

## 5. 道具（P0，共 4 张，512×512）

农民扛在头顶的货，同时当资源图标用。

| 文件名 | 提示词 |
|---|---|
| `items/ore.png` | `a chunk of gray rock with gold ore crystals, game resource icon` |
| `items/wood.png` | `a bundle of three wooden logs tied with rope, game resource icon` |
| `items/ingot.png` | `a stack of two shiny steel ingots, game resource icon` |
| `items/plank.png` | `a neat stack of three wooden planks, game resource icon` |

---

## 6. UI（P0 4 张 + P1 8 张）

UI 要能“九宫格拉伸”：**边框粗细四边一致、四个角有装饰、中间是可平铺的纯材质**，不要在中间画图案。

| 优先级 | 文件名 | 尺寸 | 提示词 |
|---|---|---|---|
| P0 | `ui/panel.png` | 512×512 | `game UI panel frame, dark polished wood plank background, ornate gold metal border with rivets and corner decorations, flat front view, empty center` |
| P0 | `ui/button.png` | 512×256 | `game UI button, rounded rectangle, light wood with gold border, slight bevel, empty, front view` |
| P0 | `ui/button_hover.png` | 512×256 | `same game UI button, brighter glowing gold border, highlighted` |
| P0 | `ui/button_pressed.png` | 512×256 | `same game UI button, darker, pressed in` |
| P1 | `ui/button_disabled.png` | 512×256 | `same game UI button, desaturated gray stone, disabled` |
| P1 | `ui/parchment.png` | 512×512 | `game UI parchment scroll panel, aged cream paper with dark brown ink border, empty center` |
| P1 | `ui/portrait_frame.png` | 512×512 | `round game UI portrait frame, gold ring with blue gem at the bottom, empty transparent center` |
| P1 | `ui/banner.png` | 1024×256 | `game UI ribbon banner, red cloth with gold trim and folded ends, empty, front view` |
| P1 | `ui/icon_worker.png` | 512×512 | `round game icon, head of a peasant with straw hat` |
| P1 | `ui/icon_hero.png` | 512×512 | `round game icon, head of an engineer with yellow hard hat` |
| P1 | `ui/icon_wave.png` | 512×512 | `round game icon, green slime monster face, danger warning` |
| P1 | `ui/icon_victory.png` | 1024×512 | `victory banner emblem, golden laurel wreath with blue shield and crossed swords, no text` |

---

## 7. 特效（P1，共 4 张，512×512）

| 文件名 | 提示词 |
|---|---|
| `fx/arrow.png` | `a single wooden arrow with gray feathers, horizontal, pointing right` |
| `fx/hit.png` | `cartoon impact hit burst, white and yellow star-shaped flash` |
| `fx/dust.png` | `cartoon dust cloud puff, soft beige round smoke` |
| `fx/goo_splat.png` | `cartoon green slime splash splat` |

---

## 8. 装饰（P1 6 张，512×512）

散在地图上加层次（可选，没有就只用地图底图）。

| 文件名 | 提示词 |
|---|---|
| `decor/bush_1.png` | `a round cartoon green bush` |
| `decor/bush_2.png` | `a cartoon green bush with small red berries` |
| `decor/rock_1.png` | `a small cartoon gray rock cluster` |
| `decor/flowers.png` | `a small patch of cartoon yellow and white flowers` |
| `decor/fence.png` | `a short wooden fence segment, horizontal` |
| `decor/stump.png` | `a cartoon tree stump with an axe mark` （树被砍光后留下） |

---

## 9. 锦上添花（P2，共 8 张）

| 文件名 | 内容 / 提示词 |
|---|---|
| `units/worker_carry.png` | `the peasant worker walking, carrying a load above his head with both hands, facing right` |
| `units/swordsman_dead.png` | `the footman lying knocked out on the ground, cartoon dizzy stars` |
| `units/archer_dead.png` | `the archer lying knocked out on the ground, cartoon dizzy stars` |
| `units/goo_dead.png` | `the slime monster melted into a flat green puddle` |
| `buildings/base_damaged.png` | 基地受损版：`the same castle, damaged, cracks, small fire, broken banner` |
| `buildings/hive_damaged.png` | 巢穴受损版：`the same slime hive, damaged, collapsing, leaking goo` |
| `ui/icon_defeat.png` | `defeat emblem, broken shield and snapped sword, no text` |
| `ui/cursor.png` (256×256) | `fantasy game mouse cursor, gold metal gauntlet pointing finger` |

---

## 10. 自查清单（出完图过一遍）

- [ ] 文件名、文件夹和本文完全一致
- [ ] 单位全部**朝右**，大小比例一致（把 5 个单位并排看一眼）
- [ ] 透明背景或纯品红 `#FF00FF` 背景，没有地面投影
- [ ] 同一套描边粗细、同一个光照方向（左上）
- [ ] 地图对齐 `map_layout.png`，空地处没有画东西
- [ ] 图里没有文字和水印

打包成 `art.zip` 发回来即可，抠图、缩放、切九宫格、接进游戏都由我来做。
