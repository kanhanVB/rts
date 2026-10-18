# 2D 角色提示词（以剑兵初版为准）

剑兵初版 = `units/swordsman_idle.png`，已经定了画风，后面所有图都**垫这张图**出。

## 用法

- **同一个角色换动作**（攻击 / 倒地 / 搬运）：用工具的**编辑模式**（"编辑这张图" / inpaint / 图生图），垫这个角色的 idle 图，用下面的"动作前缀"。这样脸、颜色、比例不会变。
- **新角色**：垫剑兵初版，用"新角色前缀"，先出 idle，满意了再用它出这个角色的其他动作。
- 每张：一个角色、全身、居中、朝右（和初版一样），**纯品红 `#FF00FF` 底最好**（白底也行，但被线条围住的小块白底抠不干净）。不要地面影子、不要文字。
- 同一角色的几张图，**大小和位置尽量一致**（画布一样大、脚底在同一高度）。

## 前缀

**动作前缀**（垫该角色的 idle 图）：

```
Edit the attached character: keep exactly the same character, design, colors, outline thickness, proportions, size and art style. Only change the pose to:
```

**新角色前缀**（垫剑兵初版）：

```
A new character in exactly the same art style as the attached footman: same thick dark grey-brown outline, flat colors with one darker shade tone, muted desaturated earthy palette, same stubby proportions with oversized headgear about 45% of total height, short thick legs, big hands, the face is a plain featureless ochre shape with no eyes, nose or mouth, 3/4 front view facing right, full body, same size on the canvas, solid flat magenta #FF00FF background, no ground shadow, no text. The character is:
```

**反向提示词**（工具支持就填）：

```
eyes, eyebrows, mouth, facial expression, detailed face, glossy, gradient, realistic, painterly, 3D render, thin lines, bright saturated colors, neon, background scenery, ground shadow, text, watermark, multiple characters, cropped
```

## 单张

| 文件名 | 前缀 | 接在后面 |
|---|---|---|
| `units/swordsman_idle.png` | — | **就是初版，已有** |
| `units/swordsman_act.png` | 动作 | `stepping forward and slashing the sword down across the body, shield held in front` |
| `units/swordsman_dead.png` | 动作 | `fallen flat on his back on the ground, helmet tilted, sword and shield dropped beside him` |
| `units/archer_idle.png` | 新角色 | `a hooded archer: muted green hood and short cape covering most of the head, featureless ochre face in the hood opening, brown leather jerkin and bracers, quiver on the back, short wooden recurve bow held low` |
| `units/archer_act.png` | 动作 | `drawing the bow fully and aiming an arrow to the right` |
| `units/archer_dead.png` | 动作 | `fallen on the ground, bow dropped beside him` |
| `units/worker_idle.png` | 新角色 | `a peasant miner: wide floppy brown felt hat covering most of the head, featureless ochre face under the brim, beige rough tunic with a small muted blue sash, brown boots, a pickaxe resting on his shoulder` |
| `units/worker_act.png` | 动作 | `swinging the pickaxe down hard at the ground in front of him, leaning forward` |
| `units/worker_carry.png` | 动作 | `walking hunched over, carrying a heavy brown sack on his back with both hands, no pickaxe in hand` |
| `units/engineer_idle.png` | 新角色 | `a dwarf engineer hero, slightly more detailed: round riveted iron helmet with brass goggles, huge bushy muted orange beard covering the lower face, featureless ochre face between helmet and beard, leather apron over muted blue sleeves, tool belt, a big two-handed war hammer held across the body` |
| `units/engineer_act.png` | 动作 | `raising the war hammer high over his head with both hands, about to smash down` |
| `units/engineer_dead.png` | 动作 | `knocked out, slumped sitting on the ground, helmet tilted over the face, hammer dropped` |
| `units/goo_idle.png` | 新角色 | `an enemy monster (monsters may have faces): a squat toxic slime blob, murky olive green jelly with a darker green shade, a few bone spikes on its back, two narrow mean yellow eyes and a jagged mouth, leaning to the right` |
| `units/goo_act.png` | 动作 | `lunging forward to the right with its mouth wide open to bite, body stretched` |
| `units/goo_dead.png` | 动作 | `melted into a flat green puddle with the bone spikes sticking out` |

## UI（可选，同一画风）

UI 部件的文件名和描述照 `KR_PROMPTS.md` 的 B2 表，前缀换成：

```
A game UI element in exactly the same art style as the attached footman: same thick dark grey-brown outline, flat colors with one darker shade tone, muted desaturated earthy palette (warm grey steel, taupe wood, dull red, ochre), chunky simple shapes, flat front view, single element, centered, solid flat magenta #FF00FF background, no text, no numbers, no letters. The element is:
```
