# 人物重绘提示词（第二版）

## 上一版为什么"没感觉"

| 问题 | 表现 | 这一版怎么改 |
|---|---|---|
| 比例太"正常" | 约 3 头身，手脚细，缩到 40px 高就成一团 | 2 头身：超大头、超大手和脚、短腿，武器/帽子夸张放大 |
| 脸没性格 | 五个人同一张脸，表情平淡 | 每人一个鲜明性格 + 标志性五官（眉毛、鼻子、胡子） |
| 剪影不好认 | 弓手绿斗篷站在绿草地上直接消失 | 每个兵种一个独特剪影；我方统一宝蓝队伍色 |
| 画风偏通用手游 | 线条粗细一样、明暗只有两层 | 线条有粗细变化、三层赛璐璐明暗 + 顶光高光 + 边缘光 |
| 穿越了 | 工程师戴现代黄色安全帽 | 改成中世纪矮人攻城匠 |
| 姿势僵硬 | 动作帧幅度小 | 动作帧画到幅度最大的那一瞬间 |

## 用法（一定按顺序）

1. **先出"全家福"定风格**（第 1 步提示词）。多抽几次，挑一张最满意的。
2. **之后每张图都把全家福当参考图**垫进去（图生图 / 参考图 / 风格参考），再接对应的单张提示词。这样 14 张才像一家人。
3. 每张图：**透明背景 PNG**；出不了透明就用 **纯品红 `#FF00FF`** 纯色底（脚本会自动抠）。1024×1024，人物全身入画、四周留白、**不画地面阴影**、**朝右**。
4. 文件名照下表起，打包发我；跑 `python3 tools/prepare_art.py 新素材目录 rts-demo` 就换上了。

---

## 第 1 步：风格锁定 · 全家福

```
Character lineup sheet for a 2D fantasy tower-defense / RTS game in the exact style of Kingdom Rush (Ironhide Game Studio).
Five characters standing side by side on a plain white background, all facing right, 3/4 view seen slightly from above, same scale, full body, evenly spaced, not overlapping:
1) a chubby cheerful peasant miner,
2) a stout dwarf siege-engineer hero,
3) a stocky armored footman,
4) a wiry hooded archer,
5) a toxic green slime monster.
Super-deformed chibi proportions: head about 45% of total height, huge hands and boots, short stubby legs, oversized props.
Bold dark-brown outlines with varied line weight (thick outer contour, thinner inner lines), three-tone cel shading with crisp highlights, warm top-left light, subtle rim light, rich saturated colors.
Human kingdom team color: royal blue (#2F63D6) with cream, warm leather brown and small gold trims — every human wears clear blue.
Expressive faces: big noses, bushy eyebrows, strong personalities, readable at very small size; simple big shapes, strong unique silhouettes.
Hand-painted mobile strategy game art, high quality, clean, no text, no ground shadow.
```

## 第 2 步：单张（每条前面加这段前缀，并垫上全家福参考图）

**前缀：**

```
Same art style and same character design as the reference lineup image. Kingdom Rush style 2D game sprite, super-deformed chibi proportions (big head, huge hands and boots, short legs), bold dark-brown varied-weight outlines, three-tone cel shading, warm top-left light, rim light, saturated colors, royal blue team color. Single character, full body, centered, facing right, 3/4 view from slightly above, transparent background, no ground shadow, no text, readable at 48 pixels tall.
```

| 文件名 | 提示词（接在前缀后面） |
|---|---|
| `units/worker_idle.png` | `a chubby cheerful peasant miner with a round red nose and rosy cheeks, wide-brim straw hat, blue sleeveless tunic over a cream shirt, rope belt, pickaxe resting on his shoulder, relaxed happy stance` |
| `units/worker_act.png` | `the same peasant miner at the peak of a big overhead pickaxe swing, body arched back, eyes squeezed with effort, tongue out, hat tilted, exaggerated wind-up pose` |
| `units/worker_carry.png` | `the same peasant miner walking briskly while carrying a heavy brown sack over his shoulder with both hands, back bent, cheeks puffed, one foot lifted mid-step` |
| `units/engineer_idle.png` | `a stout dwarf siege-engineer hero, huge braided ginger beard, brass goggles pushed up on a riveted iron cap with a small blue plume, thick leather apron over a blue shirt, rolled sleeves on big forearms, belt of tools and a scroll of blueprints, a giant two-handed hammer planted head-down beside him, proud confident grin, arms crossed on the hammer handle` |
| `units/engineer_act.png` | `the same dwarf engineer hero raising the giant hammer high above his head with both hands, ready to smash down, beard flying, fierce grin, wide stance, maximum anticipation pose` |
| `units/swordsman_idle.png` | `a stocky human footman with a determined frown and a big square jaw, oversized steel kettle helmet with a red plume, blue tabard with a gold lion emblem over chainmail, a huge round blue-and-steel shield in front, short broadsword ready, solid guard stance` |
| `units/swordsman_act.png` | `the same footman lunging forward with a powerful horizontal sword slash, shield pulled back, front foot stomping, angry shout with open mouth, plume whipping back` |
| `units/swordsman_dead.png` | `the same footman knocked out lying flat on his back, helmet fallen over his eyes, sword and shield dropped beside him, little cartoon stars circling his head, comedic not gory` |
| `units/archer_idle.png` | `a wiry young human archer with a sly confident smirk and a long pointed nose, deep royal-blue hood and short cape, brown leather vest, white feather on the hood, quiver of red-fletched arrows on his back, longbow held low at his side` |
| `units/archer_act.png` | `the same archer drawing the longbow to full tension, arrow nocked and aimed straight to the right, one eye closed, cape fluttering, leaning back` |
| `units/archer_dead.png` | `the same archer knocked out face-down on the ground, hood over his head, broken bow beside him, arrows spilled from the quiver, little cartoon stars, comedic not gory` |
| `units/goo_idle.png` | `a mischievous toxic slime monster, glossy translucent lime-green jelly body with a dark purple core visible inside, three small bone spikes on top, two big glowing yellow eyes with angry eyebrows, wide grin full of tiny sharp teeth, wobbly blob shape, cute but menacing` |
| `units/goo_act.png` | `the same slime monster stretched long and lunging forward to bite, huge gaping toothy mouth, drops of goo flying off, eyes wide and furious` |
| `units/goo_dead.png` | `the same slime monster splattered into a flat green puddle, spikes poking out, eyes as two little X marks, small bubbles` |

**头像（人物换了，头像也要跟着换）：**

| 文件名 | 提示词（接在前缀后面，把 "full body" 换成 "head and shoulders bust portrait"） |
|---|---|
| `ui/icon_worker.png` | `head and shoulders bust portrait of the same peasant miner, big friendly grin, straw hat, facing 3/4 right` |
| `ui/icon_hero.png` | `head and shoulders bust portrait of the same dwarf engineer hero, goggles on cap, huge ginger beard, confident grin, facing 3/4 right` |

**可选（有就更好）：** `units/worker_dead.png`、`units/engineer_dead.png`——照剑士阵亡那条改人物即可（工程师阵亡后会复活，可以画成"晕倒冒星星"）。

## 通用反向提示词（模型支持 negative prompt 就填）

```
realistic, photorealistic, 3D render, anime, thin uniform lines, pastel, washed-out colors, modern clothing, hard hat, safety vest, multiple characters, cropped body, ground shadow, background scenery, text, watermark, blurry, extra limbs, front view, back view
```

## 自查清单（收图时对一下）

- [ ] 缩到 48px 高还能一眼认出是谁（剪影不同、颜色不同）
- [ ] 人类都有显眼的宝蓝色
- [ ] 全部朝右，脚底在画面下方，没有地面阴影
- [ ] `_act` 和 `_idle` 是同一个人（衣服、颜色、道具一致）
- [ ] 透明底，或者纯品红底
