# 王国保卫战风格提示词（第四版：对照真图重写）

## 为什么上一版出图"不像"

拿王国保卫战原图（wiki 上的小兵、哥布林、游侠、关卡图、敌人图鉴卡）和你出的全家福逐项对比：

| | 王国保卫战真图 | 你这次的出图 | 原因（上一版提示词的锅） |
|---|---|---|---|
| 线条 | 深褐/黑色**粗细变化**的墨线：外轮廓粗、内部细，转角有尖 | 一圈均匀粗描边，像贴纸 | 写了 "thick outline" + "transparent background" → 模型理解成贴纸/图标 |
| 明暗 | **2–3 层硬边赛璐璐阴影**，左上来光，金属有一小块亮高光 | 几乎平涂，没体积 | 写了 "flat color fills" |
| 视角 | **高机位往下看**（约 50°），能看到头盔顶、肩膀，脚缩短 | 正面平视 | "3/4 view" 太弱，模型默认平视立绘 |
| 脸 | 小兵**基本没五官**：头盔/兜帽/胡子盖住，最多两条小眯缝眼 | 大脸 + 皱眉表情，像 emoji | 写了 "dot eyes + heavy brow + grumpy" → 直接画成生气 emoji |
| 配色 | **每个兵自己的固有色**：钢灰盔甲、棕皮革、绿兜帽、肉色皮肤；阵营色只是小块布 | 全身同一种饱和蓝 | 写了 "blue team color on every human" |
| 形体 | 敦实：头约占 1/3，宽肩短腿、武器夸张；剪影一眼认得出 | 圆滚滚吉祥物 | "chibi" 一词会触发萌系吉祥物 |
| 史莱姆 | 敌人是有凶相的怪物（哥布林：尖耳、眯眼、獠牙、斜着身子） | emoji 果冻 | 同上 |
| UI | 浅米色/黄褐色**木框** + 深棕皮革底板，圆润厚实、带倒角；属性是深棕圆角小槽 + 小图标；标题是橙黄手写体 | — | 上一版猜成"深色铁皮铆钉"，偏了 |

**最关键的一条：纯文字基本出不来王国保卫战画风，必须垫参考图。**

## 用法（一定要垫图）

1. **准备参考图**：截一张王国保卫战游戏画面（带小兵、带 UI 的那种），或者用我给你的参考拼图 `kr_reference.png`。只用来定画风，**不要把原图素材放进游戏**。
2. **按工具垫图**：
   - ChatGPT / GPT-image：上传参考图，提示词开头加：`Match the art style of the attached image exactly (line work, shading, colors, camera angle), but draw a NEW original character:`
   - Midjourney：`--sref <参考图链接> --sw 400 --style raw`（全家福定稿后，后面单张改 `--sref <全家福链接>`）
   - Stable Diffusion：IP-Adapter（style 模式，权重 0.6–0.8）+ 下面的提示词
3. **先出全家福 A1**，挑最像的一张；后面每张单图都**同时垫原参考图 + 这张全家福**。
4. 单图用**纯品红 `#FF00FF` 底**（比"透明底"好：透明底会把画风带成贴纸），脚本会自动抠。不画地面投影，不要文字。
5. 出图后先缩到 64px 看一眼：还认得出是谁、像王国保卫战的小兵，才算过关。
6. 文件名照抄，打包发我。

---

## A. 人物

### A0 人物通用前缀（每条都加）

```
2D tower-defense game unit sprite in the art style of Kingdom Rush (Ironhide Game Studio): hand-drawn vector cartoon, cel shading with 2-3 hard-edged tones per color, warm light from the top left, one small crisp highlight on metal parts, dark brown ink outline with varying line weight (heavier on the outer silhouette, thin lines inside, tapered sharp corners).
High camera looking down at about 50 degrees: we see the top of the head or helmet and the shoulders, legs foreshortened, character facing right.
Stocky squat proportions: head or helmet about one third of total height, broad shoulders, short legs, big hands, oversized weapon, strong readable silhouette, dynamic but compact pose.
Tiny simple face mostly hidden by helmet, hood, hat or beard: at most two small dark narrow eye slits, no mouth, no eyebrows, no facial expression.
Natural local colors per material (steel grey, leather brown, wood, skin, cloth), medium saturation; the player's blue appears only as a small cloth accent.
Single character, full body, centered, on a solid flat magenta #FF00FF background, no shadow, no text.
```

### A1 全家福（先出这张定风格）

```
Five original tiny units standing in a row on a sunlit grassy dirt road of a tower-defense level, art style of Kingdom Rush (Ironhide Game Studio), seen from a high camera about 50 degrees above, same scale, all facing right:
a peasant miner with a pickaxe, a dwarf engineer hero with a big war hammer, a footman soldier with sword and round shield, a hooded archer with a short bow, a toxic slime monster enemy.
Hand-drawn vector cartoon, 2-3 tone hard cel shading, warm top-left light, dark brown ink outlines with varying weight, stocky squat proportions with big helmets and hats, faces mostly hidden with tiny eye slits only, each unit has its own natural colors (grey steel, brown leather, green hood, beige cloth), small blue cloth accents only. No text.
```

> 全家福画在草地路上是故意的：带场景时模型更容易画对"俯视 + 游戏内小兵"的感觉。定稿后单张再换品红底。

### A2 单张（接在 A0 前缀后面）

| 文件名 | 提示词 |
|---|---|
| `units/worker_idle.png` | `a peasant miner: wide floppy brown felt hat hiding the eyes, big round nose, beige rough tunic with a small blue sash, brown boots, pickaxe resting on his shoulder, standing` |
| `units/worker_act.png` | `the same peasant miner swinging the pickaxe down hard at the ground in front of him, body leaning forward, mid-strike` |
| `units/worker_carry.png` | `the same peasant miner walking hunched over, a heavy brown sack on his back held with both hands` |
| `units/engineer_idle.png` | `a dwarf engineer hero, a bit more detailed than common soldiers: round riveted iron helmet with brass goggles on the brow, huge bushy orange beard covering the face, leather apron over rolled blue sleeves, tool belt with wrenches, a big two-handed war hammer held across his body, wide sturdy stance` |
| `units/engineer_act.png` | `the same dwarf engineer hero raising the war hammer high over his head with both hands, about to smash down` |
| `units/engineer_dead.png` | `the same dwarf engineer hero knocked out, slumped sitting on the ground, helmet tilted over his eyes, hammer dropped` |
| `units/swordsman_idle.png` | `a footman soldier: big round steel kettle helmet shading the face, grey chainmail and steel shoulder plates, short blue tabard, small round wooden shield with an iron rim, short broad sword, guard stance` |
| `units/swordsman_act.png` | `the same footman lunging forward and slashing the sword across, shield held in front` |
| `units/swordsman_dead.png` | `the same footman fallen flat on the ground, sword and shield dropped beside him` |
| `units/archer_idle.png` | `a hooded archer: deep forest green hood and cape hiding the face in shadow, brown leather bracers and boots, small blue scarf, quiver on the back, short recurve bow held low` |
| `units/archer_act.png` | `the same archer drawing the bow fully and aiming an arrow to the right, cape flaring` |
| `units/archer_dead.png` | `the same archer fallen on the ground, bow dropped beside him` |
| `units/goo_idle.png` | `an original monster enemy: a squat toxic slime creature, murky olive-green jelly with darker green cel shading and a few bubbles, bone spikes and a broken arrow stuck in its back, two narrow mean yellow eyes, a wide jagged mouth with small fangs, leaning forward aggressively` |
| `units/goo_act.png` | `the same slime creature lunging forward, mouth wide open to bite, body stretched` |
| `units/goo_dead.png` | `the same slime creature melted into a flat green puddle, bone spikes and arrow sticking out` |

### A3 人物反向提示词

```
sticker, die-cut, white border, emoji, icon, mascot, kawaii, chibi anime, uniform thick outline, flat colors without shading, front eye-level view, big face, big round eyes, eyebrows, frowning face, angry expression, smiling mouth, all one color, monochrome blue, Clash of Clans style, Pixar, 3D render, glossy plastic, realistic, painterly, pixel art, multiple characters, cropped body, ground shadow, text, watermark
```

---

## B. UI

### B0 UI 通用前缀（每条都加，并垫参考图 / B1 定稿图）

```
Game UI element in the art style of Kingdom Rush (Ironhide Game Studio): hand-drawn vector cartoon, chunky rounded shapes, warm light tan and cream carved wood frame with soft bevel, dark brown leather or dark wood inner panel, small dark iron corner caps, 2-tone hard cel shading with warm top-left light, dark brown ink outline with varying weight, warm earthy palette with orange-yellow accents, flat front view, single element, centered, on a solid flat magenta #FF00FF background, no text, no numbers, no letters.
```

### B1 UI 套件总览（先出这张定风格）

```
Original tower-defense game UI kit sheet in the art style of Kingdom Rush (Ironhide Game Studio), on a plain magenta background: small resource plaques with light tan wood frames and dark brown insets, round buttons with chunky tan wood and dark iron rims, a round hero portrait frame, a skull wave-call button shaped like a map pin, a dark brown info panel with a cream wood frame and small dark rounded stat slots, small stat icons (heart, sword, shield, boot, bow), gold stars. Hand-drawn vector cartoon, 2-tone hard cel shading, dark brown ink outlines with varying weight, warm earthy colors. No text, no numbers.
```

### B2 单张（接在 B0 前缀后面）

| 文件名 | 用途 | 提示词 |
|---|---|---|
| `ui/hud_plaque.png` | 左上角资源/人口小牌子 | `a small horizontal plaque: dark brown leather inset inside a light tan rounded wood frame, small iron end caps, empty, about 4:1 width to height` |
| `ui/info_bar.png` | 底部选中信息条 | `a long thin horizontal bar: dark brown leather inset inside a cream wood frame with rounded ends, empty, about 7:1 width to height` |
| `ui/panel.png` | 帮助 / 产能面板 | `a square dark brown wooden board with a thick light tan carved wood frame and small iron corner caps, empty` |
| `ui/tooltip.png` | 提示框 / 顶部提示条 | `a small rounded rectangle of aged cream parchment with a dark brown outline and slightly worn edges, empty` |
| `ui/ring_button.png` | 环形菜单 / 小按钮 | `an empty round button: chunky light tan wood ring with a thin dark iron rim and small rivets, dark brown recessed inner circle for an icon` |
| `ui/ring_button_hover.png` | 同上·悬停 | `the same round button, brighter with a warm golden glow on the ring` |
| `ui/ring_button_pressed.png` | 同上·按下 | `the same round button pressed in, slightly darker and smaller highlight` |
| `ui/ring_button_disabled.png` | 同上·禁用 | `the same round button, desaturated grey, dull` |
| `ui/price_tag.png` | 环形按钮下方价格牌 | `a tiny rounded dark brown tag with a thin tan wood border, empty` |
| `ui/build_ring.png` | 环形菜单底圈（画在地上） | `a thin ornamental circle ring seen from 50 degrees above, light tan wood with small dark studs, empty center, like a radial menu base` |
| `ui/portrait_ring.png` | 左下角英雄圆头像框 | `a round hero portrait frame: thick light tan wood ring with dark iron rim and rivets, small round badge slot on the lower left, empty dark center` |
| `ui/wave_call.png` | 路口"敌人来袭/提前叫波"按钮 | `a round warning button shaped like a map pin: a horned skull on dark red inside a tan wood and iron ring, small pointed tip at the bottom` |
| `ui/icon_wave.png` | 波次计数图标 | `a small skull icon` |
| `ui/icon_ore.png` | 资源·矿 | `an icon of a chunk of grey rock with orange ore crystals` |
| `ui/icon_wood.png` | 资源·木 | `an icon of two cut wooden logs` |
| `ui/icon_ingot.png` | 资源·铁锭 | `an icon of two stacked iron ingots` |
| `ui/icon_plank.png` | 资源·木板 | `an icon of a small stack of wooden planks` |
| `ui/icon_worker.png` | 人口 / 农民头像 | `an icon of the peasant miner's head with a wide floppy brown hat hiding the eyes and a big nose` |
| `ui/icon_hero.png` | 英雄头像 | `an icon of the dwarf engineer hero's head with iron helmet, brass goggles and huge orange beard` |
| `ui/icon_hp.png` | 属性·血量 | `a small red heart icon` |
| `ui/icon_attack.png` | 属性·攻击 | `a small sword icon` |
| `ui/icon_armor.png` | 属性·护甲 | `a small light blue shield icon` |
| `ui/icon_speed.png` | 属性·移速 | `a small leather boot icon` |
| `ui/icon_range.png` | 属性·射程 | `a small bow and arrow icon` |
| `ui/star.png` | 胜利星星 | `a big gold star with orange cel shading and a dark brown outline` |
| `ui/star_empty.png` | 空星 | `the same star shape, empty dark grey stone` |
| `ui/victory.png` | 胜利徽章 | `a victory emblem: a blue heraldic shield with crossed swords, laurel branches, a red ribbon banner across the bottom, empty for text` |
| `ui/defeat.png` | 失败徽章 | `a defeat emblem: a cracked dark shield with a skull, a torn dark grey ribbon banner, empty for text` |
| `ui/cursor.png` | 鼠标 | `a mouse pointer shaped like an iron gauntlet pointing finger, tip at the top left` |

### B3 UI 反向提示词

```
text, letters, numbers, sticker, white border, shiny polished gold, chrome, glossy plastic, modern flat UI, neon, sci-fi, 3D render, photorealistic, perspective tilt, multiple elements, background scenery
```

---

## 换上之后 UI 布局怎么改（照王国保卫战）

- **左上**：一排小牌子：矿 / 木 / 铁锭 / 木板 / 人口 + 骷髅波次 "3/10"
- **路口（巢穴出口）**：骷髅按钮闪烁 + 倒计时圈，点击 = 提前叫下一波
- **点建筑 / 工程师**：在它周围弹出**环形菜单**（圆形按钮 + 下面价格牌），不再用底部指令卡
- **左下**：英雄工程师圆形头像 + 血条，点一下 = 选中他
- **底部中间**：选中单位时出一条细信息条：名字 + 血量 / 攻击 / 护甲 / 移速图标数值
- 产能面板默认收起，按 C 再出
