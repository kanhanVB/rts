# 改色提示词：从"灰淡"改成王国保卫战（KR）那种鲜亮配色

用法：**形状、姿势、线条都不动，只改颜色。**每张都用生图工具的**编辑模式**（编辑这张图 / 图生图 / inpaint），垫上**要改的那张原图**，再复制下面对应的提示词。按原文件名保存，打包发我。

## 为什么看着淡（实测数据）

拿起源实机截图和我们现在的游戏截图做了对比：

| | 起源 | 我们现在 |
|---|---|---|
| 草地色相 | **128°～139°**（偏蓝的翠绿、叶子绿） | **80°**（偏黄的橄榄绿 / 军绿） |
| 最鲜艳那 10% 像素的饱和度 | 0.48～**0.98**（宝石、魔法、旗子很艳） | 0.50（没有特别艳的点缀） |
| 暗部 | 很深的墨绿 / 深褐，明暗对比强 | 偏灰，暗部不够深 |

原因很简单：之前所有提示词里都写着 `muted desaturated earthy palette`（低饱和大地色），处理脚本又给地图、矿、树再压了一遍色。这一轮这两处都去掉：**提示词换成鲜亮配色，脚本也不再压色。**

## KR 色板（提示词里的颜色都从这里取）

| 用途 | 亮面 | 中间色 | 暗面 |
|---|---|---|---|
| 草地 | `#8CCB5E` | `#5EA84A` | `#2F7A3A` |
| 森林 / 树冠 | `#6CBF4F` | `#3F8F3E` | `#1F4A2A` |
| 土路 | `#F2DFA8` | `#E0C27E` | `#B08850` |
| 石头 / 城墙（偏冷的蓝灰） | `#D3D9DC` | `#A3ADB3` | `#6A7479` |
| 木头 | `#C98A4B` | `#9A5E2E` | `#5E3518` |
| 我方蓝（屋顶 / 旗 / 衣服） | `#5FA3E8` | `#2E6FC0` | `#1B3F7A` |
| 红（羽饰 / 屋顶 / 横幅） | `#F06A4A` | `#D0352B` | `#8A1E1A` |
| 金（矿石 / 金边 / 星星） | `#FFE27A` | `#F5B935` | `#B9761C` |
| 皮肤 | `#FFD9B0` | `#F0B886` | `#C98656` |
| 史莱姆（敌人） | `#C6F25A` | `#8BCB2C` | `#4C7F18` |
| 描边 | `#2B1D14`（深褐，不要纯黑，也不要灰） | | |

要点：**每种颜色都是三档**：亮面、中间色、暗面。亮面要亮，暗面要深；影子往冷色（蓝绿）偏，亮面往暖色（黄）偏。

## 通用改色前缀（每张都先贴这段，后面接该文件的颜色说明）

```
Recolor the attached image in the vibrant color style of Kingdom Rush Origins (Ironhide Game Studio). Keep EXACTLY the same shapes, pose, proportions, line art, outline thickness, size and position on the canvas — only change the colors. Use bright saturated cartoon colors with clear cel shading in three tones: a bright warm highlight, a rich mid tone and a deep cool shadow. Strong contrast between light and shadow. Outlines dark brown #2B1D14. Keep the solid flat magenta #FF00FF background. Colors:
```

**反向提示词**（工具支持就填）：

```
muted, desaturated, grey, dull, washed out, pastel, olive, sepia, brown tint, low contrast, flat single tone, gradient background, changed pose, changed shape, extra objects, ground shadow, text, watermark
```

## 第 0 步：先改角色全家福（强烈推荐）

先把角色全家福改色，满意了以后，后面每张图都**同时附原图和这张新全家福**，再加一句 `match the colors of the attached recolored character lineup`，这样每张颜色都统一。

```
（通用改色前缀）
miner: royal blue shirt #2E6FC0, brown leather apron and boots #9A5E2E, warm peach skin #F0B886, grey-steel pickaxe head; dwarf engineer: bright orange-ginger beard #E07B2A, blue cap #2E6FC0, brown leather; red-plume knight: shiny cool steel armor #A3ADB3 with white highlights, bright red plume #D0352B, royal blue tabard #2E6FC0; green-hood archer: leaf green hood and cloak #3F8F3E with bright #6CBF4F highlights, tan leather, light wood bow; slime: bright lime green #8BCB2C with glossy light #C6F25A highlights and deep green #4C7F18 shadows; other characters: same bright saturated palette, each with one strong signature color.
```

## 单位（15 张）

同一个角色的几张图（idle / act / dead / carry）**颜色说明完全一样**，复制同一段就行。

| 文件 | 颜色说明（接在通用前缀后面） |
|---|---|
| `units/worker_idle.png` `worker_act.png` `worker_carry.png` | `a miner: royal blue shirt #2E6FC0, brown leather apron, belt and boots #9A5E2E, warm peach skin #F0B886, light wood handle and grey-steel pickaxe head with a white glint; carried ore sack: tan cloth with bright gold ore #F5B935 peeking out` |
| `units/engineer_idle.png` `engineer_act.png` `engineer_dead.png` | `a dwarf engineer: bright orange-ginger beard #E07B2A with yellow highlights, royal blue cap and shirt #2E6FC0, brown leather apron #9A5E2E, warm peach skin, steel hammer head with a white glint` |
| `units/swordsman_idle.png` `swordsman_act.png` `swordsman_dead.png` | `a knight: shiny cool steel helmet and armor #A3ADB3 with white highlights and blue-grey shadows, bright red plume #D0352B, royal blue tabard #2E6FC0 with a gold trim #F5B935, brown leather boots, steel sword and a blue round shield with gold rim` |
| `units/archer_idle.png` `archer_act.png` `archer_dead.png` | `an archer: leaf green hood and cloak #3F8F3E with bright #6CBF4F highlights and deep #1F4A2A shadows, tan leather vest and boots #C98A4B, light wood bow, white-feathered arrows` |
| `units/goo_idle.png` `goo_act.png` `goo_dead.png` | `a slime monster: bright lime green #8BCB2C body, glossy light #C6F25A highlights and a white shine spot, deep green #4C7F18 shadows, dark green #2A4A10 inside the mouth; splashes the same lime green` |

## 建筑（9 张）

| 文件 | 颜色说明 |
|---|---|
| `buildings/base.png` `base_damaged.png` | `castle: light cool blue-grey stone walls #A3ADB3 with bright #D3D9DC top faces and #6A7479 shadows, royal blue cone roofs #2E6FC0 with light blue highlights, bright blue flags, warm brown wooden gate #9A5E2E with iron bands; damaged version keeps the same colors, plus dark soot marks and small orange embers` |
| `buildings/barracks.png` | `barracks: blue-grey stone base #A3ADB3, warm brown timber #9A5E2E, bright red roof tiles #D0352B with orange-red highlights, blue banner #2E6FC0, shiny steel weapons, yellow straw dummy` |
| `buildings/warehouse.png` | `warehouse barn: warm orange-brown wood planks #C98A4B / #9A5E2E, red roof #D0352B, tan crates, barrels with steel rings, gold ore and logs visible` |
| `buildings/smelter.png` | `forge: blue-grey stone #A3ADB3, red brick chimney #B8482F, glowing bright orange-yellow furnace mouth #FFB02E with a yellow core, light grey smoke, brown wood` |
| `buildings/workshop.png` | `carpenter's shed: warm light wood #C98A4B, brown roof shingles, fresh pale yellow planks #F2DFA8, steel saw` |
| `buildings/site.png` | `construction site: fresh light yellow-brown scaffolding wood #E0C27E, blue-grey stone blocks, a small blue flag` |
| `buildings/hive.png` `hive_damaged.png` | `slime nest: purple-brown mound #6B4A6E with dark #3A2440 cave mouth, bright lime slime #8BCB2C dripping out and glowing faintly; damaged version same colors, cracked, slime splattered` |

## 资源 / 装饰 / 物品 / 特效（20 张）

| 文件 | 颜色说明 |
|---|---|
| `resources/ore_full.png` `ore_half.png` `ore_low.png` | `boulder: cool blue-grey stone #A3ADB3 with bright top faces #D3D9DC and #6A7479 shadows; ore crystals bright gold #F5B935 with pale yellow #FFE27A facets, orange #B9761C shadows and a small white sparkle` |
| `resources/tree_1.png` `tree_2.png` `tree_3.png` | `tree: lush leaf green canopy #3F8F3E with bright yellow-green #8CCB5E highlights on top and deep #1F4A2A shadows underneath, warm brown trunk #9A5E2E (birch: white trunk with dark marks)` |
| `decor/bush_1.png` `bush_2.png` | `bush: bright leaf green #5EA84A with #8CCB5E highlights and #2F7A3A shadows, a few small red or white berries` |
| `decor/flowers.png` | `flowers: pure white and bright yellow petals, a few pink #F07AA0 ones, leaf green stems` |
| `decor/rock_1.png` | `rock: cool blue-grey #A3ADB3 with bright top #D3D9DC, small green moss patches` |
| `decor/fence.png` `decor/stump.png` | `wood: warm brown #9A5E2E with light #C98A4B highlights, pale yellow cut ring on the stump, a bit of green moss` |
| `items/ore.png` | `gold ore chunk #F5B935 with pale yellow facets and a white sparkle` |
| `items/wood.png` | `log: warm brown bark #9A5E2E, pale yellow cut end #F2DFA8 with rings` |
| `items/ingot.png` | `shiny steel ingot: light blue-grey #D3D9DC top, #A3ADB3 sides, white glint` |
| `items/plank.png` | `light wood planks #E0C27E with brown grain lines` |
| `fx/arrow.png` | `light wood shaft, steel tip, white feathers` |
| `fx/hit.png` | `impact star: white center, bright yellow #FFE27A, orange #F5B935 edge` |
| `fx/dust.png` | `dust puff: warm light tan #F2DFA8 with soft beige shadow` |
| `fx/goo_splat.png` | `slime splash: bright lime #8BCB2C with light #C6F25A highlights` |

## UI（14 张）

KR 的 UI 是**暖木色 + 金边 + 深褐底**，颜色比画面略收，但金色和木色要亮。

| 文件 | 颜色说明 |
|---|---|
| `ui/panel.png` | `panel: warm medium brown wood frame #9A5E2E with light #C98A4B highlights, bright gold corner studs #F5B935, inner area deep warm brown #3E2A1C` |
| `ui/parchment.png` | `parchment: warm light cream #F2DFA8 with slightly darker tan edges #D9B77A, soft burnt edges` |
| `ui/banner.png` | `ribbon banner: rich red #D0352B with bright #F06A4A highlights and deep #8A1E1A folds, gold trim #F5B935` |
| `ui/button.png` | `button: warm brown wood #9A5E2E with light top highlight #C98A4B, gold rim #F5B935` |
| `ui/button_hover.png` | `same as button but brighter: wood #B87840, glowing yellow rim #FFE27A` |
| `ui/button_pressed.png` | `same as button but darker: wood #6E4020, rim #B9761C` |
| `ui/button_disabled.png` | `same as button but grey-brown and dull (this one SHOULD stay desaturated)` |
| `ui/portrait_frame.png` | `round frame: bright gold ring #F5B935 with pale yellow highlights and orange shadows, dark brown inner rim` |
| `ui/icon_worker.png` `icon_hero.png` | `same colors as the matching character in the recolored lineup, on a gold coin #F5B935` |
| `ui/icon_wave.png` | `slime face icon: bright lime #8BCB2C on a deep red #8A1E1A disc with a gold rim` |
| `ui/icon_victory.png` | `gold crown / trophy #F5B935 with white shine, a blue ribbon #2E6FC0` |
| `ui/icon_defeat.png` | `broken grey sword and a torn red flag #D0352B on a dark disc` |
| `ui/cursor.png` | `gold gauntlet / pointer #F5B935 with dark brown outline` |

## 地图 `map/map.png`（重画，不是改色）

地图要整张重画，**垫 `map_layout.png` 当构图参考**，土路和空地的位置要对上。尺寸 **2560×1440**（至少 1672×941）。

```
Kingdom Rush Origins style top-down level map, hand-painted vector cartoon, vibrant saturated colors. A lush emerald green meadow (#5EA84A with bright #8CCB5E sunny patches and deep #2F7A3A shade), a winding warm sandy dirt road (#E0C27E with light #F2DFA8 center and #B08850 edges) following exactly the attached layout, dense rich green cartoon forest border along all four edges (#3F8F3E canopies with bright tops and very dark #1F4A2A gaps between trees), small white and yellow flowers, a few blue-grey pebbles, a small bright turquoise stream or pond if there is room. Strong cel shading, dark brown outlines on trees and rocks, clear open grass areas where the layout shows empty space. No buildings, no characters, no text, no UI.
```

## 改完自查

- [ ] 草地是**翠绿 / 叶子绿**，不是橄榄绿或军绿
- [ ] 每张都有明显的亮面和深色暗面，不是一层平涂
- [ ] 金色（矿、金边）够亮，有白色高光点
- [ ] 形状、姿势、大小和原图一样（编辑模式没把图重画了）
- [ ] 背景还是纯品红 `#FF00FF`
- [ ] 文件名和原来一样，打包发我就行。我这边会去掉压色处理，按原色导入
