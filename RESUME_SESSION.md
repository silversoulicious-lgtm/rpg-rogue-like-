# Les Strates — Récapitulatif du projet (à jour)

Roguelike au tour par tour en Godot 4.3 / GDScript. Une héroïne unique (Aria),
build par arme, ascension linéaire d'une tour à étages (RNG, pas de carte à
embranchements). Séparation stricte logique/affichage/données : `Main.gd`
(logique), `Hud.gd` (affichage), `Data.gd` (registre de données), `Entity.gd`
(modèle pur), `GameState.gd` (autoload, sauvegarde JSON `user://save.json`).

## Ce qui est fait

- **Combat tour par tour** sur grille (énergie/vitesse, `Entity.ACTION_COST`),
  statuts (poison, saignement, maladie, affaiblissement, confusion,
  ralentissement, étourdissement, brûlure).
- **Étages open-world procéduraux** (`Dungeon.gd`) : 6 biomes, brouillard de
  guerre, tailles variables, décor/props/POI rares.
- **Progression linéaire des étages** (`Main._roll_node_type()`/`_advance()`) :
  Combat/Élite/Boutique/Événement/Repos tirés au sort à la suite (Boutique et
  Événement rares, 8% chacun), Gardien garanti tous les `ACT_LENGTH` (5)
  étages réels, pause Repos/Boutique garantie juste avant, 1er étage de
  chaque strate forcé en Combat. Plus de carte à embranchements
  (`RunMap.gd` supprimé, l'ancienne UI carte aussi).
- **Build par arme** (mêlée/distance/magie) : compétences actives
  data-driven (`Data.SKILLS`), talents de niveau (build à la Hades).
- **Loot procédural** : Commun→Rare→Épique→Légendaire, 100+ objets uniques
  nommés avec effet de combat (Épique/Légendaire), **6 préfixes de combat**
  façon *Dungeonmans* sur objets Commun/Rare (`Data.PREFIXES` : Ardent,
  Givre, Venimeux, Foudroyant côté arme ; Cuirasse, Renvoi côté armure).
- **Pouvoirs passifs** cumulables (Drone, Tourelle, Cœur de Verre,
  Détonation, Venin) + **synergies** inter-procs nommées.
- **Méta-progression** : Sanctuaire (stats permanentes), Arbre de
  Connaissances (2ᵉ monnaie, débloque des règles/systèmes en DAG avec
  prérequis — pas de simples +stats), Serments (risque/récompense
  optionnels), Codex (catalogue des découvertes), Forge in-run (renforce une
  pièce d'équipement au feu de camp, débloquée par l'Arbre).
- **Bestiaire** : 20 monstres + 10 boss (`Entity.ai`, comportements
  data-driven : mêlée/charge/distance/invocateur/fuite/téléporteur/embuscade),
  mécaniques boss variées (gardiens protecteurs, ponte, phases, charge,
  souffle, copie du joueur...).
- **Identité visuelle** "Les Strates" façon Moonring : palette néon
  restreinte, glow/bloom, dithering Bayer, sprites 32×32 générés par code
  (`_assets_gen.gd`, mirroré par `gen.py` en repli Python). Aria a des vues
  directionnelles (face/dos/profil). Ambiance en jeu : pool de torche +
  vignette (`MapView.gd`).
- **Écran-titre refondu** : composition en couches (logo/menu/profil),
  silhouette procédurale de repli (`TitleBg.gd`) tant que
  `assets/title_bg.png` n'existe pas — bascule automatique sans code dès
  que l'illustration finale sera ajoutée.
- **Main Hub explorable** (Pied de la Tour) : `Town.gd` (disposition fixe,
  6 bâtiments) + `TownView.gd` (rendu, sans brouillard/caméra de suivi),
  Aria s'y déplace librement (WASD). Sprites de bâtiments dédiés générés
  (`_gen_building_*`, 64×88, silhouette + détail par bâtiment : écusson,
  lucarne, colonnes, cheminée, auvent, arche). Armurerie/Porte de la Tour →
  Loadout, Bibliothèque → Connaissances, Sanctuaire → Sanctuaire (écrans
  existants re-câblés) ; **Forge et Boutique en écran "bientôt disponible"**
  (nouveaux systèmes pas encore conçus, cf. TODO). Écran-titre "Nouvelle
  Ascension" → Hub ; "Retour" contextuel (Hub ou Titre selon la provenance)
  via `Main.return_to_previous()`.
- **`_smoketest.gd`** : couvre tous les systèmes ci-dessus (pouvoirs,
  Connaissances, Serments, Codex, Forge, récompenses de fin d'étage, sprites
  directionnels, 20 monstres + 10 boss, préfixes de combat, Hub).

## Outillage

- **Godot 4.3 headless fonctionne dans ce bac à sable** (téléchargeable
  depuis GitHub, réseau sortant autorisé) :
  ```bash
  curl -sSL -o godot.zip https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip
  unzip -q godot.zip && chmod +x Godot_v4.3-stable_linux.x86_64
  ```
  Premier lancement obligatoire pour peupler le cache de classes globales :
  `./Godot... --headless --editor --quit --path .` (à relancer si un
  fichier "Identifier not declared" apparaît, ou après avoir généré de
  nouveaux PNG — sans repasse d'import, les nouveaux fichiers restent
  invisibles à `load()`, repli silencieux). `_SmokeTest.tscn` tourne
  ensuite avec `--headless --path . res://_SmokeTest.tscn`.
  **Note (Phase 1)** : indisponible dans certains bacs à sable dont la
  politique réseau bloque `github.com` (téléchargement du binaire refusé,
  403) — c'était le cas pour la session qui a implémenté la Phase 1 ;
  les corrections et leurs asserts de régression ont été revus
  manuellement mais **pas exécutés**. À lancer en priorité dans un
  environnement qui a l'accès réseau avant de fusionner/poursuivre.
- **Rendu réel / captures d'écran** : `--headless` seul utilise un pilote
  factice (aucun pixel produit). Pour un vrai rendu logiciel sans GPU,
  Mesa llvmpipe est installé : lancer via `xvfb-run` SANS `--headless`,
  avec `--rendering-driver opengl3` ; un script `extends SceneTree` qui
  instancie la scène, attend quelques `process_frame`, puis
  `root.get_texture().get_image().save_png(...)`. Plus lent qu'un pur
  `--headless` mais seule façon fiable de vérifier visuellement de l'UI/du
  `_draw()`.
- **`gen.py`** (repli Python, mêmes primitives que `_assets_gen.gd`) tenu à
  jour en parallèle. Écart connu et non bloquant : le `round()` de Python
  (arrondi au pair) diffère de celui de Godot (arrondi à l'écart de zéro)
  sur les cas .5 exacts — préexistant dans tout le fichier, impact
  observé : 1 pixel de bord sur de rares sprites, imperceptible.

## Ce qui reste à faire

La feuille de route détaillée (algorithmes, points d'intégration, pièges,
asserts par tâche) vit désormais dans `IMPLEMENTATION_GUIDE.md` — exécutée
phase par phase, avec `AUDIT.md`/`VISION.md`/`ART_GENERATOR_SPEC.md` en
appui. Elle **remplace** la liste ad hoc ci-dessous (numérotation différente,
ne pas les confondre).

- **Phase 1 — Corrections de bugs confirmés : FAITE.** floor_num
  démarrait à 2 au lieu de 1 ; le pouvoir garanti du boss ne tombait
  jamais (condition `floor_num % 15` sur un multiple impossible, remplacée
  par `run_bosses % 2`) ; le statut *weaken* n'affaiblissait pas les
  ennemis (préfixe Représailles inerte) ; les gardiens-boucliers de boss
  pouvaient apparaître n'importe où sur la carte et restaient en vie après
  la mort du boss (désormais rayon 6 + dissipation) ; esquive/critique/vol
  de vie n'étaient pas plafonnés (immortalité possible par cumul) ; la
  Forge amplifiait aussi les maluses d'objet ; les contrôles étaient liés
  au caractère du clavier (cassés en AZERTY, remplacés par des actions
  liées à la touche physique) ; aucune pause ni moyen d'abandonner un run
  proprement (ajout d'un état PAUSED + abandon avec pénalité d'Éclats) ;
  l'UI supposait un viewport fixe 1280×720 (sidebar/journal désormais
  ancrés, recalés au redimensionnement) ; le Serment de Pauvreté laissait
  filtrer le bonus de départ du Pacte de Pouvoir. Asserts de régression
  ajoutés dans `_smoketest.gd` pour les dix ; README corrigé (sprites
  32×32, Gardien tous les 6 étages réels).
- **Phase 2 — Équité du combat : FAITE.** `Dungeon.has_los` (Bresenham) partagée
  entre l'auto-visée joueuse et les tirs/cris ennemis (plus de tir depuis le
  néant, plus de mimic détecté à travers un mur) ; `BASE_VISION` 4→6 pour
  couvrir les tireurs à portée 7 ; zone d'agro (`Entity.awake`, IA plus
  omnisciente : un ennemi dort jusqu'à être vu/blessé/à portée d'agro, ou
  alerté par le cri d'un voisin réveillé — mimics jamais criés ni réveillés) ;
  évitement d'obstacle minimal partout (`_enemy_step_toward` tente les deux
  perpendiculaires à l'axe dominant) + A* (`Dungeon.next_step`) pour
  boss/élites (`ai.smart_path`) ; intentions ennemies télégraphiées
  (`Main.enemy_intent`, icône coin haut-droit dans `MapView`) ; bande d'ordre
  des tours au-dessus du journal (`Main.preview_turn_order`, simulation pure) ;
  panneau d'inspection au survol souris (`MapView.tile_at_mouse` →
  `Hud.show_inspect`, section INSPECTION dans la sidebar). Asserts de
  régression ajoutés dans `_smoketest.gd` pour les sept.
- **Phase 3 — Feel & polish : FAITE sauf 3.1 (police pixel, différée).**
  Effets sonores procéduraux (`_sfx_gen.gd` → `assets/sfx/*.wav`, 10
  recettes synthétisées PCM16 ; autoload `Sfx` en tourniquet ; hooks coup/
  critique/mort/butin/niveau/escalier/achat/soin/bouton) ; réglages
  persistants (`GameState.settings` : sfx_vol/music_vol/screenshake, écran
  Options) ; mouvement/combat "juice" dans `MapView` (glissé `_vis_pos`,
  nombres de dégâts/soin flottants, hit-stop bref au critique, tremblement
  de caméra sur critique/rage de boss — tout dans le rendu, la logique reste
  instantanée) ; réactivité des entrées (mouvement en polling
  `Main._process` avec délai initial + répétition, focus clavier automatique
  sur le 1er bouton de chaque overlay) ; météo d'ambiance par biome
  (`Data.BIOMES[*].ambient`, particules en espace écran) ; récap de mort
  (source du coup fatal, écart au record, chronologie du run) ; journal
  étendu à 200 lignes avec défilement, runs à seed reproductible
  (`start_run(loadout, seed)`, affichée pause/journal), RNG de gameplay
  unifiée sur `Main.rng` (tirage de talents sans doublon). Asserts de
  régression ajoutés dans `_smoketest.gd`.
  **3.1 (police pixel bitmap CC0/générée) différée** : pas d'accès réseau
  pour vendorer une police CC0, et générer une police pixel lisible à la
  main sans jamais pouvoir la voir rendue est trop risqué (texte illisible
  possible sur TOUTE l'UI) — à faire dans une session avec accès à Godot
  pour itérer visuellement.
- **Phases 4 à 8** (terrain élémentaire, équilibrage, contenu, hygiène
  d'ingénierie, direction artistique 64×64) : à faire, voir
  `IMPLEMENTATION_GUIDE.md` pour le détail.
- **Suivis mineurs (non bloquants, hérités de l'ancienne liste)** :
  - Sprites directionnels pour les ennemis (seule Aria en a).
  - Variantes teintées pour les ennemis élite, sprite distinct pour le
    boss légendaire (actuellement `boss` générique).
  - Armurerie et Porte de la Tour mènent toutes deux au même écran de
    Loadout — redondance mineure, probablement correcte telle quelle.
  - Nettoyage de 3 branches GitHub redondantes (ancêtres fusionnés de la
    branche actuelle), bloqué sur un changement de branche par défaut
    à faire depuis les Settings GitHub (hors accès outillé).
