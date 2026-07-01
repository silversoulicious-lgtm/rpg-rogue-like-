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

1. **Forge du Hub** — nouveau système de progression permanente (pas un
   renommage du Sanctuaire) : dépense les Éclats banqués pour des
   déblocages durables (tiers de Forge in-run améliorés, garantie de type
   de préfixe, nouveaux objets de départ...).
2. **Boutique du Hub** — objets cosmétiques/de confort (palettes d'Aria,
   emplacement de sac supplémentaire) contre Éclats banqués, sans effet sur
   la puissance de combat.
3. **Phase 6 — Dialogues/PNJ** : système de dialogue aux nœuds
   événement/boutique/repos, portraits, choix liés aux Serments/Connaissances.
4. **Phase 7 — Lore + fins multiples** : texte de lore par étages/Codex,
   plusieurs fins selon progression/Serments/% Codex complété.
5. **Phase 8 — Finition** : équilibrage (dégâts/HP/drop/coût des nœuds),
   polish UI/UX, sons/musique, écran titre/crédits.
6. **Suivis mineurs (non bloquants)** :
   - Sprites directionnels pour les ennemis (seule Aria en a).
   - Variantes teintées pour les ennemis élite, sprite distinct pour le
     boss légendaire (actuellement `boss` générique).
   - Représentation visuelle des pouvoirs actifs en combat (juste listés
     en sidebar texte).
   - Armurerie et Porte de la Tour mènent toutes deux au même écran de
     Loadout — redondance mineure, probablement correcte telle quelle.
   - Nettoyage de 3 branches GitHub redondantes (ancêtres fusionnés de la
     branche actuelle), bloqué sur un changement de branche par défaut
     à faire depuis les Settings GitHub (hors accès outillé).
