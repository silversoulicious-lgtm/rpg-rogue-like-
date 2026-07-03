# Instrumentation & réglage d'équilibrage (Phase 5)

Ce dossier accueille les CSV de mesure produits par le harnais d'auto-jeu
`_balance_sim.gd` (Phase 5.1), ainsi que les notes datées de réglage (Phase 5.2).

## Produire un CSV

```bash
# 50 runs (défaut) :
godot --headless --path . --script res://_balance_sim.gd
# N runs :
SIM_RUNS=200 godot --headless --path . --script res://_balance_sim.gd
```

Le script écrit `user://balance_sim.csv` (chemin `user://` de Godot ; sous Linux
`~/.local/share/godot/app_userdata/<nom du projet>/balance_sim.csv`). Copier ce
fichier ici sous un nom daté, p. ex. `2026-07-03-avant.csv` /
`2026-07-03-apres.csv`, avec une note du changement testé.

Colonnes : `seed,death_floor,killed_by,level,kills,turns,shards_banked,best_rarity,stalled`.
En fin d'exécution, le script imprime les percentiles p25/p50/p75 de `death_floor`.

## Politique du harnais (rappel)

Sonde reproductible, pas un joueur optimal — méta désactivée (upgrades / nœuds de
Connaissances / Serments neutralisés) pour mesurer la difficulté BRUTE :

- **PLAYING** : boit un soin si PV < 35 % ; lance la capacité si prête et une cible
  visible est à portée ; sinon avance (A* `Dungeon.next_step`) vers l'ennemi
  visible le plus proche, sinon vers l'escalier.
- **CHOICE** — récompense : équipe si la pièce bat le slot courant, sinon soigne
  si PV < 60 %, sinon Éclats. Boutique : achète un soin si PV < 50 % et abordable,
  sinon part. Événement : choix 0. Repos : soin.
- **LEVELUP** : premier talent proposé. **INVENTORY** : jamais ouvert.
- Garde-fou : 20 000 actions/run → run marqué `stalled`.

## Cibles de réglage (Phase 5.2)

Objectif : **étage de mort médian sans méta ≈ 12–15**. Leviers (tous dans
`Data.gd`, dans l'ordre de préférence) :

1. `ENEMY_HP_SLOPE` / `ENEMY_ATK_SLOPE` (pentes désormais séparées ; boss :
   `BOSS_HP_SLOPE` / `BOSS_ATK_SLOPE`).
2. `ENEMY_DEF_SLOPE` / `BOSS_DEF_SLOPE` (la Défense ennemie est maintenant scalée).
3. `ITEM_SCALE_SLOPE` (pente d'échelle des objets procéduraux).
4. Courbe d'XP : `Main.xp_to_next(level) = 10 + level*level*3` (quadratique).
5. `max_floor` par espèce dans `Data.ENEMIES` (les faibles se retirent).

> ⚠️ Les CSV avant/après ne sont pas encore commités : la session qui a écrit le
> harnais n'avait pas accès à un binaire Godot exécutable (politique réseau du
> bac à sable bloquant le téléchargement). À produire lors d'une passe locale
> avec Godot, puis committer ici avec la note de réglage correspondante.
