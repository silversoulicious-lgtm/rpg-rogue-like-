# Bilan complet du jeu — « Les Strates » (audit critique)

> Audit réalisé par lecture intégrale du code (`scripts/*.gd`, `project.godot`,
> `_smoketest.gd`, `Data.gd`, docs). Aucune modification de code : ce document
> liste ce qui pourrait être mieux, sans complaisance, puis propose un plan
> d'action priorisé. Les références `fichier:ligne` pointent vers l'état actuel
> de la branche.

---

## 1. Ce qui est solide (pour situer le niveau)

- Architecture propre pour un prototype : logique (`Main.gd`) / affichage
  (`Hud.gd`, `MapView.gd`) / données (`Data.gd`) / modèle pur (`Entity.gd`)
  réellement séparés.
- Contenu data-driven cohérent (ennemis, boss, compétences, objets uniques,
  préfixes, serments, arbre de Connaissances) : ajouter du contenu est facile.
- Test de fumée headless qui pilote une vraie partie — rare sur un projet solo.
- Repli ASCII systématique si un asset manque : robuste.
- Fog of war, système d'énergie/vitesse, statuts empilables : les fondations
  roguelike sont là.

Le reste du document est volontairement à charge.

---

## 2. Bugs avérés (confirmés à la lecture, à corriger en priorité)

### 2.1 — Décalage d'un étage : le run commence à « Étage 2 »
`start_run()` initialise `floor_num = 1` (Main.gd:222) puis appelle
`_advance("combat")` qui fait `floor_num += 1` (Main.gd:354). Le premier étage
joué s'affiche donc **Étage 2**. Conséquences en cascade :
- l'écran de mort et le record `best_floor` sont gonflés de 1 ;
- le gain de Connaissances (`floor_num - best_floor`, Main.gd:2107) est faussé ;
- `biome_for_floor`, `_pick_enemy_def`, tout le scaling par étage sont décalés.

### 2.2 — Le drop de pouvoir des Gardiens ne se déclenche JAMAIS
`on_enemy_killed` : `if floor_num % 15 == 0: _drop_power(...)` (Main.gd:1305).
Or les étages de boss tombent sur 7, 13, 19, 25… (≡ 1 mod 6, puisque seuls les
étages réels incrémentent `floor_num` et qu'un acte = 5 étages + le boss).
`6k+1 ≡ 0 (mod 15)` n'a **aucune solution** : ce chemin de code est mort.
Les pouvoirs ne viennent donc que des monstres légendaires et de la boutique.

### 2.3 — Le statut « weaken » est sans effet sur les ennemis
Seul `_player_def()` (Main.gd:1077) lit `has_status("weaken")`. L'attaque
ennemie (`_enemy_atk`, Main.gd:1706) ne le consulte jamais. Résultat : le
préfixe d'armure **« des Représailles » (renvoi) est un no-op complet** —
il applique un statut que rien ne lit (Main.gd:1252-1255). Un des 6 préfixes
vendus au joueur ne fait littéralement rien.

### 2.4 — Les gardiens-boucliers des boss apparaissent n'importe où
`_boss_on_spawn` place les âmes-boucliers/chaudrons via
`dungeon.random_floor_tiles(...)` **sur toute la carte** (Main.gd:534). Sur une
carte 640×400 avec vision 4, le boss est réduit à ~10-15 % de dégâts reçus
(`resist` 0.85-0.9) tant que des gardiens invisibles, dispersés à des centaines
de cases, ne sont pas retrouvés. Expérience potentiellement atroce : un boss
« immortel » sans indication d'où chercher. Ils doivent spawner près du boss
(et/ou être révélés/fléchés).

### 2.5 — Esquive et critique non plafonnés → immortalité atteignable
`recompute_stats` ne borne ni `dodge_chance` ni `crit_chance`
(Entity.gd:240-255). Voile d'Ombre (+20 %) + le talent Agilité (+10 %,
**cumulable** car les talents peuvent être repris à chaque niveau) + affixes
d'Esquive : 100 % d'esquive est atteignable sur un long run → le joueur devient
intouchable (hors DoT). Même problème de principe pour le crit et le vol de vie.

### 2.6 — La Forge « renforce » aussi les malus
`forge_choice` amplifie chaque bonus de ±30 % **en respectant le signe**
(`signi(int(v))`, Main.gd:2078). Forger une Hache (VIT −5) ou un objet unique à
malus (`max_hp: -6`) **aggrave le malus**. C'est contre-intuitif pour une
amélioration payée : les valeurs négatives devraient être ignorées (ou
réduites, en le disant).

### 2.7 — Gardiens orphelins après la mort du boss
Quand le boss meurt, ses âmes-boucliers (`stationary`, 0 ATK) restent sur la
carte comme des sacs à PV inertes. Ni menace, ni intérêt : ils devraient mourir
avec le boss.

### 2.8 — WASD cassé sur clavier AZERTY (jeu… en français)
`_unhandled_input` compare `event.keycode` (dépendant de la disposition,
Main.gd:731) au lieu de `physical_keycode` ou d'actions de l'InputMap. Sur un
AZERTY, il faut physiquement presser Z/Q pour « W/A ». Pour un jeu entièrement
en français, c'est le premier truc qu'un joueur FR remarquera. Aucune touche
n'est remappable.

### 2.9 — Impossible de quitter un run en cours
En état `PLAYING`, Échap n'est pas géré (Main.gd:759-775). Pas de menu pause,
pas d'« abandonner l'ascension », pas de sauvegarde du run : la seule sortie
est la mort ou tuer le process (et dans ce cas **les Éclats du run sont
perdus**, rien n'est banqué). C'est un trou majeur d'UX pour un jeu à sessions.

### 2.10 — UI cassée si la fenêtre n'est pas en 16:9
`project.godot` déclare `stretch/aspect="expand"` mais toute la HUD est
positionnée en absolu sur `VIEW = 1280×720` (Hud.gd:7, 79, 191 ; bouton du Hub
Hud.gd:304 ; TownView VIEW:11). Redimensionnée en 21:9 ou 4:3, la sidebar et le
journal flottent au mauvais endroit. Il faut des ancres (`PRESET_*`), pas des
positions codées en dur — ou assumer `aspect="keep"` avec des bandes noires.

---

## 3. Problèmes de game design / équité du combat

### 3.1 — Les ennemis à distance tirent sans ligne de vue, à travers le brouillard
Aucun test de visibilité ni de LoS dans `_enemy_act_ranged` / `_enemy_cast`
(Main.gd:1766-1814). La vision de base est **4** (Data.gd:106) alors que les
portées ennemies vont de 4 à **7** (Œil du Néant). Le joueur se fait tirer
dessus par des ennemis invisibles, à travers murs et forêts, sans contre-jeu.
C'est la plus grosse source d'injustice ressentie du jeu actuel.

### 3.2 — Le joueur triche aussi : auto-visée omnisciente
`_nearest_enemy_in_range` (Main.gd:959) ignore brouillard et murs. Un bolt
spammé « détecte » les ennemis cachés ; `dash_strike` cible à portée 99 à
travers toute la carte ; le Drone attaque des cibles invisibles (et peut
frapper un Mimic camouflé). Les AoE traversent les murs (Chebyshev pur).
Symétrique, donc « équilibré », mais ça vide le positionnement de son sens
— alors que le README vend un « combat tactique où le positionnement compte ».

### 3.3 — IA omnisciente et sans pathfinding
Tous les ennemis marchent vers le joueur dès le tour 1, où qu'ils soient
(`_enemy_step_toward(e, player.pos())` inconditionnel). Sur une grande carte,
toute la population converge en permanence. Et le déplacement est un greedy à
2 directions : le moindre lac ou bosquet bloque définitivement un ennemi (un
boss coincé derrière l'eau = kill gratuit à distance). Il manque :
- un rayon d'agro / état dormant tant que non vu ;
- un contournement d'obstacle minimal (A* borné, ou pas de côté aléatoire).

### 3.4 — Les grandes cartes sont du vide
`count` ennemis est clampé à 30 et le butin à 14 (Main.gd:466, 501) quelle que
soit la taille. Une 640×400 (256 000 cases) contient la même chose qu'une
320×200 : des minutes de marche case par case, vision 4, sans minimap, sans
auto-explore, sans boussole vers l'escalier. La route aide, mais « suivre la
route » n'est pas de l'exploration, c'est du transport. Options : réduire
`MAP_MAX_H`, densifier par surface (POI multiples, camps, événements de
terrain), minimap, auto-voyage vers les cases explorées.

### 3.5 — Génération : risque de gel sur les cartes immenses
`_generate` remplit 5 grilles Array-of-Array (≈ 1,3 M d'appends), parcourt tout
pour le décor, puis fait un BFS complet (`_reachable_set`) — le tout en
GDScript interprété (Dungeon.gd:39-82). Sur 640×400, attendez-vous à un freeze
de plusieurs secondes à chaque étage. `PackedByteArray` + génération limitée
aux besoins réels réduirait ça d'un ordre de grandeur.

### 3.6 — Équilibrage non instrumenté (risques identifiés)
- **Scaling ennemi linéaire** ×(1 + 0,12/étage) sur PV **et** ATK
  (Main.gd:593) contre un scaling joueur par objets ×(1 + 0,08/étage)
  (Data.gd:628) : l'ATK ennemie finit mécaniquement par dépasser la défense
  plate du joueur. La défense **ennemie n'est pas scalée du tout**
  (Main.gd:603) : celle du joueur explose relativement, la leur devient nulle.
- **XP = valeur en Éclats** (Main.gd:1268) : deux économies soudées, impossible
  d'ajuster l'une sans casser l'autre. Courbe `6 + 5×niveau` très plate →
  pluie de niveaux en début de run, interruptions constantes.
- Événement « pari » : EV strictement positive (60 % de +30 contre −10 PV),
  ce n'est pas un pari.
- Aucun harnais de mesure : personne ne sait à quel étage un build moyen meurt.

### 3.7 — Le Serment de Pauvreté est incohérent
`run_shards = 0 if has_oath("pauvrete")` mais surtout `_grant_starting_bonuses`
saute **aussi** Héritage/Instinct — c'est documenté, ok — par contre le Pacte
de Pouvoir (nœud de l'Arbre) passe quand même (Main.gd:256). « Aucun bonus de
départ » n'est pas tenu. À trancher (et à tester dans le smoke test).

---

## 4. UX / interface

1. **Modalités d'entrée incohérentes** : le donjon est 100 % clavier, tous les
   menus/overlays sont 100 % souris (aucun focus initial, pas de navigation
   flèches+Entrée). Il faut choisir : soit tout au clavier est possible
   (roguelike classique), soit la grille est aussi cliquable.
2. **Journal de combat illisible** : 8 messages max (`MAX_LOG`, Main.gd:8) dans
   un panneau de 88 px, sans défilement. Un tour chargé (frappe double + procs
   + DoT + morts) déborde largement : le joueur perd de l'information de
   combat. Il faut un historique scrollable.
3. **Aucune inspection d'ennemi** : pas de survol/tooltip donnant PV, ATK,
   traits (`resist_phys`, `on_hit`…). Le seul feedback est une barre de 4 px.
   Pour un jeu tactique avec 30 monstres data-driven, c'est un gâchis : toute
   cette data existe déjà et n'est jamais montrée.
4. **Armurerie = piège** : au Hub, l'Armurerie et la Porte de la Tour ouvrent
   le même écran, et « Choisir » **lance immédiatement le run**
   (Main.gd:156-170, choose_loadout → start_run). Entrer à l'Armurerie « pour
   voir » peut démarrer une ascension. Séparer préparation (loadout/serments)
   et départ (porte uniquement).
5. **Pas de cause de mort** : l'écran de fin ne dit pas ce qui a tué le joueur.
   C'est l'information n°1 d'un écran de mort de roguelike.
6. **Le Codex n'a pas de bestiaire** (Hud.gd:712-738) : compétences, pouvoirs,
   uniques — mais pas les 20 monstres ni les 10 boss, alors que ce sont les
   découvertes les plus mémorables (et `ai` contient tout ce qu'il faut
   afficher).
7. Le Mimic déguisé affiche sa barre de PV dès qu'il est blessé
   (MapView.gd:417) — le déguisement fuit.
8. Les stubs Forge/Boutique du Hub ne se ferment qu'à la souris (état `CHOICE`
   sans gestion d'Échap).
9. Le bâtiment (sprite 64×88) n'est déclenché que par UNE case : on peut
   marcher « dans » le visuel sans rien déclencher. Petit, mais perceptible.
10. **Aucun son** : ni musique ni SFX. Assumé (Phase 8), mais à ce stade même
    3 bips (coup / ramassage / niveau) changeraient la sensation de jeu.

---

## 5. Contenu (minceur des pools)

| Pool | Taille actuelle | Problème |
|---|---|---|
| Artefacts | **5** | Héritage×2 + drops : pool épuisé en mi-run, les drops d'artefacts deviennent impossibles (`_pick_artifact_def` → vide) |
| Pouvoirs | **5** | idem à terme ; 2 s'excluent mutuellement |
| Événements | **7** | répétitifs dès le 2ᵉ run ; aucun ne dépend du biome/étage |
| Consommables | **4** (dont 3 soins) | pas de bombe, téléport, antidote, buff — les classiques du genre |
| Talents | 16, quasi tous « +stat plat » | le choix de niveau est la décision la moins intéressante du jeu ; comparer aux dons Hades cités en référence |
| Élites | ×1,25 PV / ×1,2 ATK | de simples éponges : pas d'affixe (rapide, explosif, soigneur…), pas de teinte visuelle |

Autres points :
- Les compétences par arme sont bien fournies (6/6/6), mais une seule est
  active à la fois et le cd est court : le combat se joue « attaque + spam
  compétence ». Une 2ᵉ case de compétence ou des consommables actifs
  donneraient de vraies rotations.
- Biome ↔ strate désynchronisés : boss tous les 6 étages réels, biome tous les
  12 → le « thème » d'une strate n'existe pas vraiment. Aligner (biome = 2
  strates, ou boss thématisé par biome) renforcerait l'identité Aincrad.
- Les ennemis anciens (Gobelin…) restent dans le pool à poids égal pour
  toujours : au 30ᵉ étage on combat les mêmes 25 monstres à stats gonflées.
  Prévoir `max_floor` ou des poids par étage.

---

## 6. Technique / dette

1. **`Main.gd` = objet-dieu de 2 180 lignes** : état, flux d'écrans, génération,
   combat, IA, butin, boutique, événements, économie. Chaque nouvelle feature
   (dialogues, fins multiples — Phases 6-7 prévues) va empirer les choses.
   Découpage naturel : `CombatSystem`, `EnemyAI`, `LootSystem`,
   `RunProgression` (nœuds/actes), `Main` réduit au routage.
2. **`gen.py` (1 990 l.) duplique `_assets_gen.gd` (2 193 l.)** avec une
   divergence d'arrondi connue. Deux générateurs à maintenir pour les mêmes
   sprites, c'est le double de travail garanti. En garder UN (le .gd, qui fait
   foi) et supprimer/geler l'autre.
3. **Pas de CI** : le smoke test existe mais rien ne l'exécute sur push. Un
   workflow GitHub Actions (télécharger Godot headless, import, lancer
   `_SmokeTest.tscn`) transformerait ce test en vrai filet de sécurité.
   Le smoke test lui-même utilise un RNG non seedé (`randi()`) → flakiness
   possible ; le seeder.
4. **Sauvegarde sans version** : `save.json` n'a pas de champ `version`
   (GameState.gd:133-147). La première évolution de format cassera les saves
   en silence. Ajouter `{"version": N}` + migration.
5. **Pas de sauvegarde du run en cours** : lié au §2.9 — quitter = tout perdre.
6. **RNG fragmenté** : `Main.rng` seedé au hasard, mais `pool.shuffle()`
   (Hud.gd:830) et le smoke test utilisent le RNG global. Des runs seedés
   (daily, partage de seed, reproduction de bugs) sont impossibles en l'état.
   Centraliser tout tirage gameplay sur `Main.rng`.
7. **Textures mortes** : `knight`, `mage`, `ranger` chargés dans MapView
   (MapView.gd:80) alors que plus rien ne les référence depuis le passage à
   Aria. Idem glyphes dupliqués (Drake et Kobold = « k », Ours et boss = « B »)
   pour le repli ASCII.
8. **`infer_weapon_type` devine le type par le NOM français** de l'objet
   (« Arc » dans la chaîne, Data.gd:96-101). Fragile au premier renommage.
   Les uniques devraient déclarer `wtype` explicitement.
9. **`Hud.refresh()` reconstruit 4 boîtes de widgets à chaque action** du
   joueur (queue_free + realloc, Hud.gd:1017-1074). Invisible aujourd'hui,
   mais c'est du churn inutile ; ne reconstruire que sur changement.
10. **Docs mensongères par endroits** : README dit sprites « 24x24 » (réels :
    32×32), « Gardien tous les 5 étages » (réel : 6 étages réels),
    « PNG 24x24 » ligne 142. RESUME_SESSION est bon. Pas de LICENSE.
    Pas d'`export_presets.cfg` → impossible de shipper un build sans config
    manuelle.
11. **Localisation en dur** : 100 % des chaînes FR inline. Acceptable tant
    qu'aucune traduction n'est prévue — à acter consciemment.

---

## 7. Plan d'action proposé (ordonné, sans code pour l'instant)

### P0 — Corriger l'existant (1 passe courte, tout est petit)
1. Off-by-one d'étage (§2.1) — corriger + assert dans le smoke test
   (`floor_num == 1` au premier étage).
2. Drop de pouvoir des boss (§2.2) — remplacer `floor_num % 15` par une règle
   qui existe (ex. `map_act % 3 == 0` ou tous les 2 Gardiens).
3. Rendre « weaken » effectif sur les ennemis (§2.3) → le préfixe Représailles
   fonctionne.
4. Gardiens-boucliers près du boss + mort avec le boss (§2.4, §2.7).
5. Plafonds : esquive ≤ 60 %, crit ≤ 75 %, vol de vie ≤ 50 % (§2.5) — valeurs à
   discuter, mais des plafonds.
6. Forge : ne jamais amplifier un malus (§2.6).
7. `physical_keycode` + InputMap pour tous les contrôles (§2.8).
8. Menu pause sur Échap : Reprendre / Options / Abandonner l'ascension (les
   Éclats sont banqués à l'abandon, avec malus éventuel) (§2.9).
9. Ancrer la HUD (sidebar/journal/boutons) aux bords réels du viewport (§2.10).
10. Pauvreté : bloquer aussi le Pacte de Pouvoir, ou reformuler le serment
    (§3.7).

### P1 — Équité du combat (le cœur du ressenti)
11. Ligne de vue partagée joueur/ennemis : un tir (dans les deux sens) exige
    d'être dans le champ de vision et sans mur bloquant (Bresenham suffit).
    Les AoE ne traversent plus les murs.
12. Garantir vision ≥ portée max rencontrée à l'étage, OU télégraphier les
    tirs hors vision (« un trait siffle depuis l'obscurité » + direction).
13. Rayon d'agro : les ennemis dorment tant que non vus/entendus ; réveil par
    proximité, dégâts, ou cri d'un allié proche.
14. Contournement d'obstacles (A* borné à ~20 pas pour élites/boss, pas de
    côté pour la piétaille).
15. Ciblage lisible : surligner la cible que la compétence choisira, et/ou
    Tab pour cycler les cibles visibles.

### P2 — Rythme, exploration, lisibilité
16. Réduire `MAP_MAX_H` (ex. 240) tant que la densité ne suit pas ; ensuite
    seulement, ré-agrandir avec du contenu par surface (2-3 POI, camps,
    mini-événements de terrain).
17. Minimap (cases explorées) + marqueur d'escalier une fois découvert ;
    optionnel : auto-voyage vers une case explorée.
18. Optimiser la génération (PackedByteArray, une seule passe décor) — vise
    < 100 ms sur la plus grande carte.
19. Journal scrollable + historique complet du run.
20. Tooltip/inspection d'ennemi (PV, ATK, comportement, faiblesses — la data
    `ai` existe déjà).
21. Cause de mort sur l'écran de fin + « tué par » dans le journal de run.

### P3 — Équilibrage instrumenté
22. Harnais headless : N runs auto-joués (politique simple), sortie CSV
    (étage de mort, DPS, PV moyens, économie). Sans mesure, pas d'équilibrage.
23. Découpler XP et Éclats (table d'XP par ennemi) ; adoucir la pluie de
    niveaux (courbe quadratique douce).
24. Scaler la défense ennemie ; revoir le couple scaling ennemi/joueur pour
    viser une mort médiane à l'étage cible (ex. 12-15 pour un nouveau joueur).
25. Passe économie : prix boutique, salvage, Moisson, coût des nœuds de
    l'Arbre, récompenses de serments.

### P4 — Contenu (une fois le socle juste et mesuré)
26. Talents : remplacer la moitié des +stats par des talents à mécanique
    (ex. « les DoT tiquent 2× », « +1 rebond de projectile », « les pièges
    deviennent alliés »).
27. Élites à affixes (rapide, explosif, régénérant, voleur…) + teinte visuelle.
28. Pools : artefacts → ~15, pouvoirs → ~12, événements → ~20 (dont certains
    par biome), consommables → ~10 (bombe, antidote, téléport, buffs).
29. Bestiaire dans le Codex (monstres + boss, avec leurs traits découverts).
30. Aligner biome et strate ; boss thématisé par biome si possible.
31. Puis les phases déjà prévues : Forge du Hub, Boutique du Hub, Dialogues
    (Phase 6), Lore/fins (Phase 7).

### P5 — Finition & industrialisation
32. CI GitHub Actions : import + smoke test à chaque push ; seeder le smoke
    test.
33. Version de sauvegarde + sauvegarde/reprise du run en cours.
34. Un seul générateur d'assets (supprimer ou geler `gen.py`).
35. Découper `Main.gd` (CombatSystem / EnemyAI / LootSystem / RunProgression).
36. RNG unifié + seed de run affichée (ouvre daily runs / partage de seeds).
37. Audio (SFX essentiels puis musique par biome), export_presets, LICENSE,
    README corrigé (32×32, cadence réelle des Gardiens), nettoyage des
    textures/glyphes morts, navigation clavier des menus.

---

## 8. Ordre de bataille recommandé

P0 en premier (que des corrections petites et sûres, grosse valeur), puis P1
avant tout ajout de contenu : tant que le combat n'est pas « juste » (LoS,
agro, visée), équilibrer ou densifier revient à décorer une fondation fissurée.
P2 et P3 peuvent s'entrelacer. P4 seulement après P3 (le contenu s'équilibre
avec l'outillage de P3). P5 en continu, mais la CI (item 32) mérite d'être
remontée juste après P0 : elle protège tout le reste.
