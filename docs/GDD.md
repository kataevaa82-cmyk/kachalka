# Game Design Document — КАЧАЛКА

**Working title:** КАЧАЛКА  
**Genre:** 3D gym simulator / timing-action idle  
**Platform:** Яндекс Игры (HTML5), desktop + mobile  
**Engine:** Godot 4.7 Compatibility  
**Age:** 0+ (no gore, no gambling)  
**Session:** 2–8 minutes  

## 1. Fantasy

Ты — новичок в ночной качалке. Ходишь между станками, ловишь ритм повторения, растёшь на глазах. Цель — не «кликер с цифрами», а **видимое тело + точное попадание в такт**.

## 2. Why this is interesting on Yandex Games

| Pillar | Implementation |
|--------|----------------|
| Instant read | Low-poly hero, neon gym, stations as 3D icons |
| One-thumb skill | Timing bar on every rep (not auto-idle) |
| Visible progress | Bone scale: arms / chest / legs grow in-session |
| Short loop | Energy 100 → 4–6 sets → protein, rest or rewarded ad |
| Social | Leaderboard «Масса» |
| Humour | Trainer one-liners in Russian gym slang |

## 3. Player fantasy loop

```
Walk gym → Pick station → Timing reps → Gains + cash
    → Body grows → Shop (protein / belt / preworkout)
    → Energy empty → Ad or wait → Heavier unlocks → Leaderboard
```

## 4. Controls

| Device | Move | Camera | Interact | Rep |
|--------|------|--------|----------|-----|
| Keyboard | WASD | mouse | E | Space / LMB |
| Touch | left virtual stick | right drag | button «Занять» | tap anywhere on HUD |

No OS-reserved shortcuts (Ctrl+W, Alt+F4, etc.).

## 5. Gym layout (metres, origin at floor centre)

Playable box **16 × 12 × 4.2**. Grid **2 m**. Ceiling **4.2 m**. Door **0.9 × 2.1**. Corridor width ≥ 1.8 m around stations.

```
        +Z Godot (Blender +Y)  mirrors + neon sign
   PullUp          Shop/Fridge         Treadmill
        ·              ·                    ·
                    SPAWN
        ·              ·                    ·
   Bench           SquatRack           Dumbbells
        -Z Godot  entrance
```

## 6. Stations

| Id | Name | Muscle | Unlock mass | Energy / set | Cash / perfect |
|----|------|--------|-------------|--------------|----------------|
| bench | Жим лёжа | chest | 0 | 12 | 8 |
| dumbbell | Гантели | arms | 0 | 10 | 7 |
| treadmill | Дорожка | cardio | 0 | 8 | 5 |
| bike | Велосипед | cardio | 0 | 7 | 4 |
| rower | Гребля | cardio | 0 | 9 | 6 |
| hyper | Гиперэкстензия | back | 0 | 8 | 6 |
| ropes | Канаты | arms | 64 | 10 | 6 |
| row | Тяга сидя | back | 65 | 11 | 8 |
| legpress | Жим ногами | legs | 66 | 13 | 9 |
| kettlebell | Гири | arms | 67 | 10 | 7 |
| shoulder | Жим сидя | chest | 69 | 11 | 8 |
| lat | Тяга сверху | back | 72 | 11 | 8 |
| squat | Присед | legs | 76 | 14 | 10 |
| dip | Брусья | chest | 84 | 13 | 9 |
| pullup | Турник | back | 88 | 12 | 9 |

Set = 6–14 reps depending on station. Three misses in one set → abort, combo reset.

### 6.1. Six progression levels

| Level | Name | Unlock | Gameplay change |
|------:|------|-------:|-----------------|
| 1 | Подвал «Старт» | 62 kg start | Base tempo and rewards |
| 2 | Районный зал | 70 kg | Tempo +6%, rewards +15% |
| 3 | Железный цех | 82 kg | Tempo +12%, precision windows −8% |
| 4 | Неоновая лига | 96 kg | Tempo +18%, rewards +50% |
| 5 | Арена чемпионов | 112 kg | Tempo +24%, precision windows −20% |
| 6 | Кузница титанов | 128 kg | Tempo +30%, double cash |

Each level changes the hall accent/background, HUD title, timing period, accuracy window, gains and cash. Unlock order is automatic and persisted indirectly through muscle stats, so old saves need no extra level field.

## 7. Timing minigame

- Marker sweeps a bar. Green window starts at 18% of the period.
- Perfect (inner 8%): 2.0× gains, combo+1, punchy SFX.
- Good (green): 1.0×, combo+1.
- Miss: 0.25×, combo=0, trainer roast.
- Preworkout item: green window × 1.35 for 90 s.
- Combo 5 / 10 / 15: pitch-up SFX + floating «ОГОНЬ».

Base period: 0.62–1.05 s depending on the minigame. Current level multiplies it from 1.0 down to 0.70; accuracy windows narrow from 1.0 to 0.74.

## 8. Stats (persisted)

```
chest, arms, back, legs, cardio : float 0..160
mass = 62 kg base + diminishing nonlinear contribution per muscle
balanced chest/arms/back/legs add up to 12% balance bonus
energy : 0..100
money : int
inventory : {protein, preworkout, belt, gloves}
combo_best, total_reps, day_program
```

Visual: `UpperArm_*` scale XZ from 1.0 → 1.9 with arms; `Chest` 1.0 → 1.55; `UpperLeg_*` 1.0 → 1.7. Head does not scale (silhouette law).

## 9. Economy

- Perfect rep → cash. Set complete bonus.
- Protein: 40 cash, +45 energy, +10% gains 60 s.
- Preworkout: 70 cash, wider window.
- Belt: 120 cash, squat gains +25% (permanent).
- Gloves: 90 cash, dumbbell miss forgiveness (first miss per set ignored).
- Rewarded ad: +60 energy **or** +1 protein (player choice).
- Interstitial: after every 4 completed sets, never during a set, never before first set.

## 10. Energy

- Starts 100. Set costs table above.
- Regen 1 / 8 s while walking (not during set).
- At 0: prompt rest / ad. Gameplay does not hard-lock.

## 11. Trainer lines (examples)

- Perfect: «Вот это жим.» / «Спину держи — красота.»
- Miss: «Локтями жмёшь.» / «Это не присед, это поклон.»
- Empty energy: «Забой. Протеин или диван.»
- Unlock squat: «Ноги тоже качай.»

## 12. UI surfaces

1. Boot / title
2. HUD: mass, energy, cash, combo
3. Prompt: «E — Жим лёжа»
4. Workout overlay: timing bar + rep count
5. Shop panel
6. Pause (Yandex `game_api_pause`)
7. Level unlock toast + themed hall sign
8. Result toast after set

Safe area: 16:9 desktop and 9:19.5 mobile. HUD in 90 dp margins. Sticky banner reserve 50–100 px bottom on mobile via SDK.

## 13. Audio

Procedural / tiny WAV: hit, perfect, miss, complete, UI. Optional muted bed. Mute on `game_api_pause`.

## 14. Save

- Local `user://save.json`
- Yandex cloud player data when authorised (≤ 200 KB)
- Never require login to play

## 15. Analytics events (SDK)

`gym_set_complete`, `ad_rewarded`, `shop_buy`, `mass_milestone_10/25/50`.

## 16. Out of scope (v1)

PvP, full clothing shop, photoreal textures, multiplayer ghosts, voice acting.
