# Les Strates — Récapitulatif du projet (à jour)

Roguelike au tour par tour en Godot 4.3 / GDScript. Une héroïne unique (Aria),
build par arme, ascension de tour à étages en progression linéaire (RNG, plus
de carte à embranchements). Séparation stricte logique/affichage/données :
`Main.gd` (logique), `Hud.gd` (affichage), `Data.gd` (registre de données),
`Entity.gd` (modèle pur), `GameState.gd` (autoload, sauvegarde persistante
JSON dans `user://save.json`).

## Ce qui est fait

### Phase 0-2 — Fondations
- Système de tour par énergie/vitesse (`Entity.ACTION_COST`, `effective_speed()`).
- Génération procédurale d'étages (`Dungeon.gd`) avec biomes, brouillard de
  guerre (`explored`/`visible`), eau/route/arbres/rochers/décor.
- Progression entre étages : nœuds combat, élite, boutique, événement, repos,
  boss (cf. Revue de code / juillet 2026 ci-dessous pour l'évolution vers une
  chaîne linéaire tirée au sort, remplaçant la carte à embranchements).
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

### Bestiaire élargi — 20 monstres + 10 boss (data-driven)
- **Socle réutilisable** (pas de classe par monstre — idiomatique au projet) :
  `Entity.ai` (sac de traits) + répartiteur `Main._enemy_act` sur `ai.behavior`
  (melee, charger, ranged, caster [invocation/cri/sacrifice], fleer, teleporter,
  ambush, stationary). Briques : `_enemy_step_toward/away`, `_enemy_atk` (meute),
  `_enemy_summon`, `_free_adjacent`, `_random_walkable_near`.
- **Statuts** ajoutés : `bleed`, `disease` (DoT, dans `Entity.tick_statuses`),
  `weaken` (défense réduite via `_player_def`), `confusion` (déplacement aléatoire
  dans `try_move`). Helpers `apply_bleed/disease/weaken/confuse`. Affichage HUD.
- **Combat** : résistances `ai.resist_phys/resist_magic` (négatif = vulnérabilité,
  golem ↔ sorts via contexte `_attack_dmg_type`), `immune_fire`/`weak_fire`,
  coups multiples (`atk_count`), vol de vie, statut au contact (`on_hit`),
  explosion à la mort (`explode`), régén suspendue par la brûlure, pièges au sol
  (`hazards`, `_drop_trap`/`_trigger_hazard_at`, rendus par MapView).
- **20 monstres** dans `Data.ENEMIES` (champ `ai`) + **10 boss** dans
  `Data.BOSSES` (sélection cyclique par strate via `_pick_boss_def`). Mécaniques
  boss : gardiens liés protecteurs (`guardians` → `_boss_on_spawn`/
  `_living_guardians` : âmes-boucliers du Seigneur Fantôme, chaudrons de la
  Sorcière), ponte au coup reçu (`spawn_on_hit`, Araignée Mère), phases selon PV
  (`_boss_update_phase`, Dieu-Bête), charge (Bourreau), souffle élémentaire
  (Drake/Wyrm), invocation continue (Roi Liche), régén/faible au feu (Troll
  Ancestral), copie du joueur (Paladin Déchu), regard à distance (Œil du Néant).
- **Sprites** : 21 (monstres + coffre/mimic) + 12 (boss + âme/chaudron) PNG 24×24
  générés (moteur Python + `_assets_gen.gd` synchronisé) avec `.import`.
- **Animations idle/attack/death** : couche de feedback `MapView` découplée
  (bob d'idle, bond d'attaque, flash de dégât, fondu de mort) — appelée par
  `Main` (`fx_attack/fx_hit/fx_death`), pilotée par `_process`, sans incidence
  logique.
- **Smoketest** étendu : spawn + 14–16 tours pour chacun des 20 monstres et des
  10 boss (gardiens, ponte, phases), + vérif statuts/immunité/pièges.

### Outillage / validation
- Godot 4.3 headless utilisé pour valider réellement les changements
  (rendu de sprites en image, exécution de `_smoketest.gd` via
  `_SmokeTest.tscn`) — pas seulement une relecture de code.
- `_smoketest.gd` couvre : pouvoirs (acquisition/doublon/exclusion/déclenchement),
  arbre de connaissances (prérequis/achat/persistance), Pacte de Pouvoir,
  Serments (toggle/contrainte/effet/récompense), Codex, Forge, Œil du Devin,
  écran de récompense de fin de nœud (choix standard/élite/Funeste), sprites
  directionnels (mapping facing→sprite et mise à jour de `player.facing`
  après une action), préfixes de combat (génération + valeur/desc +
  déclenchement Ardent/Cuirasse/Renvoi en combat direct).

### Préfixes de combat sur objets procéduraux (inspiré de Dungeonmans)
Retour utilisateur : donner aux objets Commun/Rare (pas seulement aux
Épiques/Légendaires curés) une chance de porter un effet de combat aléatoire,
comme les préfixes/suffixes de *Dungeonmans*.
- `Data.PREFIXES` (6 préfixes) + `Data.PREFIX_CHANCE` (Commun 12%, Rare 22%,
  Épique/Légendaire n'en tirent pas — ils gardent leur effet curé propre) +
  `Data._roll_prefix()` appelé depuis `_generate_procedural_item()`. Un
  préfixe ajoute son nom à celui de l'objet (ex. *Épée de Force du Brasier*)
  et pose `item.proc`/`proc_val`/`desc` exactement comme un objet unique —
  `Entity.recompute_stats()` les collecte déjà génériquement depuis
  n'importe quel slot équipé, donc aucun changement nécessaire côté Entity.
  `Data._proc_desc()` étendu avec les 6 nouveaux ids.
- 4 préfixes d'ARME (déclenchés dans `Main._trigger_weapon_prefixes()`,
  appelé depuis `_player_attack` juste après le vol de vie) : *Ardent* (dégâts
  de feu bonus instantanés via `_fire_prefix_damage()`, qui respecte
  `immune_fire`/`weak_fire` comme `apply_burn`), *Givre* (chance d'appliquer
  `slow`), *Venimeux* (chance d'appliquer `poison`), *Foudroyant* (chance
  d'appliquer `stun`, 1 tour). Réutilisent les helpers `apply_*` déjà
  génériques (entité-agnostiques) du reste du code.
- 2 préfixes d'ARMURE : *Rempart* (`cuirasse`, réduction plate de dégâts,
  repliée directement dans `Main._player_def()` — se propage automatiquement
  aux 5 points d'appel existants de `_player_def()`, y compris capacités de
  boss et pièges) et *Représailles* (`renvoi`, chance d'affaiblir
  l'attaquant au contact via `Main._trigger_armor_retaliation()`, appelé
  depuis `_enemy_hit_player` et `_enemy_ranged_attack`).
- Fix de cohérence au passage : l'écran de récompense de fin d'étage
  (`Main._make_floor_rewards()`) ne montrait jamais la description d'effet
  d'un objet (ni pour les uniques existants, ni pour les nouveaux préfixes)
  — seul un résumé de stats était affiché. Corrigé pour concaténer
  `item.desc` quand il existe.
- `_smoketest.gd` : génère 400 objets arme/armure et vérifie qu'au moins 3
  préfixes d'arme et 1 préfixe d'armure distincts apparaissent avec une
  desc non vide ; déclenche directement Ardent/Cuirasse/Renvoi sur un
  ennemi de test pour vérifier les dégâts de feu, la réduction de défense
  effective et le statut d'affaiblissement appliqué à l'attaquant.

## Ce qui reste à faire

### Revue de code (juillet 2026) — correctifs appliqués
Audit complet du code (logique + rendu/UI) et des idées implémentées, mené
via deux passes de relecture ciblées. Correctifs appliqués suite à l'audit :
- **Bug** : `Main._enemy_attack_player` appliquait le statut « au contact »
  (`ai.on_hit`) même quand tous les coups d'une séquence étaient esquivés
  (le `continue` sur esquive jetait la valeur de retour). Corrigé : le
  statut ne s'applique plus que si au moins un coup a réellement porté.
- **Design gap** : `RunMap._init(act, ...)` ignorait son paramètre `act` —
  la difficulté de carte (proportion Élite/Événement) était identique à
  toute strate. Corrigé alors dans `RunMap._roll_type()` ; **superseded**
  ci-dessous par le retrait complet de la carte à embranchements (la logique
  de scaling par `map_act` a été reportée dans `Main._roll_node_type()`).
- **Feature incomplète** : la Forge (nœud de l'arbre de Connaissances)
  choisissait au hasard une pièce d'équipement à renforcer, sans écran.
  Remplacée par un vrai écran `Hud.show_forge()` : le joueur choisit
  explicitement la pièce à renforcer (ou renonce). `Main._forge_equipment`
  scindé en `open_forge()` (ouvre l'écran) / `forge_choice(slot)` (renforce)
  / `forge_cancel()` (retour au feu de camp).
- **Code mort** : `Hud.equip_box` (VBoxContainer jamais ajouté à l'arbre,
  vestige d'une ancienne UI d'équipement texte) supprimé.
- **Doc obsolète** : README.md décrivait encore 3 héros nommés
  (Chevalier/Mage/Rôdeur) alors que le jeu suit une héroïne unique (Aria)
  dont le style dépend de l'arme équipée ; section et tableau réécrits.
  La liste « Pistes suivantes » de README.md (loot/statuts/variété
  d'ennemis) était elle aussi obsolète — remplacée par un résumé aligné sur
  les Phases 6/7/8 ci-dessous.

### Refonte de la progression — retrait de la carte à embranchements
Retour utilisateur : la carte de strate (choix du prochain nœud parmi 2-4,
façon *Slay the Spire*) sortait le joueur de l'immersion ; le vrai cœur du
jeu est l'exploration en temps réel de l'étage ouvert, pas la planification
méta d'un chemin. Décision : supprimer la carte, garder tout le reste
(boutique/événement/repos/récompense de fin d'étage/Forge inchangés dans
leur contenu) et enchaîner les étages automatiquement.
- **Suppression** : `scripts/RunMap.gd` (fichier supprimé), l'état
  `Main.State.MAP`, `Main.run_map`/`map_pos`/`reachable_indices()`/
  `choose_map_node()`/`_enter_node()`/`_start_act()`/`_back_to_map()`,
  et côté `Hud.gd` : `map_layer`/`map_root`/`_build_map()`/`show_map()`/
  `hide_map()`/`NODE_LABELS`/`NODE_COLORS`/`NODE_PLAIN`/`_node_icon()`
  (les PNG `assets/node_*.png` restent présents mais ne sont plus utilisés —
  suppression des fichiers non faite, à décider séparément).
- **Remplacement** : `Main._roll_node_type()` tire le type du prochain nœud
  (Combat/Élite/Boutique/Événement/Repos, Boutique et Événement rendus plus
  rares que dans l'ancienne carte — 8% chacun au lieu de 15% —, Repos monté
  à 11%, part Élite qui grandit avec `map_act` comme dans l'ancien scaling
  de `RunMap`) ; `Main._advance(forced_type)` enchaîne automatiquement vers
  ce nœud (ou l'affiche s'il s'agit d'un écran de pause). Un Gardien est
  garanti tous les `ACT_LENGTH` (5) étages réels via `Main.act_floor`, et le
  tout premier étage de chaque strate (après le run et après chaque Gardien)
  reste forcé en Combat, comme le faisait l'ancienne rangée 0 de `RunMap`.
  Une pause Repos/Boutique est elle aussi garantie une fois par acte juste
  avant le Gardien (`_act_rest_done`), pour reprendre la sécurité qu'offrait
  l'ancienne rangée pré-boss forcée de `RunMap` — sans elle, ~20% des actes
  auraient pu enchaîner 5 Combats/Élites d'affilée avant un Gardien à sec.
- Tous les anciens appels à `_back_to_map()` (fin de boutique/événement/
  repos/Forge/récompense de fin d'étage) redirigent maintenant vers
  `_advance()`. Un bug a été intercepté en cours de route : `Hud.show_game()`
  ne masquait pas `overlay_layer`, ce qui aurait laissé l'écran de boutique/
  récompense affiché par-dessus un étage généré juste après — corrigé en
  ajoutant `hud.hide_overlay()` en tête de `_advance()`.
- `_smoketest.gd` mis à jour : les runs démarrent directement en Combat
  (plus besoin de `choose_map_node`/`reachable_indices`), et un nouveau bloc
  teste explicitement `act_floor`/`ACT_LENGTH`/le forçage du Gardien et la
  remise à zéro après victoire.

### Écran-titre refondu (préparation de l'illustration Aria + Tour)
`Hud.show_title()` ne repose plus sur la colonne centrée générique
(`_menu_column`) mais construit sa propre composition en couches directement
dans `menu_root` :
- **Fond** : charge `res://assets/title_bg.png` s'il existe (`ResourceLoader.
  exists`), sinon monte `scripts/TitleBg.gd` — un `Control` procédural
  (tour en trapèzes empilés + fenêtres à halo + lune + étoiles + silhouette
  d'Aria au pied de la tour, dessinés en `_draw()`). Le jour où l'illustration
  finale est ajoutée dans `assets/`, elle prend le relais **sans changement
  de code**. `TitleBg.gd` reconnecte `resized` à `queue_redraw()` (le premier
  `_draw()` peut survenir avant que les ancres n'aient fini de résoudre la
  taille réelle).
- **Voiles de contraste** : deux dégradés (haut assombri pour le titre, bas
  assombri pour le menu) ancrés en `PRESET_TOP_WIDE`/`PRESET_BOTTOM_WIDE`
  avec un `offset` explicite (assigner `.size` seul sur un Control déjà ancré
  en `PRESET_FULL_RECT` — cas de `Ui.gradient_bg()` — est silencieusement
  écrasé par les ancres, piège rencontré et corrigé pendant l'implémentation).
- **Disposition** : logo en haut à gauche, bloc de boutons dans un panneau
  semi-transparent ancré en bas à droite (`PRESET_BOTTOM_RIGHT` +
  `grow_horizontal/vertical = GROW_DIRECTION_BEGIN` pour qu'il s'étende vers
  l'intérieur de l'écran plutôt qu'au-delà du bord), bandeau de profil (record
  d'ascension + Éclats + Connaissances, `_title_profile_strip()`) en bas à
  gauche — à la place de l'unique ligne de record précédente.
- **Mise à jour** : Godot 4.3 headless EST utilisable dans cet environnement
  (voir « Godot headless : comment ça marche ici » ci-dessous) — ce rendu a
  depuis été vérifié par une vraie capture d'écran, deux bugs visuels réels
  ont été trouvés et corrigés dans `TitleBg.gd` : le remplissage de la tour
  et le sol étaient bien assez sombres, mais le contraste de bord (silhouette
  quasi invisible sur fond de ciel déjà très sombre en bas de dégradé) et la
  silhouette d'Aria (couleur quasi identique à celle du sol) ne se voyaient
  presque pas. Corrigé en assombrissant encore la tour/le sol (toujours plus
  sombres que n'importe quel point du ciel) et en ajoutant un liseré clair
  (contre-jour lunaire, `TOWER_EDGE`/`ARIA_RIM`) qui dessine la forme par son
  contour plutôt que par contraste de remplissage — plus des halos de
  fenêtres et un halo au sol sous Aria agrandis pour rester visibles.

### Godot headless : comment ça marche ici
Le binaire Godot 4.3 n'est pas préinstallé, mais **peut être téléchargé et
exécuté** dans ce bac à sable (accès réseau sortant autorisé vers GitHub) :
```bash
curl -sSL -o godot.zip https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip
unzip -q godot.zip && chmod +x Godot_v4.3-stable_linux.x86_64
```
- **Premier lancement obligatoire** : faire un passage d'import du projet
  avant tout `--script`/scène, sinon les classes globales (`class_name Data`,
  `Entity`...) ne sont pas encore résolues et tout échoue en "Identifier not
  declared" : `./Godot... --headless --editor --quit --path .` (crée
  `.godot/`, à relancer si le cache est absent).
- **`_SmokeTest.tscn` tourne réellement** avec `--headless --path . res://_SmokeTest.tscn`
  une fois l'import fait — aucun display/GPU nécessaire pour la logique pure
  (assertions, simulation de tours). Deux bugs de FLAKINESS DE TEST (pas de
  bugs de jeu) ont été trouvés en le faisant tourner plusieurs fois de suite
  (le hasard du Pacte de Pouvoir en début de run change les résultats d'un
  run à l'autre) et corrigés :
  - « Serment de Fragilité » et « repos : entraînement » comparaient
    `player.atk`/`max_hp` (dérivés, faussés par l'arrondi d'un pouvoir en %
    comme Cœur de Verre) au lieu de `base_atk`/`base_max_hp` (le champ
    réellement muté) — comparaisons corrigées sur les champs de base.
  - Le test de comportement des 20 monstres pouvait voir un pouvoir Drone
    (hérité du Pacte de Pouvoir acheté plus haut dans le fichier) achever
    automatiquement un monstre fragile (Chauve-souris, 9 PV) avant la fin
    des 14 tours de test — `main.player.powers.clear()` ajouté pour isoler
    ce test.
- **Rendu RÉEL / captures d'écran** : `--headless` seul utilise un pilote de
  rendu factice (`get_viewport().get_texture()` renvoie null, aucun pixel
  produit) — utile pour la logique, pas pour vérifier visuellement l'UI.
  Pour un vrai rendu logiciel sans GPU/écran physique, Mesa llvmpipe est
  installé : lancer via `xvfb-run` (Xvfb dispo) SANS `--headless`, avec
  `--rendering-driver opengl3` :
  ```bash
  xvfb-run -a --server-args="-screen 0 1280x720x24" \
    ./Godot... --path . --script capture.gd --rendering-driver opengl3
  ```
  où `capture.gd` (`extends SceneTree`) instancie la scène, attend quelques
  `process_frame`, puis `root.get_texture().get_image().save_png(...)`. C'est
  ainsi que le screenshot de l'écran-titre ci-dessus a été obtenu et les deux
  bugs de contraste corrigés. Nettement plus lent qu'un pur `--headless`
  (rasterisation logicielle) mais fiable pour vérifier visuellement du GDScript
  UI/`_draw()` sans jamais avoir besoin d'un vrai GPU/écran.
- **Régénérer `assets/` avec `_assets_gen.gd`** (`--headless --script
  res://_assets_gen.gd`) produit les PNG mais PAS leurs `.import` — un
  nouveau fichier généré reste invisible à `load()` (repli silencieux sur
  texture nulle) tant qu'un passage d'import (`--headless --editor --quit`)
  n'a pas tourné après coup. Piège déjà rencontré une fois dans l'historique
  du projet, retombé dedans en générant les sprites de bâtiments du Hub.
- **`gen.py` (repli Python)** : maintenu à jour en parallèle de
  `_assets_gen.gd` (nouveaux `_gen_building_*`, `_new_sized`/`Img` à taille
  libre, `_px`/`_glow`/`_fade`/`_save` généralisés à `img.w`/`img.h`).
  Vérifié par diff pixel-à-pixel contre les PNG produits par le vrai Godot :
  identique pour 3 des 6 sprites, différences de quelques pixels (delta ≤2/255,
  imperceptible) pour les 3 autres, dues à `_glow()` qui utilisait `int()`
  au lieu de `floor`/`ceil` pour les bornes de boucle (corrigé) et à un écart
  résiduel connu et **non corrigé** : le `round()` de Python arrondit au pair
  le plus proche (banker's rounding) alors que celui de Godot arrondit
  toujours à l'écart de zéro sur les cas .5 exacts — écart préexistant dans
  tout le fichier (15+ appels à `round()`), pas introduit par ce chantier ;
  corriger ça partout demanderait de revérifier visuellement des dizaines de
  sprites déjà livrés, hors scope ici. Impact réel observé : 1 pixel de bord
  sur un des 6 sprites de bâtiment, imperceptible.

### Main Hub (Pied de la Tour) — infrastructure implémentée
Décisions actées avec l'utilisateur, puis construites (vérifiées par capture
d'écran réelle via Xvfb + Mesa llvmpipe, cf. section outillage plus haut) :
- **Style d'interaction** : ville explorable, Aria s'y déplace réellement
  (WASD/flèches, pas de tour par tour/combat) ; marcher sur la case d'un
  bâtiment déclenche automatiquement son écran, comme l'escalier en donjon.
- **`Town.gd`** (nouveau, `RefCounted`) : disposition FIXE dessinée à la main
  (17×13, pas de génération procédurale — c'est un lieu, pas un donjon) avec
  une croix de chemins reliant 6 bâtiments à la place centrale. `tiles`,
  `buildings` (`Vector2i -> {id,name,glyph,color}`), `is_walkable()`,
  `building_at()`, `player_start`.
- **`TownView.gd`** (nouveau, `Node2D`, calqué sur `MapView.gd` en plus
  simple) : pas de brouillard de guerre ni de caméra de suivi (la ville
  entière — 544×416px — tient dans les 1280×720 de la zone de jeu, centrée
  statiquement). Réutilise les textures du biome "plaine" (sol/arbre en
  bordure) et `road` pour rester cohérent visuellement sans nouveaux assets.
  Un rectangle de fond plein écran défensif évite qu'un rendu de donjon
  résiduel ne transparaisse dans les marges.
- **Sprites de bâtiments dédiés** (ajoutés après coup, sur demande) : 6
  nouveaux générateurs dans `_assets_gen.gd` (`_gen_building_<id>`,
  64×88 — 2×2 tuiles au sol, bien plus grand qu'une tuile 32×32 pour lire
  comme un vrai lieu et pas une icône), une silhouette générique commune
  (`_gen_building_base` : murs + toit + porte + fenêtres) que chaque
  bâtiment personnalise (Armurerie : écusson à épées croisées ; Bibliothèque :
  lucarne ronde lumineuse + livres empilés ; Sanctuaire : colonnes + lueur
  dorée au porche ; Forge : cheminée fumante + enclume devant l'entrée ;
  Boutique : auvent rayé + tonneau ; Porte de la Tour : arche de pierre avec
  la Tour entrevue au loin). Couleur reprise de `Town.buildings[].color`
  (chargé dynamiquement depuis `Town.gd` dans `_assets_gen.gd`, pas dupliqué).
  `TownView._blit_or_rect()` les dessine centrés sur la case du bâtiment,
  débordant vers le haut. **Fix nécessaire au passage** : `_px()`/`_glow()`
  étaient bornés en dur à `TILE` (32) — généralisé à `img.get_width()`/
  `get_height()` (comportement identique pour tous les sprites 32×32
  existants, permet aussi les sprites plus grands).
- **Piège rencontré** : après génération, `load("res://assets/building_*.png")`
  échouait silencieusement (repli sur rectangle coloré) tant qu'un passage
  d'import (`--headless --editor --quit`) n'avait pas tourné pour créer les
  `.import` — déjà rencontré une fois dans l'historique du projet ("Add
  missing .import files for new PNG assets").
- **`Main.gd`** : `State.HUB` ; `town`/`hub_pos`/`town_view` ; `enter_hub()`
  (crée la ville une seule fois, position conservée entre visites, bascule
  `map_view.visible`/`town_view.visible`) ; `_hub_try_move()` (bloqué par la
  bordure, comme un mur de donjon) ; `_hub_enter_building()` (dispatch par id).
  Nouveau mécanisme `_menu_return_state` (TITLE ou HUB) + `return_to_previous()` :
  les boutons "Retour" des écrans de Loadout/Sanctuaire/Connaissances
  utilisent maintenant `return_to_previous()` plutôt que `return_to_title()`
  en dur, pour ramener vers le Hub si c'est de là qu'on vient (l'écran de fin
  de run garde `return_to_title()` en dur : pas de détour par le Hub après un
  run, choix delibéré pour limiter la portée de cette passe).
- **`Hud.gd`** : `hub_layer` minimal (pas de sidebar de combat, rien à
  afficher hors-run) — bandeau d'indice + bouton "Menu principal" en coin,
  `show_hub()`, `show_hub_stub()` (écran "bientôt disponible" réutilisant
  `overlay_layer`, pour Forge/Boutique).
- **Bâtiments câblés** : Porte de la Tour + Armurerie → `open_loadout()` ;
  Bibliothèque → `open_knowledge()` ; Sanctuaire → `open_meta()` (écrans
  existants, inchangés, juste re-câblés). Forge et Boutique affichent un
  écran "bientôt disponible" — les concevoir (nouveaux systèmes : Forge =
  progression permanente, Boutique = cosmétique/confort) reste à faire, cf.
  décisions ci-dessous, conservées pour référence.
- **Écran-titre** : "Nouvelle Ascension" ouvre maintenant le Hub
  (`enter_hub()`) plutôt que le Loadout directement ; c'est en marchant
  jusqu'à la Porte de la Tour qu'on atteint l'écran de Loadout.
- **Bug de bord évité** : `map_view` et `town_view` sont deux `Node2D`
  toujours présents dans l'arbre (ni l'un ni l'autre n'est un `CanvasLayer`)
  — sans bascule explicite de `.visible`, un rendu de donjon résiduel
  d'un run précédent aurait pu transparaître dans les marges autour de la
  ville (plus petite que l'écran). Réglé en togglant `map_view.visible`/
  `town_view.visible` dans `_ready()`/`start_run()`/`enter_hub()`.
- **Test** : bloc dédié dans `_smoketest.gd` (déplacement, entrée de
  bâtiment, `return_to_previous()` contextuel HUB vs TITLE, bordure
  bloquante) + vérification visuelle par capture d'écran réelle (mêmes
  outils que pour l'écran-titre) : un bug de troncature de texte a été trouvé
  et corrigé ("Porte de la Tour" coupé en "Porte de la Tou" — largeur de
  boîte de `draw_string` insuffisante pour le nom le plus long).

Décisions encore valables pour la suite (Forge/Boutique restent à concevoir) :
- **Forge/Blacksmith** : nouveau système de progression permanente (pas un
  simple renommage du Sanctuaire) — dépense les Éclats banqués pour des
  déblocages durables (tiers de Forge en jeu améliorés, garantie de type de
  préfixe, nouveaux objets de départ...), distinct des bonus de stats plates
  du Sanctuaire.
- **Boutique du Hub** : vend des objets cosmétiques/de confort (palettes
  alternatives d'Aria, emplacement de sac supplémentaire) contre Éclats
  banqués — pas d'effet sur la puissance de combat.
- **Suivi ouvert (non bloquant)** : Armurerie et Porte de la Tour mènent
  toutes deux au même écran de Loadout — redondance mineure à reconsidérer
  une fois qu'on saura ce qu'Armurerie doit vraiment offrir de distinct
  (peut-être rien : c'est probablement correct tel quel, thématiquement).

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
