# ⛫ Les Strates

Un **RPG roguelike tour-par-tour** où tu gravis une **tour géante façon Aincrad (Sword Art Online)**, étage par étage. À chaque mort, tu améliores tes capacités de façon permanente grâce au butin (Éclats) récolté dans le donjon.

> Prototype jouable développé sous **Godot 4.3**. Rendu par **sprites & textures pixel-art** générés par code (avec repli ASCII automatique si un asset manque).

---

## 🎮 Concept

- **Choisis un héros** au Pied de la Tour, puis grimpe.
- **Carte de strate à embranchements** (façon *Slay the Spire*) : à chaque pas, choisis ta voie parmi des salles — Combat, **Élite** (dur, meilleur butin), **Boutique**, **Événement** (risque/récompense), **Repos**, et le **Gardien** au sommet de chaque strate.
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

## 🦸 Héros

| Héros | Style | Capacité |
|---|---|---|
| **Chevalier** | Robuste, corps-à-corps | *Tourbillon d'acier* — frappe tous les ennemis adjacents |
| **Mage** | Fragile, distance | *Éclair foudroyant* — foudroie l'ennemi le plus proche |
| **Rôdeur** | Polyvalent | *Tir précis* — flèche puissante à distance |

## 🛡️ Équipement & Artefacts

Le butin apparaît au sol et se ramasse en marchant dessus.

**Équipement** (3 slots, améliore les stats principales) :
| Slot | Glyphe | Améliore surtout |
|---|---|---|
| Arme `/` | orange | Attaque, Magie, Vitesse |
| Armure `]` | bleu | Défense, PV max |
| Relique `=` | vert | Vitesse, Régén PV, mixte |

L'équipement s'équipe automatiquement s'il est meilleur que l'actuel ; l'ancien est recyclé en Éclats.

**Rareté** : Commun et Rare restent **procéduraux** (stats de base + 0 ou 1 affixe aléatoire parmi ATK, MAG, DEF, VIT, PV, Régén, Critique, Esquive, Vol de vie, Épines) — c'est le loot courant.

Épique et Légendaire ne sont plus de simples "stats plus grosses" : ils puisent dans une **bibliothèque de 100+ objets uniques nommés**, chacun porteur d'un **effet de combat distinct** en plus de ses stats fixes. Le Légendaire est la version amplifiée (stats ×1.4, effet ×1.3, épithète) de la même identité que son pendant Épique.

| Rareté | Origine | Couleur |
|---|---|---|
| Commun | procédural, 0 affixe | gris |
| Rare | procédural, 1 affixe | bleu |
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

Ouvre l'inventaire (`I`) pour équiper, comparer, recycler et utiliser des consommables — l'effet de chaque objet unique est affiché sous ses stats.

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
  RunMap.gd            Carte de strate à embranchements (graphe en couches)
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

- Objets/équipement à ramasser pendant le run (armes, armures, sorts).
- Plus d'archétypes d'ennemis et de comportements d'IA (à distance, fuite, invocation).
- Intentions ennemies télégraphiées + variété d'IA (archers, invocateurs) — façon *Into the Breach*.
- Effets de statut & éléments (poison, brûlure, gel, étourdissement).
- Davantage de synergies, sets d'équipement, davantage de biomes.
- Brouillard de guerre par **ligne de vue** (les arbres/rochers bloquent la vision) plutôt que par simple rayon.
- Feedback visuel dédié par proc en combat (auras, particules, texte flottant).
- Animations (déplacement, attaque, dégâts), sons et musique.

---

*Direction créative : medieval-fantasy, tour d'Aincrad. Développement : itératif.*
