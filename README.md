# ⛫ Les Strates

Un **RPG roguelike tour-par-tour** où tu gravis une **tour géante façon Aincrad (Sword Art Online)**, étage par étage. À chaque mort, tu améliores tes capacités de façon permanente grâce au butin (Éclats) récolté dans le donjon.

> Prototype jouable développé sous **Godot 4.3**. Rendu ASCII-roguelike (aucun asset requis), 100% remplaçable par des sprites plus tard.

---

## 🎮 Concept

- **Choisis un héros** au Pied de la Tour, puis grimpe.
- **Chaque étage est généré procéduralement** (salles + couloirs différents à chaque run).
- **Combat tactique tour-par-tour sur grille** : le positionnement compte.
- **Permadeath** : à la mort, le run s'arrête… mais tes Éclats vont en banque.
- **Méta-progression** : dépense tes Éclats pour des améliorations permanentes (PV, Attaque, puissance de capacité) qui rendent les runs suivants plus forts.
- **Boss** : un *Gardien de l'Étage* apparaît tous les 5 étages.

## 🕹️ Contrôles

| Action | Touches |
|---|---|
| Se déplacer / attaquer | `WASD`, flèches, ou `HJKL` |
| Utiliser la capacité | `ESPACE` (ou `E`) |
| Attendre un tour | `.` |

Se déplacer **dans** un ennemi l'attaque. Marcher sur l'escalier `>` monte d'un étage.

## 🦸 Héros

| Héros | Style | Capacité |
|---|---|---|
| **Chevalier** | Robuste, corps-à-corps | *Tourbillon d'acier* — frappe tous les ennemis adjacents |
| **Mage** | Fragile, distance | *Éclair foudroyant* — foudroie l'ennemi le plus proche |
| **Rôdeur** | Polyvalent | *Tir précis* — flèche puissante à distance |

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
  MapView.gd           Rendu ASCII via _draw()
_smoketest.gd          Test de fumée headless (pilote une partie complète)
```

### Tester sans interface (headless)

```bash
godot --headless --path . res://_SmokeTest.tscn
```
Doit afficher `=== SMOKETEST PASSED ===`.

## 🗺️ Pistes suivantes

- Objets/équipement à ramasser pendant le run (armes, armures, sorts).
- Plus d'archétypes d'ennemis et de comportements d'IA (à distance, fuite, invocation).
- Étages thématiques (façon « strates » d'Aincrad) avec biomes visuels.
- Sprites/tuiles en remplacement du rendu ASCII.
- Sons et musique.

---

*Direction créative : medieval-fantasy, tour d'Aincrad. Développement : itératif.*
