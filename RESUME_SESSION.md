# Résumé de session — Liste des objets & refonte des raretés

Ce document résume les deux sujets traités dans cette session : (1) l'inventaire
détaillé de tous les items du jeu tel qu'il existait avant la session, et
(2) la refonte des raretés Épique/Légendaire (demande, idée retenue,
implémentation, vérifications). Il reflète l'état du code à la fin de la
session (commit `2cb6330` sur la branche `claude/rpg-roguelike-autonomy-g1vxmt`).

---

## 1. Demande : liste détaillée de tous les items du jeu

Demande initiale : *« fais moi une liste détaillée de tous les items du jeu »*.

Réponse fournie à partir d'une relecture complète de `scripts/Data.gd`,
couvrant six catégories :

1. **12 bases d'équipement** (Dague, Épée, Hache, Bâton / Tunique, Cotte,
   Plastron, Robe / Anneau, Amulette, Bottes, Talisman) avec leur stat
   primaire garantie, par slot (`arme`, `armure`, `relique`).
2. **4 raretés** (Commun 0 affixe ×1.0 / Rare 1 affixe ×1.15 / Épique 2
   affixes ×1.35 / Légendaire 3 affixes ×1.6), avec poids de tirage variant
   selon l'étage.
3. **10 affixes** possibles (ATK, MAG, DEF, VIT, PV, Régén, Critique,
   Esquive, Vol de vie, Épines) avec leurs plages de valeurs.
4. **4 consommables** (Potion de soin +40% PV, Grande potion +75% PV, Élixir
   de vie soin complet, Cristal d'Éclats +12+étage Éclats).
5. **5 artefacts** passifs cumulables (Calice de Sang, Carapace d'Épines,
   Croc Sauvage, Voile d'Ombre, Plume de Phénix) avec leur étage minimum.
6. **14 talents** de montée de niveau (Vigueur, Puissance, Arcane,
   Carapace, Célérité, Régénération, Précision, Agilité, Sangsue,
   Représailles, Affûtage, Concentration, Second souffle, Brutalité) —
   classés à part car ce sont des choix de build, pas du butin.

Cette liste portait sur le système **tel qu'il existait avant** la refonte
décrite ci-dessous (rareté = stats + affixes aléatoires uniquement, pour
tous les paliers).

---

## 2. Demande : rendre les raretés plus intéressantes que de simples stats

Demande : *« j'aimerai rendre les raretés d'équipement plus intéressement
que seulement des stats supplémentaires. propose une idée et produits au
moins 100 équipements pour commencer »*.

### Idée retenue

Garder **Commun** et **Rare** procéduraux (stats de base + 0 ou 1 affixe
aléatoire) comme économie de loot courante, mais faire en sorte que
**Épique** et **Légendaire** ne soient plus une simple amplification de
chiffres : ils puisent désormais dans une **bibliothèque d'objets uniques
nommés**, chacun porteur d'un **effet de combat distinct** (un « proc »)
en plus de ses stats fixes. Le palier Légendaire est la version amplifiée
(stats ×1.4, effet ×1.3, nom + épithète) de la même identité que son
pendant Épique — trouver l'un de ces objets devient un évènement marquant
qui change la façon de jouer, pas juste un meilleur nombre.

### Les 6 effets de combat (procs)

| id | Effet | Valeur Épique → Légendaire (exemples) |
|---|---|---|
| `execution` | +X% dégâts contre une cible sous 25% PV | 0.40–0.65 → ×1.3 |
| `frenesie` | +X% dégâts quand le porteur est sous 40% PV | 0.30–0.35 → ×1.3 |
| `premier_coup` | La 1ʳᵉ attaque de chaque combat est un critique garanti | booléen |
| `frappe_double` | X% de chances de frapper une 2ᵉ fois (50% dégâts) | 0.20–0.28 → ×1.3 |
| `soif_de_sang` | Soigne X% des PV max à chaque ennemi tué | 0.12–0.14 → ×1.3 |
| `moisson` | +X Éclats à chaque ennemi tué | 4–5 → ×1.3 |

### Contenu produit

- **51 identités de base** définies à la main dans `Data.UNIQUE_BASES`
  (17 par slot : arme / armure / relique), chacune avec nom, stats fixes et
  proc assigné.
- **17 épithètes** (`Data.UNIQUE_EPITHETS`) utilisées pour nommer la version
  Légendaire de chaque identité (ex. *« Bâton des Cendres, du Jugement »*).
- Le pool final **`Data.UNIQUE_ITEMS`** est construit une fois au chargement
  par `Data._build_unique_pool()` : 51 × 2 paliers = **102 objets** au total
  (vérifié par assertion dans le smoke test : `UNIQUE_ITEMS.size() >= 100`).

### Implémentation technique

- **`scripts/Data.gd`** :
  - Ajout de `UNIQUE_EPITHETS`, `UNIQUE_BASES`, `_proc_desc()`,
    `_build_unique_pool()`, `static var UNIQUE_ITEMS`, `_pick_unique()`.
  - `generate_item()` réécrit : si la rareté tirée est Épique/Légendaire,
    pioche dans `UNIQUE_ITEMS` (slot + rareté) plutôt que de générer une
    pièce procédurale ; sinon délègue à `_generate_procedural_item()`
    (l'ancienne logique d'affixes, extraite dans sa propre fonction).
  - L'objet retourné porte en plus des champs habituels : `unique: true`,
    `proc` (id), `proc_val` (valeur), `desc` (texte affiché en jeu).
- **`scripts/Entity.gd`** :
  - Nouveau champ `procs: Array` agrégé dans `recompute_stats()` à partir
    des objets équipés portant un champ `"proc"`.
  - Nouvelles méthodes `has_proc(id)` et `proc_value(id)`.
- **`scripts/Main.gd`** (logique de combat) :
  - Nouveau champ `first_strike_used`, réinitialisé dans `generate_floor()`.
  - `_player_attack()` : applique `frenesie` (PV bas), `execution` (cible
    affaiblie), force un critique pour `premier_coup` (une fois par
    combat), et gère un second coup pour `frappe_double`.
  - `on_enemy_killed()` : applique `moisson` (Éclats bonus) et
    `soif_de_sang` (soin au kill).
- **`scripts/Hud.gd`** : affiche la description de l'effet (`desc`) sous
  chaque objet équipé/en sac, dans la sidebar, le sac et la boutique.

### Bug latent corrigé en vérifiant

En capturant un écran réel de l'inventaire, la sidebar (PV, stats,
équipement) ne reflétait pas immédiatement un équipement/déséquipement/
recyclage/usage d'objet — elle ne se mettait à jour qu'au tour suivant.
Corrigé en ajoutant un appel à `refresh()` dans `equip_item()`,
`unequip_item()`, `salvage_item()`, `use_consumable()` et
`_acquire_artifact()` dans `scripts/Main.gd`.

### Vérifications effectuées

1. **Smoke test headless** (`_smoketest.gd` → `_SmokeTest.tscn`) : ajout
   d'assertions vérifiant (a) au moins 100 objets dans `UNIQUE_ITEMS`,
   (b) un objet unique pour chaque combinaison slot × rareté
   Épique/Légendaire, (c) qu'un objet unique généré porte bien un `proc` et
   une `desc`, (d) que `player.has_proc(...)` devient vrai après équipement
   réel via `Main.equip_item()`. Résultat : `=== SMOKETEST PASSED ===`.
2. **Capture d'écran réelle** (Xvfb + harnais jetable `_screenshot.gd`,
   supprimé après usage) : confirmé visuellement que l'inventaire affiche
   bien les trois effets uniques (Frénésie, Exécution, Moisson) sous les
   objets équipés, et que la sidebar reflète immédiatement les nouvelles
   stats après le correctif de rafraîchissement.

### Documentation mise à jour

`README.md` : la section *Rareté & affixes* a été remplacée par une
description du nouveau système (Commun/Rare procéduraux vs.
Épique/Légendaire = objets uniques + tableau des 6 effets de combat).

### Commit

```
2cb6330 feat: objets uniques pour Épique/Légendaire (effets de combat, 102 objets)
```
Poussé sur `claude/rpg-roguelike-autonomy-g1vxmt`
(6 fichiers modifiés : `README.md`, `_smoketest.gd`, `scripts/Data.gd`,
`scripts/Entity.gd`, `scripts/Hud.gd`, `scripts/Main.gd`).
