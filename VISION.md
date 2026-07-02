# VISION — Ce qui ferait sortir « Les Strates » du lot

> Compagnon de `AUDIT.md`. L'audit dit ce qui est cassé ; ce document dit ce
> qui manque pour que le jeu soit *remarquable* plutôt que « encore un
> roguelike généré ». Aucun code : des directions, classées par impact.

---

## 1. Diagnostic honnête : le jeu n'a pas encore de phrase

Aujourd'hui, « Les Strates » est un collage compétent d'emprunts assumés :
talents façon Hades, structure de nœuds façon Slay the Spire, préfixes façon
Dungeonmans, arbre façon Integrated Strategies, look façon Moonring, thème
façon SAO. Chaque pièce est correcte. **Aucune n'est à toi.**

Le test qui sépare un vrai jeu d'un jeu-prototype : peux-tu compléter la
phrase *« c'est le roguelike où ___ »* d'une façon qu'aucun autre jeu ne peut
revendiquer ?

- Into the Breach : « …où tu vois chaque attaque ennemie avant qu'elle tombe. »
- Hades : « …où l'histoire continue à travers tes morts. »
- Noita : « …où chaque pixel est simulé. »
- Les Strates : « …où tu montes une tour et tu ramasses du loot. » ← c'est la
  description de 400 jeux Steam à 3 avis.

Un joueur qui ne peut pas décrire ton jeu en une phrase ne peut pas le
recommander. Tout ce qui suit sert à construire cette phrase, puis à
l'entourer du niveau de finition qui fait dire « c'est un vrai jeu ».

---

## 2. Le hook : quatre candidats, une recommandation

Choisir **UN** hook et le creuser jusqu'au bout. Un hook à moitié fait ne
compte pas.

### A. Les biomes deviennent des RÈGLES : terrain élémentaire interactif ★ recommandé

Aujourd'hui les 6 biomes sont des palettes de couleurs. L'idée : chaque biome
devient un bac à sable élémentaire où le terrain réagit aux éléments — et tout
le contenu existant (statuts burn/slow/stun/poison, préfixes Brasier/Givre/
Foudre/Venin, tuiles arbre/eau/rocher) se met soudain à interagir :

- **Le feu se propage** : enflammer un arbre de la Forêt embrase les arbres
  adjacents tour après tour ; l'obstacle brûlé disparaît (nouveaux passages),
  les ennemis pris dedans brûlent. L'Élémentaire de feu devient un danger de
  terrain ambulant.
- **L'eau conduit la foudre** : un éclair sur un ennemi dans l'eau chaîne sur
  tout le plan d'eau. Le Marais (14 % d'eau) devient LE biome des builds foudre.
- **Le givre gèle l'eau** : surface marchable temporaire — raccourcis, fuites,
  attirer un ennemi lourd sur la glace qui craque.
- **Le poison stagne en nuages** dans le Marais ; le vent du Désert les déplace.
- **La lave du Volcan** coule lentement, remodèle l'étage pendant le combat.

> **État (Phase 4 du guide d'implémentation)** : feu qui se propage (4.1),
> eau conductrice de foudre, gel praticable qui fond, nuages toxiques à la
> mort des créatures du marais, lave punitive au volcan (4.2) et knockback
> (4.3 — Coup de bélier, chargeurs, Bourreau) sont **implémentés**. Coupés
> pour l'instant : le vent du désert qui déplace les nuages, et la lave qui
> COULE (elle est statique — dangereuse seulement quand on y est poussé,
> l'adjacence passive était trop punitive).

Pourquoi c'est LE bon hook pour CE jeu : il ne demande presque aucun contenu
nouveau — il convertit du contenu existant (biomes, statuts, préfixes, sorts)
en gameplay émergent. Le positionnement devient réellement tactique (l'audit
pointe que la promesse « le positionnement compte » n'est pas tenue). Les
biomes deviennent des stratégies, pas des skins. Et la phrase existe :
**« le roguelike où tu brûles la forêt, gèles le lac et électrifies le
marais — étage par étage. »**

### B. Les Échos : la Tour se souvient de tes mortes

À chaque mort, la Tour garde un Écho. Au run suivant, sur l'étage où tu es
tombée, tu rencontres **ton Aria précédente** en revenante — avec son vrai
build (équipement, talents, compétence, pouvoirs, sérialisés à la mort). La
vaincre permet de récupérer UN objet de son build, au choix.

- Coût technique faible : sérialiser le build au game over, un spawn spécial.
- Le Revenant et le Paladin Déchu (`copy_player`) posent déjà la mécanique.
- Émotionnellement fort : la permadeath a soudain une trace dans le monde, et
  « affronter son ancien build » est une histoire que les joueurs racontent.
- Variante douce : l'Écho non combattu murmure un indice/lore.

### C. Intentions télégraphées (la leçon d'Into the Breach)

Chaque ennemi affiche son intention au-dessus de sa tête : ⚔ direction
d'attaque, ✦ incantation (quoi), ↻ invocation, 💤 endormi. Le combat devient
un puzzle lisible et **aucune mort n'est injuste**. Toute la data existe déjà
(`ai.behavior`, cooldowns) — c'est de l'affichage.

→ Verdict : ce n'est pas un hook, c'est un **standard de qualité**. À faire
quoi qu'il arrive (voir §3), mais ça ne différencie pas à soi seul.

### D. La Tour parle : pactes dynamiques en cours de run

Étendre les Serments (système déjà en place) : la Tour propose des pactes en
plein run — « Atteins le Gardien en 20 tours sans soin : je t'offre un
Légendaire. Échoue : −25 % PV max. » Des moments de décision risque/récompense
qui donnent une voix à l'antagoniste.

### Recommandation

**A** comme identité mécanique + **C** comme socle de qualité, et **B** comme
signature émotionnelle (A et B ne se marchent pas dessus). Si un seul : **A**.
D peut venir plus tard nourrir la narration (§4).

---

## 3. Profondeur de combat : chaque tour doit être une décision

Aujourd'hui un tour type = « avancer vers l'ennemi, bumper ». Ce qui manque :

1. **Intentions ennemies visibles** (§2.C) — non négociable.
2. **L'ordre des tours affiché** : le système d'énergie/vitesse est la
   mécanique la plus sophistiquée du moteur… et elle est **invisible**. Une
   petite frise « qui joue bientôt » (façon Darkest Dungeon) rend la stat
   Vitesse enfin lisible et stratégique.
3. **Poussée/traction** : une action « bousculer » (et des compétences qui
   poussent) + hook A = projeter un ennemi dans l'eau, le feu, un piège. Le
   knockback est la brique qui rend le terrain offensif.
4. **Une 2ᵉ case active** (touche Q) : compétence secondaire ou consommable
   assigné — le combat gagne une rotation au lieu de « bump + ESPACE ».
5. **Aperçu de dégâts au survol** : combien je vais lui mettre, combien il va
   me mettre. Toute la formule existe.

---

## 4. Identité narrative : le modèle Hades, pas le modèle SAO

Une héroïne unique est ton plus gros atout narratif — exploité à 0 % (une
ligne de lore dans `Data.gd`). Le modèle qui marche avec la répétition :

- **Aria parle** : une réplique courte (1 ligne, jamais plus) en entrant dans
  un biome, en croisant un Écho, en re-rencontrant un boss déjà vaincu.
- **Le Hub réagit aux morts** : les PNJ prévus en Phase 6 doivent se souvenir.
  « Encore le Bourreau ? Il tient sa hache trop haut, tu sais. » Le forgeron
  qui commente ton dernier build. C'est ça qui rend un hub vivant, pas les
  sprites de bâtiments.
- **Les boss ont une mémoire** : 2-3 variantes de dialogue d'intro selon le
  nombre de rencontres. Dix boss × 3 lignes = 30 lignes de texte pour un
  effet « le monde me connaît » massif.
- **Nommer les strates** (la Lisière, les Fosses, le Ciel Renversé…) : la
  progression devient géographie, pas compteur.
- La Tour comme antagoniste doté d'une voix (relie §2.D et les fins multiples
  prévues en Phase 7).

Règle d'or : du texte en gouttes (barks), jamais en murs.

---

## 5. La checklist « poli vs camelote » (classée impact/effort)

C'est ici que se joue à 80 % la perception « vrai jeu vs jeu vibe-codé ».
Un joueur juge en 90 secondes, sur le feel, pas sur l'arbre de méta.

1. **Une vraie police pixel** — le jeu utilise `ThemeDB.fallback_font`
   partout : c'est LE marqueur n°1 de prototype. Une police bitmap dédiée
   (m5x7, monogram, ou custom) change instantanément 100 % des écrans.
2. **10 sons** : coup, critique, mort, ramassage, niveau, escalier, achat,
   soin, clic UI, danger. Un jeu muet = camelote, quel que soit le reste.
   Ensuite : une musique par biome + un thème de Hub + ambiances (vent,
   braises, marais).
3. **Le mouvement tweené** : les entités se téléportent de case en case.
   Interpoler (0,08 s), ajouter un hit-stop de 2-3 frames sur les coups, des
   **chiffres de dégâts flottants**, un micro-screenshake sur les crits
   (désactivable). Le moteur d'FX de MapView est déjà à moitié là.
4. **Réactivité des entrées** : maintien de touche = déplacement continu,
   buffer d'input, zéro frame morte entre l'action et la réponse. Un
   tour-par-tour doit se sentir *instantané*.
5. **Particules d'ambiance par biome** : feuilles en Forêt, neige en Toundra,
   cendres au Volcan, lucioles au Marais + étincelles de la torche. Peu
   coûteux, transforme l'atmosphère.
6. **L'illustration d'écran-titre** (déjà prévue) + parallaxe lente : la
   première image vend le jeu.
7. **Récap de mort digne** : cause de la mort, frise du run (étages, boss,
   objets clés), « à un cheveu de ton record ». C'est l'écran le plus vu du
   jeu — il doit donner envie de relancer, pas constater.
8. **Seed affichée + runs quotidiens + page de statistiques** : les signaux
   « ce jeu est fini et pensé pour durer ».
9. **Options complètes** : volumes séparés, screenshake on/off, remap des
   touches, glyphes de rareté doublés d'icônes (daltonisme).
10. **Cohérence UI/pixel-art** : coins arrondis + ombres portées StyleBox
    actuels jurent avec le pixel art. Passer les panneaux sur des bordures
    pixel (9-patch) pour une direction artistique UNE et indivisible.

---

## 6. Ce qu'il ne faut PAS faire

- **Ajouter des systèmes en largeur.** Le jeu a déjà ~12 systèmes ; la
  camelote générée est large et peu profonde, les bons jeux sont étroits et
  profonds. Chaque idée nouvelle doit approfondir le hook choisi, sinon poubelle.
- **Cinq familles de passifs parallèles** : procs d'objets, artefacts,
  pouvoirs, talents, synergies — un joueur ne les distingue pas. Fusionner
  artefacts + pouvoirs en un seul système « Reliques » à paliers réglerait la
  confusion et libérerait de l'UI. Moins de cases, plus de sens.
- **Plusieurs héros.** Aria est l'atout narratif ; la diluer tue le §4. La
  variété vient des armes/biomes/serments.
- **Agrandir les cartes** avant d'avoir densifié (cf. AUDIT §3.4).
- **Écrire du lore en pavés.** Barks d'une ligne, toujours.

---

## 7. Séquencement (s'insère dans le plan de l'AUDIT)

1. **AUDIT P0 + P1 d'abord** (bugs + équité du combat) : un hook posé sur un
   combat injuste ne sauvera rien.
2. **Polish 1-4 immédiatement après** (police, sons, tween/juice, inputs) :
   une semaine de travail, transforme la perception de tout ce qui existe déjà.
3. **Tranche verticale du hook A** sur UN biome : la Forêt, propagation du feu
   uniquement. Valider que c'est amusant avant d'étendre aux 5 autres biomes.
4. **§3 (intentions + frise des tours + poussée)** en parallèle de l'extension
   du hook.
5. **§4 (narration)** au moment de la Phase 6 (dialogues/PNJ) déjà planifiée —
   avec les Échos (§2.B) comme pièce maîtresse.
6. Le reste de l'AUDIT (contenu P4, industrialisation P5) inchangé.

La cible finale, en une phrase de page Steam : *« Un roguelike tactique où la
tour se souvient de tes mortes, et où chaque biome est un bac à sable
élémentaire — brûle la forêt, gèle le lac, électrifie le marais, et venge
celle que tu étais. »* Aucun jeu de la concurrence directe ne peut écrire
cette phrase.
