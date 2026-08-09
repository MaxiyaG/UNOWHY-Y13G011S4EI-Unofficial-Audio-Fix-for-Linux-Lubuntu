# UNOWHY Y13G011S4EI — Correctif audio pour Lubuntu / Ubuntu

Correctifs pour le bug récurrent de "son absent" / "son qui coupe"
affectant les haut-parleurs intégrés de la tablette/ordinateur portable
éducatif **UNOWHY Y13G011S4EI** (Intel Celeron N4120, Gemini Lake, codec
ES8336 via SOF) sous **Lubuntu 26.04 LTS**. Ces correctifs s'appliquent
très probablement aussi à d'autres machines partageant la même
combinaison de puce audio (pilote `sof-audio-pci-intel-apl` + codec
`sof-essx8336`) non reconnue dans la table de correctifs matériels du
noyau.

---

## ⚠️ Avertissement

Ce projet a été construit avec l'aide d'un assistant IA (un LLM), **et
non par un développeur professionnel du noyau/audio**, au cours d'une
session de débogage itérative par essais-erreurs sur une seule machine
physique. Il n'a **pas** été relu par des pairs et n'a **pas** été testé
sur une autre machine que celle sur laquelle il a été construit.

- Il s'agit d'un **prototype**, publié dans l'espoir d'aider d'autres
  personnes ayant exactement le même matériel — pas d'un outil abouti et
  généraliste.
- **Utilisation entièrement à vos propres risques.** L'auteur/les auteurs
  de ce dépôt **n'assument aucune responsabilité** en cas de dommage,
  perte de données, instabilité, ou toute autre conséquence résultant de
  l'utilisation de ces scripts.
- **Lisez chaque script avant de l'exécuter**, et assurez-vous de
  comprendre ce que fait chaque commande (modifications du mixeur,
  services systemd, paramètres de module noyau, réglages de gestion
  d'énergie PCI) avant de l'appliquer sur votre propre système.
- Testez sur un système où vous pouvez vous permettre une erreur (après
  une sauvegarde, ou sur une installation de test) avant de vous y fier
  sur votre machine principale.
- En cas de problème, consultez la section
  **[Désinstallation / Retour en arrière](#désinstallation--retour-en-arrière)**
  pour tout supprimer et revenir à une configuration d'origine.

---

## Résumé

Sur ce matériel, le son s'arrête aléatoirement de fonctionner sous
Linux — au premier démarrage, après une mise en veille, après que la
mise en veille automatique (autosuspend) PCI du contrôleur audio se
déclenche pendant une période d'inactivité, ou après plusieurs
pauses/lectures répétées dans un onglet de navigateur — alors même que
Windows sur cette même machine ne présente aucun souci et que le système
continue de signaler un périphérique audio sans erreur apparente.

Au cours d'une longue session de diagnostic, quatre causes
**indépendantes** ont été identifiées et corrigées, plus un problème
restant non résolu :

| # | Cause | Correctif | État |
|---|-------|-----------|------|
| 1 | Détection de jack casque inversée au démarrage (carte mère absente de la table de correctifs DMI du noyau) | Quirk de module noyau (`quirk=64`, JD_INVERTED) | ✅ Corrigé |
| 2 | Le mixeur du codec repasse en "muet / mauvais routage" après une mise en veille système | Watchdog ALSA en continu | ✅ Atténué |
| 3 | Mise en veille automatique (autosuspend) PCI du contrôleur audio pendant l'inactivité | Désactivation permanente de l'autosuspend | ✅ Corrigé |
| 4 | Le pipeline audio PipeWire se bloque même quand le mixeur ALSA est correct | Watchdog basé sur le compteur d'erreurs PipeWire | ✅ Atténué |
| 5 | Un onglet de navigateur isolé (observé avec TikTok sur Brave) perd son flux audio alors que d'autres onglets continuent de fonctionner | — | ❌ **Non corrigé** — voir [Pistes futures](#pistes-futures--problèmes-connus) |

Aucun de ces correctifs n'est un "vrai" patch noyau/pilote amont — ce
sont des contournements pratiques (un quirk documenté du noyau, plus des
scripts de surveillance qui détectent et corrigent la dérive) qui rendent
la machine utilisable au quotidien.

---

## Matériel couvert

| Composant | Détails |
|---|---|
| **Modèle** | **UNOWHY Y13G011S4EI** — ordinateur/tablette éducatif (`family=Education`) |
| **Carte mère** | `EM_IG116_200B_ENE_F_V2.0` — UNOWHY |
| **CPU** | Intel Celeron N4120 @ 1.10 GHz — Gemini Lake, 4 cœurs |
| **RAM** | 4 GiB LPDDR4 |
| **Contrôleur audio** | Intel *Celeron/Pentium Silver Processor High Definition Audio* |
| **PCI ID** | `8086:3198` |
| **Sous-système** | `2782:0220` — Emdoor Digital Technology |
| **Adresse PCI** | `0000:00:0e.0` |
| **Pilote audio** | `sof-audio-pci-intel-apl` — Sound Open Firmware (SOF) |
| **Codec** | ES8336 — `snd_soc_sof_es8336` |
| **Carte ALSA** | `sof-essx8336` |
| **Firmware** | `intel/sof/sof-glk.ri` |
| **Topologie** | `sof-glk-es8336-ssp0.tplg` |
| **OS testé** | Lubuntu 26.04 LTS |
| **Noyau testé** | `7.0.0-29-generic` |

### Compatibilité

Si votre machine utilise le **même pilote audio** `sof-audio-pci-intel-apl`
et la **même carte ALSA** `sof-essx8336`, ces correctifs vous concernent
très probablement, même si le modèle exact de la carte mère diffère.

Vous pouvez vérifier avec :

```bash
lspci -nnk | grep -A3 -i audio
cat /proc/asound/cards

---

## Explication technique des problèmes

### 1. Détection de jack inversée au démarrage

Le pilote `snd_soc_sof_es8336` utilise une table de correctifs basée sur
le DMI pour savoir comment interpréter son signal/broche de détection de
jack selon la carte mère exacte. Les cartes absentes de cette table
reçoivent `quirk mask 0x0` (visible via `dmesg | grep -i quirk`), donc
aucune correction n'est appliquée. Sur ce matériel, cela signifie que le
pilote croit en permanence qu'un casque est branché (`Headphone Jack`
affiche `on` même sans rien de connecté), ce qui coupe le haut-parleur
interne via la logique automatique du pilote — ceci se produit à chaque
démarrage à froid, indépendamment de toute mise en veille.

Confirmé par test : brancher un vrai casque produisait du son
correctement, prouvant que le circuit audio lui-même fonctionne — seule
*l'interprétation de la polarité du jack* est fausse. Forcer le bit 6 du
quirk (`SOF_ES8336_JD_INVERTED`, valeur 64) via un paramètre de module
corrige cela à chaque démarrage.

### 2. Réinitialisation de l'état du mixeur après veille / inactivité / pause-lecture

Indépendamment du problème de jack ci-dessus, les contrôles ALSA de ce
codec (interrupteur muet `Speaker`, volumes `SPKL`/`SPKR`, et surtout le
contrôle énuméré `HPVol SPKVol` qui sélectionne quels canaux DAC internes
alimentent l'amplificateur du haut-parleur) se réinitialisent dans un
état incorrect après :

- une mise en veille/réveil système complète (`systemctl suspend`)
- la mise en veille automatique (autosuspend) du contrôleur PCI lui-même
  pendant les périodes d'inactivité (visible via
  `cat /sys/bus/pci/devices/0000:00:0e.0/power/runtime_status` qui bascule
  vers `suspended`)
- simplement mettre en pause puis relancer une lecture vidéo plusieurs
  fois, **sans aucune** veille ni autosuspend impliqué

Comme il existe plusieurs déclencheurs indépendants (dont certains ne
passent par aucun hook systemd unique), un hook ciblé n'est pas
suffisamment fiable. Le correctif pratique est une boucle légère en
arrière-plan (`audio-watchdog.sh`) qui sonde les contrôles du mixeur
concernés et corrige toute dérive en une fraction de seconde, peu importe
la cause.

Une subtilité qui mérite d'être documentée : `amixer sget 'HPVol SPKVol'`
liste toujours les quatre valeurs possibles sur sa ligne `Items:` — seule
la ligne `Item0:` indique laquelle est *réellement* active. Un `grep`
naïf sur toute la sortie peut matcher silencieusement la mauvaise ligne
et rapporter "OK" alors que la sélection réelle est fausse.

### 3. Autosuspend PCI

Indépendamment de ce qui précède, la gestion d'énergie du noyau peut
elle-même mettre en veille automatique le périphérique PCI audio
(`power/control = auto`) après une période d'inactivité, contribuant au
symptôme n°2. Fixer `power/control = on` pour ce périphérique précis (via
un petit service systemd, une règle udev s'étant révélée non fiable —
elle semble entrer en compétition avec l'initialisation du pilote SOF et
se fait écraser) supprime entièrement ce déclencheur, pour un coût
énergétique négligeable pour un contrôleur audio.

### 4. Blocages du pipeline PipeWire indépendants du mixeur ALSA

Même avec un état de mixeur parfaitement correct (`Speaker on`, volumes
valides, bon routage) et `runtime_status active`, la lecture peut rester
silencieuse. `pw-top` a permis de le confirmer : quand le son fonctionne,
la colonne `ERR` du nœud `alsa_output...sof-essx8336...` affiche `0` ;
quand le son est mort silencieusement, elle affiche `1` (ou plus) sur ce
nœud précis, sans aucun changement correspondant côté mixeur ALSA.

Détail important : ce compteur `ERR` est **cumulatif** — il ne revient
pas à `0` une fois le problème résolu, donc un watchdog doit réagir à une
*augmentation* de la valeur, pas simplement à une valeur non nulle, sous
peine de redémarrer PipeWire inutilement en boucle. `pipewire-watchdog.sh`
implémente correctement cette logique et, en cas d'augmentation réelle,
redémarre la session PipeWire / PipeWire-Pulse / WirePlumber de
l'utilisateur.

### 5. Non résolu : bug audio par onglet de navigateur

Observé une fois : un onglet TikTok a perdu tout son audio (aucun flux
PipeWire pour lui dans `wpctl status`) alors qu'un onglet YouTube dans le
même navigateur (Brave) continuait de fonctionner normalement. Comme
seul un onglet était affecté alors que le périphérique audio, le mixeur
ALSA et le pipeline PipeWire étaient par ailleurs pleinement
fonctionnels (confirmé par l'autre onglet), ceci semble être un problème
propre au navigateur/site (limitation d'onglets en arrière-plan,
politique de lecture automatique, ou bug propre au lecteur du site)
plutôt qu'un problème audio au niveau système, et est **hors de portée de
ce que ces scripts peuvent corriger**. Voir [Pistes futures](#pistes-futures--problèmes-connus).

---

## Installation du correctif (Lubuntu / Ubuntu)

Ces étapes ciblent Lubuntu 26.04 LTS mais devraient fonctionner sans
modification sur toute distribution récente basée sur Ubuntu utilisant
systemd, ALSA et PipeWire.

### 0. Avant de commencer

Vérifiez que votre matériel correspond (adaptez les correctifs ci-dessous
si l'adresse PCI ou l'index de carte diffère sur votre machine) :

```bash
lspci -nnk | grep -A3 -i audio
cat /proc/asound/cards
```

Vous devriez voir `driver=sof-audio-pci-intel-apl` et une carte nommée
`sof-essx8336`. Si votre adresse PCI n'est pas `0000:00:0e.0`, mettez-la
à jour dans `scripts/audio-no-runtime-pm.service` et
`scripts/pipewire-watchdog.sh` avant l'installation.

### 1. Télécharger ce dépôt

```bash
git clone https://github.com/<votre-nom-utilisateur>/unowhy-y13g011s4ei-lubuntu-audio-fix.git
cd unowhy-y13g011s4ei-lubuntu-audio-fix
```

(Pas de `git` ? Utilisez le bouton vert "Code" → "Download ZIP" sur
GitHub, puis `cd` dans le dossier extrait.)

### 2. Correctif n°1 — quirk de détection de jack

Vous pouvez déplacer directement le fichier fourni :

```bash
sudo mv scripts/es8336-quirk.conf /etc/modprobe.d/es8336-quirk.conf
```

...ou le créer à la main avec `nano` si vous préférez voir exactement ce
qui est inséré :

```bash
sudo nano /etc/modprobe.d/es8336-quirk.conf
```

Collez :

```
options snd_soc_sof_es8336 quirk=64
```

Sauvegardez (`Ctrl+O`, `Entrée`) et quittez (`Ctrl+X`).

### 3. Correctifs n°2 et n°4 — installer les scripts de surveillance

```bash
sudo mv scripts/audio-watchdog.sh /usr/local/bin/audio-watchdog.sh
sudo mv scripts/pipewire-watchdog.sh /usr/local/bin/pipewire-watchdog.sh
sudo mv scripts/audio-fix-all.sh /usr/local/bin/audio-fix-all.sh
sudo chmod +x /usr/local/bin/audio-watchdog.sh \
              /usr/local/bin/pipewire-watchdog.sh \
              /usr/local/bin/audio-fix-all.sh
```

### 4. Installer les services systemd (correctifs n°2, n°3, n°4)

```bash
sudo mv scripts/audio-watchdog.service /etc/systemd/system/
sudo mv scripts/audio-no-runtime-pm.service /etc/systemd/system/
sudo mv scripts/pipewire-watchdog.service /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable --now audio-watchdog.service
sudo systemctl enable --now audio-no-runtime-pm.service
sudo systemctl enable --now pipewire-watchdog.service
```

### 5. Redémarrer

Le quirk de détection de jack (correctif n°1) ne prend effet qu'une fois
le module `snd_soc_sof_es8336` rechargé, ce qui se produit au démarrage :

```bash
sudo reboot
```

### 6. Vérifier

Après redémarrage :

```bash
cat /sys/module/snd_soc_sof_es8336/parameters/quirk   # doit afficher 64
sudo dmesg | grep -i quirk                             # doit mentionner "JD inverted enabled"
cat /sys/bus/pci/devices/0000:00:0e.0/power/control    # doit afficher "on"
systemctl status audio-watchdog.service                # doit être active (running)
systemctl status audio-no-runtime-pm.service            # doit montrer une exécution oneshot réussie
systemctl status pipewire-watchdog.service               # doit être active (running)
speaker-test -c2 -Dhw:0,0 -t wav
```

Vous devriez entendre des tonalités de test alternées gauche/droite.
Appuyez sur `Ctrl+C` pour arrêter.

### Optionnel : raccourci manuel "bouton d'urgence"

Pour le bug non résolu par onglet de navigateur (voir
[ci-dessus](#5-non-résolu--bug-audio-par-onglet-de-navigateur)), vous
pouvez lier `audio-fix-all.sh` à un raccourci clavier dans les
paramètres de votre environnement de bureau (ex : LXQt → Préférences →
Clavier et souris → Raccourcis), en le pointant vers :

```
pkexec /usr/local/bin/audio-fix-all.sh
```

Ou simplement l'exécuter manuellement depuis un terminal en cas de
besoin :

```bash
sudo /usr/local/bin/audio-fix-all.sh
```

---

## Désinstallation / Retour en arrière

Pour tout supprimer et revenir à une configuration d'origine, non
modifiée :

```bash
sudo systemctl disable --now audio-watchdog.service
sudo systemctl disable --now audio-no-runtime-pm.service
sudo systemctl disable --now pipewire-watchdog.service

sudo rm -f /etc/systemd/system/audio-watchdog.service
sudo rm -f /etc/systemd/system/audio-no-runtime-pm.service
sudo rm -f /etc/systemd/system/pipewire-watchdog.service
sudo systemctl daemon-reload

sudo rm -f /usr/local/bin/audio-watchdog.sh
sudo rm -f /usr/local/bin/pipewire-watchdog.sh
sudo rm -f /usr/local/bin/audio-fix-all.sh

sudo rm -f /etc/modprobe.d/es8336-quirk.conf

sudo reboot
```

Après redémarrage, `cat /sys/module/snd_soc_sof_es8336/parameters/quirk`
devrait afficher `-1` (ou aucune surcharge), et aucun des services de
surveillance ne devrait apparaître dans `systemctl list-units | grep audio`.

---

## Pistes futures / problèmes connus

- **Bug audio par onglet de navigateur (problème n°5 ci-dessus).** Pas
  encore compris en détail. Hypothèses à creuser : la politique de
  limitation/économie d'énergie des onglets en arrière-plan de Brave, un
  bug propre au lecteur TikTok, ou une politique du gestionnaire de
  session PipeWire (WirePlumber) qui supprime le nœud d'un flux sans le
  recréer. À tester : le bug se reproduit-il aussi sur Firefox/Chromium,
  ou seulement sur Brave ? Désactiver les options de limitation en
  arrière-plan dans `brave://settings/system` aide-t-il ?
- **Support du casque.** Ces scripts supposent actuellement que le
  haut-parleur interne est la seule sortie et vont activement contrer
  toute tentative de router le son vers un casque, car le signal de
  détection de jack sur ce matériel est peu fiable **dans les deux
  sens** (le switch brut `SW_HEADPHONE_INSERT` sur `/dev/input/eventN`
  s'est révélé bloqué sur "inséré" même sans rien de branché, donc le
  logiciel ne peut actuellement pas distinguer "bug" de "un vrai casque
  est branché"). Un basculement manuel (arrêter
  `audio-watchdog.service`, basculer `HPVol SPKVol` vers le routage
  casque, redémarrer le service une fois terminé) contourne cela mais
  n'est pas automatique. Un correctif plus propre nécessiterait
  d'investiguer si le signal brut de détection de jack GPIO peut être
  corrigé au niveau matériel/firmware, ou de trouver un autre signal
  fiable (par ex. un événement udev/ACPI) permettant de distinguer un
  vrai branchement de casque de ce faux positif.
- **Réglage CPU/batterie.** L'intervalle de sondage de
  `audio-watchdog.sh` (`INTERVAL`, `0.5s` par défaut) est un compromis
  entre vitesse de réaction et consommation CPU/batterie. N'hésitez pas
  à l'augmenter (par ex. `2`) si vous n'avez pas besoin d'une récupération
  quasi instantanée et préférez une consommation CPU en arrière-plan plus
  faible.
- **Portabilité vers d'autres distributions.** L'approche générale (quirk
  noyau + scripts de surveillance) devrait se transposer sur Debian,
  Fedora ou Arch, mais les noms de paquets pour le firmware SOF diffèrent
  (`firmware-sof-signed` sur Ubuntu, `sof-firmware` sur Debian/Arch,
  `alsa-sof-firmware` sur Fedora), et le fichier de quirk modprobe peut
  nécessiter une régénération de l'initramfs sur certaines distributions
  (`dracut --force` sur Fedora, `mkinitcpio -P` sur Arch). Les
  contributions documentant cela pour d'autres distributions sont les
  bienvenues.
- **Aucun correctif amont.** Rien de tout cela n'a été signalé aux ou
  relu par les vrais mainteneurs du noyau SOF/ALSA. Si vous avez
  l'expertise nécessaire, envisagez de signaler ceci comme un vrai
  rapport de bug auprès de
  [thesofproject](https://github.com/thesofproject) — une véritable
  entrée dans la table de correctifs pour cette carte serait un bien
  meilleur correctif à long terme qu'un script de surveillance.

Les contributions, tests sur d'autres appareils UNOWHY/Gemini
Lake/ES8336, et pull requests sont les bienvenus.

---

## Licence

Fourni tel quel, sans garantie d'aucune sorte (voir
[Avertissement](#️-avertissement) ci-dessus). Vous êtes libre d'utiliser,
modifier et redistribuer ces scripts.
