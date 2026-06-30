# Les Strates — Récapitulatif du projet (à jour)

Roguelike au tour par tour en Godot 4.3 / GDScript. Une héroïne unique (Aria),
build par arme, ascension de tour à étages, carte ramifiée. Séparation stricte
logique/affichage/données : `Main.gd` (logique), `Hud.gd` (affichage),
`Data.gd` (registre de données), `Entity.gd` (modèle pur), `GameState.gd`
(autoload, sauvegarde persistante JSON dans `user://save.json`).

## Ce qui est fait

### Phase 0-2 — Fondations
- Système de tour par énergie/vitesse (`Entity.ACTION_COST`, `effective_speed()`).
- Génération procédurale d'étages (`Dungeon.gd`) avec biomes, brouillard de
  guerre (`explored`/`visible`), eau/route/arbres/rochers/décor.
- Carte ramifiée entre étages (`RunMap.gd` + `MapView.gd`) : nœuds combat,
  élite, boutique, événement, repos, boss.
- Build par arme (équipement modifie le style de combat d'Aria).
- Monnaie de run (Éclats) → améliorations de stats permanentes au Sanctuaire.

### Phase 3 — Pouvoirs passifs
- `Data.POWERS`, `POWER_GLYPH`, `POWER_MODS` : pouvoirs cumulables sans
  limite, sauf exclusions mutuelles explicites ponctuelles.
- Sources de drop : monstres légendaires (taux faible, `LEGENDARY_CHANCE`),
  boss tous les 15 étages, ou boutique.
- `Entity.powers`, `has_power()`, `is_legendary`; mods en % (`atk_pct`,
  `max_hp_pct`) appliqués après les mods plats dans `recompute_stats()`.
- Déclenchement via `Main._trigger_powers()` (appelé depuis `_player_acted`),
  hooks venin (`_player_attack`) et détonation (`on_enemy_killed`).
- Affichage : sidebar des pouvoirs actifs dans `Hud.gd` (`_rebuild_powers()`).

### Phase 5 — Arbre de Connaissances + Serments
- Deuxième monnaie meta : Connaissances (gagnées en fin de run, proportionnel
  à la progression d'étage + boss tués + bonus de Serments), distincte des
  Éclats : débloque des **règles/systèmes**, pas des stats plates.
- `Data.KNOWLEDGE_BRANCHES`, `KNOWLEDGE_NODES`, `KNOWLEDGE_ORDER` : arbre en
  DAG avec prérequis, inspiré des arbres de Stratégies Intégrées d'Arknights —
  chaque nœud change une règle du jeu (pool de drop amélioré, pouvoir de
  départ garanti, boutique propose toujours un pouvoir, boost légendaire,
  Forge, Codex, révélation du butin...), pas de simples "+2 ATK".
- `GameState` : `knowledge`, `knowledge_nodes`, `discovered` (catégories
  skill/power/unique), `add_knowledge()`, `has_knowledge_node()`,
  `node_prereqs_met()`, `can_unlock_node()`, `buy_knowledge_node()`, lecteurs
  raccourcis (`starts_with_power`, `better_drop_pool`, `shop_always_power`,
  `oaths_unlocked`, `major_oaths_unlocked`, `legendary_boost`,
  `codex_unlocked`, `reveals_loot`, `forge_unlocked`), `note_discovery()`,
  `discovered_count()`. Persisté dans la sauvegarde.
- Serments (`Data.OATHS`, `oath_by_id()`) : modificateurs de difficulté
  optionnels activables à l'écran de loadout (`active_oaths`, `has_oath()`,
  `toggle_oath()`), ex. Pauvreté, Fragilité, Horde, Glas, Funeste — risque
  contre récompense (multiplicateur d'Éclats, bonus de Connaissances).
- Écrans dédiés dans `Hud.gd` : `show_knowledge()` (arbre), `show_codex()`
  (pouvoirs/uniques découverts), panneau de Serments dans `show_loadout()`.
- Forge (`Main._forge_equipment()`) débloquée par l'arbre, accessible au repos.
- Œil du Devin (nœud de l'arbre) : révèle le butin à travers le brouillard de
  guerre via `Dungeon.mark_explored()` et `MapView.reveal_loot`.

### Phase 4 — Récompenses de fin de nœud
- Remplacement du heal silencieux 20% par un écran de choix
  (`Main._open_floor_reward()`, `_make_floor_rewards()`,
  `_consumable_reward()`, `resolve_floor_reward()`) : choix de 1 parmi N
  (soin / équipement / éclats, + bonus compétence ou consommable sur nœud
  élite). Respecte le Serment Funeste (pas d'option de soin si actif).
- Écran `Hud.show_floor_reward()`.

### Identité visuelle (refonte façon Moonring)
- Palette unifiée "Les Strates" dans `Data.gd`/`_assets_gen.gd` : familles
  INK, STONE, STEEL, BONE, GOLD, BLOOD, ARCANE, CYAN, POISON, EMBER — sombre,
  désaturée, accents nets, éclairage cohérent en haut à gauche.
- Génération procédurale (`_assets_gen.gd`, exécuté en headless via
  `godot --headless --script res://_assets_gen.gd`) : tous les sprites de
  créatures (chevalier, mage, ranger, gobelin, loup, squelette, orc, spectre,
  boss), butin (arme/armure/relique/artefact/potion), terrain de biomes
  (sol/arbre/rocher/eau/décor/route) et icônes de nœuds de carte (combat,
  boss, élite, boutique, événement, repos) redessinés avec cette palette.
- **Aria** : sprite dédié et distinct (plus du tout le "knight" générique),
  avec **vues directionnelles** face/dos/profil (`aria`, `aria_back`,
  `aria_side`). Câblé dans le code, pas seulement de l'art statique :
  `Entity.facing` mis à jour dans `Main.try_move()` à chaque action de
  déplacement, résolu en sprite via `MapView._directional_sprite()` (mapping
  facing → nom de sprite + miroir horizontal) et dessiné via
  `MapView._blit_ex()` (rect à largeur négative pour le miroir). Vue de
  profil retravaillée après retour utilisateur (cheveux trop "blob"/chauve,
  épée encombrante) : calotte fine + tresse, épée retirée de cette vue.
- Refonte palette des biomes (`Data.BIOMES`) : couleurs assombries/désaturées/
  plus froides (ex. toundra : blanc quasi-pur → bleu-gris).
- 6 icônes de nœuds de carte régénérées avec la même direction artistique,
  intégrées dans `Hud.gd` (`_node_icon()`, cache, fallback texte si texture
  manquante).

### Refonte visuelle med-fantasy NÉON (2e passe Moonring)
- **Recherche** sur l'identité de Moonring (palette restreinte ~4 couleurs
  dérivée du cercle HSV, sprites néon vifs sur fonds quasi-noirs, glow/bloom,
  palette qui change selon le lieu/les lunes) → traduite ici en **palettes de
  biome restreintes** : sols TRÈS sombres/désaturés sur lesquels les accents
  néon (feuillage, eau, décor) ressortent. `Data.BIOMES` retravaillé en ce sens.
- Palette d'identité de `_assets_gen.gd` poussée : contour `INK` quasi-noir,
  accents (GOLD/BLOOD/ARCANE/CYAN/POISON/EMBER) plus vifs.
- Nouvelles primitives de rendu d'assets : **`_glow`** (halo néon additif/bloom
  appliqué aux yeux, gemmes, escalier, lave, braises, cristaux, butin magique)
  et **dithering Bayer 4×4** sur les sols (grain doux, fini rétro). Tous les
  PNG de `assets/` ont été régénérés en conséquence.
- **Ambiance en jeu** (`MapView.gd`, totalement nouvelle) : **pool de torche**
  + **halo chaud** centrés sur l'héroïne et **vignette** de bord, dessinés en
  surimpression à la fin de `_draw()` à partir de textures radiales générées
  une fois (`_make_pool`, `_make_radial`, `_make_vignette`). Brouillard
  (`COLOR_FOG`/`COLOR_MEMORY`) assombri vers le quasi-noir. Le pool s'estompe à
  0 sur son anneau extérieur (pas de bord carré visible).
- **UI** (`Ui.gd`/`Hud.gd`) : panneaux et cartes dotés d'un liseré arcanique
  discret + ombre portée (relief), fonds de menu/sidebar approfondis pour
  coller à la palette assombrie.
- Note d'outillage : le binaire Godot n'étant pas exécutable dans cet
  environnement, les PNG ont été régénérés par un **moteur de rendu Python
  fidèle** (mêmes primitives/logique que `_assets_gen.gd`) ; les deux doivent
  rester cohérents. `_assets_gen.gd` reste la source canonique côté Godot.

### Outillage / validation
- Godot 4.3 headless utilisé pour valider réellement les changements
  (rendu de sprites en image, exécution de `_smoketest.gd` via
  `_SmokeTest.tscn`) — pas seulement une relecture de code.
- `_smoketest.gd` couvre : pouvoirs (acquisition/doublon/exclusion/déclenchement),
  arbre de connaissances (prérequis/achat/persistance), Pacte de Pouvoir,
  Serments (toggle/contrainte/effet/récompense), Codex, Forge, Œil du Devin,
  écran de récompense de fin de nœud (choix standard/élite/Funeste), sprites
  directionnels (mapping facing→sprite et mise à jour de `player.facing`
  après une action).

## Ce qui reste à faire

### Phase 6 — Dialogues / PNJ
- Système de dialogue (PNJ aux nœuds événement/boutique/repos), portraits,
  arbres de choix simples liés aux Serments/Connaissances.

### Phase 7 — Lore + fins multiples
- Texte de lore distillé par étages/découvertes du Codex.
- Plusieurs fins selon progression, Serments actifs, % de Codex complété.

### Phase 8 — Finition
- Équilibrage final (courbes de dégâts/HP, taux de drop, coût des nœuds de
  l'arbre), polish UI/UX, sons/musique si prévu, écran titre/crédits.

### Suivis artistiques identifiés (non bloquants)
- Sprites directionnels pour les ennemis (actuellement seule Aria en a ;
  le loup serait un bon candidat suivant).
- Variantes teintées pour les ennemis élite (actuellement même sprite que la
  version normale).
- Sprite distinct pour le boss légendaire (actuellement `boss` générique).
- Représentation visuelle des pouvoirs actifs en combat (actuellement
  seulement listés en sidebar texte, pas d'effet visuel à l'écran).
- Polish des sols/murs d'intérieur de donjon (actuellement focalisé sur les
  biomes extérieurs).

## Notes d'infrastructure
- Branche de travail : `claude/new-session-5ndfrb` (à jour avec le remote).
- Nettoyage GitHub en attente de décision utilisateur : 3 branches
  redondantes (`game-launch-checklist-xyir98`,
  `game-modifications-summary-x29h6s`, `rpg-roguelike-autonomy-g1vxmt`) sont
  toutes des ancêtres fusionnés de la branche actuelle, mais l'une d'elles
  est la branche par défaut du repo sur GitHub (changement uniquement
  possible via les Settings GitHub, pas d'accès outillé pour le faire à
  distance) — suppression à faire une fois le défaut changé, ou suppression
  partielle des deux autres dès maintenant si souhaité.
