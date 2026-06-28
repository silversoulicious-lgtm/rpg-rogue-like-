# ⛫ Les Strates

Un **RPG roguelike tour-par-tour** où tu gravis une **tour géante façon Aincrad (Sword Art Online)**, étage par étage. À chaque mort, tu améliores tes capacités de façon permanente grâce au butin (Éclats) récolté dans le donjon.

> Prototype jouable développé sous **Godot 4.3**. Rendu par **sprites & textures pixel-art** générés par code (avec repli ASCII automatique si un asset manque).

---

## 🎮 Concept

- **Choisis un héros** au Pied de la Tour, puis grimpe.
- **Chaque étage est généré procéduralement** (salles + couloirs différents à chaque run).
- **Combat tactique tour-par-tour sur grille** : le positionnement compte.
- **Permadeath** : à la mort, le run s'arrête… mais tes Éclats vont en banque.
- **Méta-progression** : dépense tes Éclats pour des améliorations permanentes (PV, Attaque, puissance de capacité) qui rendent les runs suivants plus forts.
- **Loot procédural** : équipement généré aléatoirement avec **rareté** (Commun / Rare / Épique / Légendaire) et **affixes** (ex. *Hache du Vampire* : ATK+9, VIT−9, Vol de vie +6%). Les raretés montent avec l'étage.
- **Inventaire interactif** (`I`) : un vrai sac — ramasse plusieurs objets, compare, équipe/déséquipe, recycle en Éclats, et utilise des **consommables** (potions, cristaux).
- **Montée de niveau & talents** : gagne de l'XP en tuant ; à chaque niveau, choisis 1 **talent** parmi 3 (build émergent à la *Hades*).
- **Artefacts** ramassés dans le donjon : **capacités spéciales passives** (vol de vie, épines, critique, esquive, résurrection).
- **Système de vitesse** : la stat Vitesse régit l'économie de tours (être rapide = agir plus souvent).
- **Boss** : un *Gardien de l'Étage* apparaît tous les 5 étages.

## 🖥️ Interface

- **Zone de jeu** (gauche) : la grille où l'on contrôle son personnage.
- **Sidebar permanente** (droite), toujours visible : titre, étage, héros,
  barre de PV, **statistiques** détaillées (ATK / MAG / DEF / VIT / Régén /
  Éclats / Banque), état de la **capacité**, **page Équipement** (3 slots avec
  leurs bonus) et **page Artefacts** (avec descriptions).
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

**Rareté & affixes** : chaque objet a une rareté qui détermine le nombre d'affixes aléatoires en plus de sa stat de base :

| Rareté | Affixes | Couleur |
|---|---|---|
| Commun | 0 | gris |
| Rare | 1 | bleu |
| Épique | 2 | violet |
| Légendaire | 3 | or |

Les affixes peuvent ajouter : ATK, MAG, DEF, VIT, PV, Régén, mais aussi Critique, Esquive, Vol de vie ou Épines. Ouvre l'inventaire (`I`) pour équiper, comparer, recycler et utiliser des consommables.

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
  Main.gd              Contrôleur : flux d'écrans, tour-par-tour, combat, IA
  GameState.gd         Autoload : méta-progression persistante + sauvegarde
  Data.gd              Données (héros, ennemis, boss, améliorations)
  Dungeon.gd           Génération procédurale (salles + couloirs)
  Entity.gd            Entité de grille (héros / ennemi)
  MapView.gd           Rendu par tuiles : textures + sprites (repli ASCII)
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
- Étages thématiques (façon « strates » d'Aincrad) avec biomes visuels / palettes de textures par strate.
- Animations (déplacement, attaque, dégâts).
- Sons et musique.

---

*Direction créative : medieval-fantasy, tour d'Aincrad. Développement : itératif.*
