# ⛫ Les Strates

Un **RPG roguelike tour-par-tour** où tu gravis une **tour géante façon Aincrad (Sword Art Online)**, étage par étage. À chaque mort, tu améliores tes capacités de façon permanente grâce au butin (Éclats) récolté dans le donjon.

> Prototype jouable développé sous **Godot 4.3**. Rendu par **sprites & textures pixel-art** générés par code (avec repli ASCII automatique si un asset manque).

---

## 🎮 Concept

- **Choisis un héros** au Pied de la Tour, puis grimpe.
- **Progression linéaire et rythmée** : pas de carte à choisir, l'ascension s'enchaîne directement d'un étage au suivant — Combat, **Élite** (plus rare, plus dur, meilleur butin), **Boutique**, **Événement** (risque/récompense) et **Repos** sont tirés au sort (Boutique/Événement volontairement rares : ce sont des pauses, pas le cœur du jeu). Un **Gardien** garanti t'attend tous les 5 étages réels ; le premier étage de chaque strate est toujours un Combat, histoire de souffler après le précédent Gardien.
- **Étages « open world »** : chaque combat se déroule sur une **carte ouverte** générée procéduralement, parsemée d'**arbres, rochers, étendues d'eau, routes et décor**. La caméra suit le héros : on **explore** vraiment l'étage pour trouver l'escalier. La **taille est ré-échantillonnée à chaque étage** (distribution triangulaire) : la plus fréquente est **320×200**, la minuscule **64×40** et l'immense **640×400** restant rares. Le nombre d'ennemis et de butin s'adapte à la surface pour qu'une grande carte ne soit jamais vide.
- **Biomes** : tous les ~12 étages, on entre dans un **biome différent** qui change la palette, le terrain et les sprites — *Plaines verdoyantes*, *Forêt profonde*, *Désert de cendres dorées*, *Toundra gelée*, *Marais putride*, *Terres de feu*.
- **Brouillard de guerre** : la vision est limitée à un **cercle autour du héros** (stat *Vision*). Les zones non vues sont noires, les zones déjà explorées restent en mémoire (assombries) mais ennemis et butin n'apparaissent que dans le champ de vision. La portée de Vision s'améliore via les talents **Clairvoyance** (+1) et **Œil de Lynx** (+2).
- **Combat tactique tour-par-tour sur grille** : le positionnement compte.
- **Permadeath** : à la mort, le run s'arrête… mais tes Éclats vont en banque, et un **journal de fin de run** récapitule ton exploit (étage atteint, ennemis vaincus, meilleur coup, objet le plus marquant) avec des records persistants.
- **Méta-progression** : dépense tes Éclats pour des améliorations permanentes (PV, Attaque, puissance de capacité, mais aussi **Fortune** = Éclats de départ, **Héritage** = artefact de départ, **Instinct** = talent de départ) qui rendent les runs suivants plus forts. Chaque amélioration est plafonnée pour ne pas trivialiser le jeu.
- **Synergies inter-procs** : combine deux objets uniques aux effets complémentaires pour activer une synergie nommée (ex. *Rage Sanguinaire* : Soif de Sang + Frénésie) qui **amplifie** les deux procs. Les synergies actives sont affichées dans la sidebar.
- **Loot procédural** : équipement généré aléatoirement avec **rareté** (Commun / Rare / Épique / Légendaire) et **affixes** (ex. *Hache du Vampire* : ATK+9, VIT−9, Vol de vie +6%). Les raretés montent avec l'étage.
- **Inventaire interactif** (`I`) : un vrai sac — ramasse plusieurs objets, compare, équipe/déséquipe, recycle en Éclats, et utilise des **consommables** (potions, cristaux).
- **Montée de niveau & talents** : gagne de l'XP en tuant ; à chaque niveau, choisis 1 **talent** parmi 3 (build émergent à la *Hades*).
- **Artefacts** ramassés dans le donjon : **capacités spéciales passives** (vol de vie, épines, critique, esquive, résurrection).
- **Système de vitesse** : la stat Vitesse régit l'économie de tours (être rapide = agir plus souvent).
- **Boss** : un *Gardien de l'Étage* garde le sommet de chaque strate. Il se **régénère** et entre en **RAGE** sous 50% PV (dégâts accrus) ; le vaincre lâche un **butin garanti Épique+** (objet unique nommé).

## 🖥️ Interface

- **Zone de jeu** (gauche) : la grille où l'on contrôle son personnage.
- **Sidebar permanente** (droite), toujours visible : titre, étage, héros,
  barre de PV, **statistiques** détaillées (ATK / MAG / DEF / VIT / Régén /
  **Vision** / Éclats / Banque), le **biome courant**, état de la **capacité**,
  **page Équipement** (3 slots avec leurs bonus), **page Artefacts** (avec
  descriptions) et **page Synergies** (synergies de procs actuellement actives).
- **Journal de combat** (bas) : les derniers événements.

## 🕹️ Contrôles

| Action | Touches |
|---|---|
| Se déplacer / attaquer | `WASD`, flèches, ou `HJKL` |
| Utiliser la capacité | `ESPACE` (ou `E`) |
| Attendre un tour | `.` |
| Ouvrir / fermer l'inventaire | `I` (ou `Échap` pour fermer) |

Se déplacer **dans** un ennemi l'attaque. Marcher sur l'escalier `>` monte d'un étage.

## 🦸 Héroïne

Une **héroïne unique, Aria**. Son style de combat n'est pas figé par une
classe : il dépend de l'**arme équipée** (mêlée / distance / magie), qui
détermine sa compétence active de base et sa passive de type.

| Type d'arme | Style | Capacité de base |
|---|---|---|
| **Mêlée** | Robuste, corps-à-corps | *Tourbillon d'acier* — frappe tous les ennemis adjacents |
| **Magie** | Fragile, distance | *Éclair foudroyant* — foudroie l'ennemi le plus proche |
| **Distance** | Polyvalent | *Tir précis* — flèche puissante à distance |

D'autres compétences (Commune/Rare/Épique) se droppent en jeu et remplacent
la compétence active selon le type d'arme porté.

## 🛡️ Équipement & Artefacts

Le butin apparaît au sol et se ramasse en marchant dessus.

**Équipement** (3 slots, améliore les stats principales) :
| Slot | Glyphe | Améliore surtout |
|---|---|---|
| Arme `/` | orange | Attaque, Magie, Vitesse |
| Armure `]` | bleu | Défense, PV max |
| Relique `=` | vert | Vitesse, Régén PV, mixte |

Le butin ramassé va dans le sac ; ouvre l'inventaire (`I`) pour l'équiper — l'ancien objet du slot repart dans le sac (ou est recyclé en Éclats si le sac est plein).

**Rareté** : Commun et Rare restent **procéduraux** (stats de base + 0 ou 1 affixe aléatoire parmi ATK, MAG, DEF, VIT, PV, Régén, Critique, Esquive, Vol de vie, Épines) — c'est le loot courant.

Épique et Légendaire ne sont plus de simples "stats plus grosses" : ils puisent dans une **bibliothèque de 100+ objets uniques nommés**, chacun porteur d'un **effet de combat distinct** en plus de ses stats fixes. Le Légendaire est la version amplifiée (stats ×1.4, effet ×1.3, épithète) de la même identité que son pendant Épique.

| Rareté | Origine | Couleur |
|---|---|---|
| Commun | procédural, 0 affixe, chance de préfixe de combat | gris |
| Rare | procédural, 1 affixe, chance de préfixe de combat | bleu |
| Épique | objet unique nommé + 1 effet de combat | violet |
| Légendaire | objet unique amplifié + 1 effet de combat renforcé | or |

Effets de combat possibles sur les objets uniques :
| Effet | Description |
|---|---|
| Exécution | Bonus de dégâts contre une cible sous 25% PV |
| Frénésie | Bonus de dégâts quand le porteur est sous 40% PV |
| Premier Coup | La 1re attaque de chaque combat est un critique garanti |
| Frappe Double | Chance de frapper une 2e fois (50% dégâts) |
| Soif de Sang | Soigne un % des PV max à chaque ennemi tué |
| Moisson | Éclats bonus à chaque ennemi tué |

**Préfixes de combat** (inspirés de *Dungeonmans*) : même un objet Commun ou Rare peut tirer, en plus de son affixe de stat, un préfixe qui ajoute un **effet de combat** à son nom (ex. *Épée de Force du Brasier*). Indépendants de la bibliothèque d'objets uniques, ils rendent le loot courant plus intéressant sans l'égaler en puissance — Rare a plus de chances qu'un Commun d'en tirer un (22% contre 12%), et leur magnitude grandit un peu avec l'étage.

| Préfixe | Slot | Effet |
|---|---|---|
| du Brasier | Arme | Dégâts de feu bonus à chaque attaque (~3 à 9 selon l'étage) |
| du Givre | Arme | Chance de ralentir la cible touchée |
| du Venin | Arme | Chance d'empoisonner la cible touchée |
| de la Foudre | Arme | Chance d'étourdir la cible touchée (1 tour) |
| du Rempart | Armure | Réduit chaque coup subi d'un montant fixe |
| des Représailles | Armure | Chance d'affaiblir un attaquant au contact |

Ouvre l'inventaire (`I`) pour équiper, comparer, recycler et utiliser des consommables — l'effet de chaque objet unique ou préfixe est affiché sous ses stats.

**Artefacts** `✦` (capacités spéciales passives, cumulables) :
| Artefact | Effet |
|---|---|
| Calice de Sang | Vol de vie : soigne 30% des dégâts infligés |
| Carapace d'Épines | Renvoie des dégâts aux attaquants |
| Croc Sauvage | 25% de coups critiques (x2) |
| Voile d'Ombre | 20% d'esquive |
| Plume de Phénix | Ressuscite une fois à 50% PV |

## ▶️ Lancer le jeu

1. Installe [Godot 4.3+](https://godotengine.org/download).
2. Ouvre Godot → *Importer* → sélectionne le fichier `project.godot` de ce dépôt.
3. Appuie sur **F5** (ou le bouton ▶).

## 🧱 Architecture

```
project.godot          Config du projet + autoload GameState
scenes/Main.tscn       Scène principale (porte le contrôleur)
scripts/
  Main.gd              Coordinateur : état, génération, combat, tour-par-tour, IA
  Hud.gd               Toute l'interface : sidebar, journal, hub, overlays
  Ui.gd                Fabrique de widgets (label/button/styles) anti-boilerplate
  GameState.gd         Autoload : méta-progression persistante + sauvegarde
  Data.gd              Données (héros, ennemis, objets procéduraux, talents…)
  Dungeon.gd           Génération du terrain open-world biome + brouillard de guerre
  Entity.gd            Entité de grille + stats dérivées (héros / ennemi)
  MapView.gd           Rendu par tuiles biome + brouillard + caméra (repli ASCII)
assets/                Sprites & textures pixel-art (PNG 24x24, générés)
_assets_gen.gd         Générateur d'assets (régénère assets/ par code)
_smoketest.gd          Test de fumée headless (pilote une partie complète)
```

### Régénérer les assets (sprites & textures)

Tous les visuels sont générés par code dans `_assets_gen.gd`. Pour les
recréer (après avoir modifié les couleurs/formes) :

```bash
godot --headless --path . --script res://_assets_gen.gd
```

### Tester sans interface (headless)

```bash
godot --headless --path . res://_SmokeTest.tscn
```
Doit afficher `=== SMOKETEST PASSED ===`.

## 🗺️ Pistes suivantes

- **Dialogues / PNJ** : système de dialogue aux nœuds événement/boutique/repos, portraits, choix simples liés aux Serments/Connaissances.
- **Lore + fins multiples** : texte de lore distillé par étages/découvertes du Codex, plusieurs fins selon la progression, les Serments actifs et le % de Codex complété.
- **Finition** : équilibrage final (courbes de dégâts/HP, taux de drop, coût des nœuds de l'arbre), polish UI/UX, sons/musique, écran titre/crédits.
- Sprites directionnels pour les ennemis (actuellement seule Aria en a).
- Variantes teintées pour les ennemis élite, sprite distinct pour le boss légendaire.
- Représentation visuelle des pouvoirs actifs en combat (auras, particules, texte flottant).
- Brouillard de guerre par **ligne de vue** (les arbres/rochers bloquent la vision) plutôt que par simple rayon.

---

*Direction créative : medieval-fantasy, tour d'Aincrad. Développement : itératif.*
