# 建筑提示词（照全家福画风重画）

用法：每次**附两张图**——① 我给的旧建筑图（`buildings_refs.zip` 里同名文件，用来定造型和角度）② 角色全家福（定画风）。复制一段发给生图 AI，一段出一张，按标题的文件名保存，打包发我。

- 画风跑偏（太亮、太细、有渐变）：补一句 `keep the same flat muted style as the character lineup`
- 角度变成正面平视了：补一句 `seen from above at about 45 degrees, like the first image`
- 一张一个建筑，不要地面、草地和影子

## 主城（基地，带箭塔会射箭）

### `buildings/base.png`

```
Redraw the building in the FIRST attached image in exactly the art style of the SECOND attached image (the character lineup): thick dark grey-brown outline, flat colors with one darker shade tone, muted desaturated earthy palette, chunky simple shapes, slightly cartoonish proportions. Keep the same building type, rough layout and camera angle (3/4 view from above, about 45 degrees). It is the player's main castle keep: grey stone walls with two round towers, muted slate-blue conical roofs with small blue flags, a wooden gate, a small blue shield emblem above the gate, an archer platform on top. Single building, centered, solid flat magenta #FF00FF background, no ground, no grass, no shadow, no text.
```

## 主城·受损（血量低时显示）

### `buildings/base_damaged.png`

```
Redraw the building in the FIRST attached image in exactly the art style of the SECOND attached image (the character lineup): thick dark grey-brown outline, flat colors with one darker shade tone, muted desaturated earthy palette, chunky simple shapes, slightly cartoonish proportions. Keep the same building type, rough layout and camera angle (3/4 view from above, about 45 degrees). It is the same castle, heavily damaged: cracked and broken stones, a collapsed roof section, torn flags, scorch marks, a few loose stones. Single building, centered, solid flat magenta #FF00FF background, no ground, no grass, no shadow, no text.
```

## 兵营（训练剑兵、弓箭手）

### `buildings/barracks.png`

```
Redraw the building in the FIRST attached image in exactly the art style of the SECOND attached image (the character lineup): thick dark grey-brown outline, flat colors with one darker shade tone, muted desaturated earthy palette, chunky simple shapes, slightly cartoonish proportions. Keep the same building type, rough layout and camera angle (3/4 view from above, about 45 degrees). It is a soldiers' barracks: a sturdy stone and timber hall with a muted brown tiled roof, a training dummy and a weapon rack with swords and spears beside the door, a small blue banner. Single building, centered, solid flat magenta #FF00FF background, no ground, no grass, no shadow, no text.
```

## 仓库（资源交货点）

### `buildings/warehouse.png`

```
Redraw the building in the FIRST attached image in exactly the art style of the SECOND attached image (the character lineup): thick dark grey-brown outline, flat colors with one darker shade tone, muted desaturated earthy palette, chunky simple shapes, slightly cartoonish proportions. Keep the same building type, rough layout and camera angle (3/4 view from above, about 45 degrees). It is a storage warehouse: a wide wooden barn with a muted brown roof, big open double doors, crates, barrels and sacks stacked outside. Single building, centered, solid flat magenta #FF00FF background, no ground, no grass, no shadow, no text.
```

## 冶炼厂（矿石炼成铁锭）

### `buildings/smelter.png`

```
Redraw the building in the FIRST attached image in exactly the art style of the SECOND attached image (the character lineup): thick dark grey-brown outline, flat colors with one darker shade tone, muted desaturated earthy palette, chunky simple shapes, slightly cartoonish proportions. Keep the same building type, rough layout and camera angle (3/4 view from above, about 45 degrees). It is an ore smelter: a stone forge building with a big brick chimney with a little grey smoke, a glowing orange furnace opening, an anvil and a few iron ingots outside. Single building, centered, solid flat magenta #FF00FF background, no ground, no grass, no shadow, no text.
```

## 木工坊（木材加工成木板）

### `buildings/workshop.png`

```
Redraw the building in the FIRST attached image in exactly the art style of the SECOND attached image (the character lineup): thick dark grey-brown outline, flat colors with one darker shade tone, muted desaturated earthy palette, chunky simple shapes, slightly cartoonish proportions. Keep the same building type, rough layout and camera angle (3/4 view from above, about 45 degrees). It is a carpenter's workshop / sawmill: a timber shed with an open front, a big saw bench with a log on it, stacks of planks and a pile of sawdust. Single building, centered, solid flat magenta #FF00FF background, no ground, no grass, no shadow, no text.
```

## 工地（建造中的工地）

### `buildings/site.png`

```
Redraw the building in the FIRST attached image in exactly the art style of the SECOND attached image (the character lineup): thick dark grey-brown outline, flat colors with one darker shade tone, muted desaturated earthy palette, chunky simple shapes, slightly cartoonish proportions. Keep the same building type, rough layout and camera angle (3/4 view from above, about 45 degrees). It is a construction site: a square stone foundation with wooden scaffolding and beams, a few stones and planks lying around, a small toolbox. Single building, centered, solid flat magenta #FF00FF background, no ground, no grass, no shadow, no text.
```

## 巢穴（敌人刷怪点）

### `buildings/hive.png`

```
Redraw the building in the FIRST attached image in exactly the art style of the SECOND attached image (the character lineup): thick dark grey-brown outline, flat colors with one darker shade tone, muted desaturated earthy palette, chunky simple shapes, slightly cartoonish proportions. Keep the same building type, rough layout and camera angle (3/4 view from above, about 45 degrees). It is the enemy slime monster nest: a lumpy mound of murky green slime and dark purple flesh with a dark cave mouth, bone spikes sticking out, some slime dripping over grey rocks at the base. Single building, centered, solid flat magenta #FF00FF background, no ground, no grass, no shadow, no text.
```

## 巢穴·受损（血量低时显示）

### `buildings/hive_damaged.png`

```
Redraw the building in the FIRST attached image in exactly the art style of the SECOND attached image (the character lineup): thick dark grey-brown outline, flat colors with one darker shade tone, muted desaturated earthy palette, chunky simple shapes, slightly cartoonish proportions. Keep the same building type, rough layout and camera angle (3/4 view from above, about 45 degrees). It is the same slime nest, heavily damaged: deflated and cracked, broken bone spikes, splattered slime, the cave mouth partly collapsed. Single building, centered, solid flat magenta #FF00FF background, no ground, no grass, no shadow, no text.
```

## 可选：矿石和树（同样附旧图 + 全家福）

### `resources/ore_full.png`（矿·满）

```
Redraw the object in the FIRST attached image in exactly the art style of the SECOND attached image (the character lineup): thick dark grey-brown outline, flat colors with one darker shade tone, muted desaturated earthy palette, chunky simple shapes. Same camera angle (3/4 view from above). It is a large grey rock with many muted amber ore crystals. Single object, centered, solid flat magenta #FF00FF background, no ground, no shadow, no text.
```

### `resources/ore_half.png`（矿·半）

```
Redraw the object in the FIRST attached image in exactly the art style of the SECOND attached image (the character lineup): thick dark grey-brown outline, flat colors with one darker shade tone, muted desaturated earthy palette, chunky simple shapes. Same camera angle (3/4 view from above). It is the same rock, about half of the ore crystals mined away. Single object, centered, solid flat magenta #FF00FF background, no ground, no shadow, no text.
```

### `resources/ore_low.png`（矿·少）

```
Redraw the object in the FIRST attached image in exactly the art style of the SECOND attached image (the character lineup): thick dark grey-brown outline, flat colors with one darker shade tone, muted desaturated earthy palette, chunky simple shapes. Same camera angle (3/4 view from above). It is the same rock, almost all ore crystals mined away, only one small crystal left. Single object, centered, solid flat magenta #FF00FF background, no ground, no shadow, no text.
```

### `resources/tree_1.png`（树 1）

```
Redraw the object in the FIRST attached image in exactly the art style of the SECOND attached image (the character lineup): thick dark grey-brown outline, flat colors with one darker shade tone, muted desaturated earthy palette, chunky simple shapes. Same camera angle (3/4 view from above). It is a round leafy oak tree. Single object, centered, solid flat magenta #FF00FF background, no ground, no shadow, no text.
```

### `resources/tree_2.png`（树 2）

```
Redraw the object in the FIRST attached image in exactly the art style of the SECOND attached image (the character lineup): thick dark grey-brown outline, flat colors with one darker shade tone, muted desaturated earthy palette, chunky simple shapes. Same camera angle (3/4 view from above). It is a tall pine tree. Single object, centered, solid flat magenta #FF00FF background, no ground, no shadow, no text.
```

### `resources/tree_3.png`（树 3）

```
Redraw the object in the FIRST attached image in exactly the art style of the SECOND attached image (the character lineup): thick dark grey-brown outline, flat colors with one darker shade tone, muted desaturated earthy palette, chunky simple shapes. Same camera angle (3/4 view from above). It is a birch tree with a white trunk. Single object, centered, solid flat magenta #FF00FF background, no ground, no shadow, no text.
```
