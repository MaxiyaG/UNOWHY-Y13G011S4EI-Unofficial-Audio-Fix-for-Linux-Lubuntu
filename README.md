*[English version below](#english-version) — [Version anglaise plus bas](#english-version)*

# UNOWHY Y13G011S4EI — Correctif audio pour Lubuntu / Ubuntu

Correctifs pour le bug récurrent de "son absent" / "son qui coupe"
affectant les haut-parleurs intégrés de la tablette/ordinateur portable
éducatif **UNOWHY Y13G011S4EI** (Intel Celeron N4120, Gemini Lake, codec
ES8336 via SOF) sous **Linux (Lubuntu 26.04 LTS)**. Ces correctifs
s'appliquent très probablement aussi à d'autres machines partageant la
même combinaison de puce audio (pilote `sof-audio-pci-intel-apl` + codec
`sof-essx8336`) non reconnue dans la table de correctifs matériels du
noyau.

---

## ⚠️ AVERTISSEMENT : PROTOTYPE EN COURS DE DÉVELOPPEMENT — UTILISATION À VOS PROPRES RISQUES ET PÉRILS

Ce projet a été construit avec l'aide d'un assistant IA (un LLM), **et
non par un développeur professionnel du noyau/audio**, au cours d'une
session de débogage itérative par essais-erreurs sur une seule machine
physique. Il n'a **pas** été relu par des pairs et n'a **pas** été testé
sur une autre machine que celle sur laquelle il a été construit.

- **Prototype** publié pour aider d'autres personnes ayant exactement le
  même matériel — pas un outil abouti et généraliste.
- **Utilisation entièrement à vos propres risques.** L'auteur de ce dépôt
  n'assume aucune responsabilité en cas de dommage, perte de données,
  instabilité ou toute autre conséquence.
- **Lisez les scripts avant de les exécuter** — ils modifient le mixeur
  ALSA, installent des services systemd, un paramètre de module noyau et
  un réglage de gestion d'énergie PCI.
- En cas de problème : `sudo ./uninstall.sh` (voir plus bas).

---

## Résumé

Sur ce matériel, le son s'arrête aléatoirement de fonctionner sous Linux
— au premier démarrage, après une mise en veille, après que l'autosuspend
PCI du contrôleur audio se déclenche pendant une inactivité, ou après
plusieurs pauses/lectures répétées dans un onglet de navigateur — alors
que Windows sur cette même machine ne présente aucun souci.

Quatre causes **indépendantes** ont été identifiées et corrigées, plus un
problème restant non résolu :

| # | Cause | Correctif | État |
|---|-------|-----------|------|
| 1 | Détection de jack casque inversée au démarrage (carte mère absente de la table de correctifs DMI du noyau) | Quirk de module noyau (`quirk=64`, JD_INVERTED) | ✅ Corrigé |
| 2 | Le mixeur du codec repasse en "muet / mauvais routage" après une mise en veille | Watchdog ALSA en continu | ✅ Atténué |
| 3 | Mise en veille automatique (autosuspend) PCI du contrôleur audio | Désactivation permanente de l'autosuspend | ✅ Corrigé |
| 4 | Le pipeline PipeWire se bloque même quand le mixeur ALSA est correct | Watchdog basé sur le compteur d'erreurs PipeWire | ✅ Atténué |
| 5 | Un onglet de navigateur isolé (observé avec TikTok sur Brave) perd son flux audio | — | ❌ Non corrigé — voir [Pistes futures](#pistes-futures) |

Aucun de ces correctifs n'est un "vrai" patch noyau/pilote amont — ce
sont des contournements pratiques (un quirk documenté du noyau, plus des
scripts de surveillance qui détectent et corrigent la dérive) qui rendent
la machine utilisable au quotidien.

---

## Matériel couvert

| Composant | Détails |
|---|---|
| **Modèle** | UNOWHY Y13G011S4EI |
| **Carte mère** | `EM_IG116_200B_ENE_F_V2.0` — UNOWHY |
| **CPU** | Intel Celeron N4120 @ 1.10 GHz — Gemini Lake, 4 cœurs |
| **RAM** | 4 GiB LPDDR4 |
| **Contrôleur audio** | Intel *Celeron/Pentium Silver Processor HD Audio* (`8086:3198`) |
| **Sous-système** | `2782:0220` — Emdoor Digital Technology |
| **Adresse PCI** | `0000:00:0e.0` |
| **Pilote audio** | `sof-audio-pci-intel-apl` (Sound Open Firmware) |
| **Codec** | ES8336 — `snd_soc_sof_es8336` |
| **Carte ALSA** | `sof-essx8336` |
| **OS testé** | Lubuntu 26.04 LTS, noyau `7.0.0-29-generic` |

**Compatibilité :** si votre machine rapporte le même pilote
`sof-audio-pci-intel-apl` et la même carte `sof-essx8336`
(`lspci -nnk | grep -A3 -i audio` et `cat /proc/asound/cards`), ces
correctifs vous concernent très probablement, même sur un autre modèle
de carte mère.

---

## Explication technique des problèmes

### 1. Détection de jack inversée au démarrage

Le pilote `snd_soc_sof_es8336` utilise une table de correctifs basée sur
le DMI pour interpréter son signal de détection de jack selon la carte
mère exacte. Les cartes absentes de cette table reçoivent
`quirk mask 0x0` (`dmesg | grep -i quirk`) : aucune correction n'est
appliquée, et le pilote croit en permanence qu'un casque est branché
(`Headphone Jack` affiche `on` même sans rien de connecté), coupant le
haut-parleur interne dès le démarrage à froid.

Confirmé par test : brancher un vrai casque produisait du son
correctement — seule *l'interprétation de la polarité du jack* est
fausse. Forcer le bit 6 du quirk (`SOF_ES8336_JD_INVERTED`, valeur 64)
corrige cela à chaque démarrage.

### 2. Réinitialisation du mixeur après veille / inactivité / pause-lecture

Les contrôles ALSA du codec (`Speaker`, `SPKL`/`SPKR`, et surtout
`HPVol SPKVol` qui sélectionne les canaux DAC alimentant le
haut-parleur) se réinitialisent après une veille système, un autosuspend
PCI, ou simplement plusieurs pause/lecture vidéo — **sans aucune veille
impliquée**. Comme les déclencheurs sont multiples et indépendants,
`audio-watchdog.sh` sonde en continu ces contrôles et corrige toute
dérive en une fraction de seconde, peu importe la cause.

Subtilité : `amixer sget 'HPVol SPKVol'` liste toujours les 4 valeurs
possibles sur sa ligne `Items:` — seule la ligne `Item0:` indique
laquelle est réellement active. Un `grep` sur toute la sortie peut
matcher la mauvaise ligne à tort.

### 3. Autosuspend PCI

Le noyau peut lui-même mettre en veille le périphérique PCI audio
(`power/control = auto`) après inactivité, contribuant au problème n°2.
Un service systemd force `power/control = on` en permanence (une règle
udev s'est révélée peu fiable, en compétition avec l'init du pilote
SOF), pour un coût énergétique négligeable.

### 4. Blocages PipeWire indépendants du mixeur ALSA

Même mixeur correct et `runtime_status active`, la lecture peut rester
silencieuse. `pw-top` le confirme via la colonne `ERR` du nœud
`alsa_output...sof-essx8336...` : `0` quand ça marche, `1`+ quand le son
est mort silencieusement. Ce compteur est **cumulatif** (ne revient
jamais à 0), donc `pipewire-watchdog.sh` ne réagit qu'à une
*augmentation* de sa valeur, et redémarre alors PipeWire/WirePlumber.

### 5. Non résolu : bug audio par onglet de navigateur

Observé une fois : un onglet TikTok a perdu tout son audio (aucun flux
PipeWire) alors qu'un onglet YouTube dans le même navigateur (Brave)
fonctionnait normalement. Périphérique, mixeur et pipeline étant
par ailleurs pleinement fonctionnels, ceci semble être un problème
propre au navigateur/site, **hors de portée de ces scripts**.

---

## Installation (Lubuntu / Ubuntu)

```bash
git clone https://github.com/<votre-nom-utilisateur>/unowhy-y13g011s4ei-lubuntu-audio-fix.git
cd unowhy-y13g011s4ei-lubuntu-audio-fix
sudo ./install.sh
sudo reboot
```

`install.sh` vérifie que votre matériel correspond, installe le quirk
noyau, les scripts et les 3 services systemd, puis les active. Le
redémarrage est nécessaire pour que le quirk (`quirk=64`) prenne effet.

> Adresse PCI différente de `0000:00:0e.0` ? Éditez-la dans
> `scripts/audio-no-runtime-pm.service` et `scripts/pipewire-watchdog.sh`
> avant d'exécuter `install.sh`.

**Vérification rapide** après redémarrage :

```bash
cat /sys/module/snd_soc_sof_es8336/parameters/quirk   # -> 64
systemctl status audio-watchdog.service                # -> active (running)
speaker-test -c2 -Dhw:0,0 -t wav
```

**Bouton d'urgence** pour le bug par onglet (§5) — à lier à un raccourci
clavier si besoin (`pkexec /usr/local/bin/audio-fix-all.sh`) :

```bash
sudo /usr/local/bin/audio-fix-all.sh
```

---

## Désinstallation

```bash
sudo ./uninstall.sh
sudo reboot
```

Supprime les 3 services, les scripts, et le quirk noyau — retour à une
configuration d'origine.

---

## Pistes futures

- **Bug audio par onglet (§5).** À creuser : throttling des onglets en
  arrière-plan de Brave, bug propre à TikTok, ou WirePlumber qui
  supprime un nœud sans le recréer. Se reproduit-il sur Firefox/Chromium ?
- **Support du casque.** Le signal de détection de jack est peu fiable
  dans les deux sens (`SW_HEADPHONE_INSERT` reste bloqué "inséré" même
  débranché) : impossible pour l'instant de distinguer un vrai casque
  d'un faux positif. Contournement manuel : arrêter
  `audio-watchdog.service`, basculer `HPVol SPKVol` vers le routage
  casque, redémarrer le service une fois terminé.
- **CPU/batterie.** `INTERVAL` dans `audio-watchdog.sh` (0.5s par défaut)
  est un compromis réactivité/consommation — augmentez-le si besoin.
- **Autres distributions.** Approche transposable à Debian/Fedora/Arch,
  mais le paquet firmware SOF change de nom
  (`sof-firmware`, `alsa-sof-firmware`) et peut nécessiter une
  régénération d'initramfs (`dracut --force`, `mkinitcpio -P`).
- **Correctif amont.** Rien n'a été soumis aux mainteneurs SOF/ALSA — une
  vraie entrée dans leur table de quirks serait préférable à un
  watchdog. Contributions bienvenues sur
  [thesofproject](https://github.com/thesofproject).

---

## Licence

Fourni tel quel, sans garantie d'aucune sorte (voir
[Avertissement](#️-avertissement)).

---
---

<a name="english-version"></a>
# UNOWHY Y13G011S4EI — Audio Fix for Lubuntu / Ubuntu

Fixes for the recurring "no sound" / "sound cutting out" bug affecting
the built-in speakers of the **UNOWHY Y13G011S4EI** educational
tablet/laptop (Intel Celeron N4120, Gemini Lake, ES8336 codec via SOF)
on **Linux (Lubuntu 26.04 LTS)**. These fixes very likely also apply to
other machines sharing the same audio chip combination (driver
`sof-audio-pci-intel-apl` + codec `sof-essx8336`) that isn't recognized
in the kernel's hardware quirk table.

---

## ⚠️ WARNING: PROTOTYPE UNDER DEVELOPMENT — USE AT YOUR OWN RISK

This project was built with the help of an AI assistant (an LLM), **not
by a professional kernel/audio developer**, over the course of an
iterative trial-and-error debugging session on a single physical
machine. It has **not** been peer-reviewed and has **not** been tested
on any machine other than the one it was built on.

- **Prototype** published to help others with the exact same hardware —
  not a polished, general-purpose tool.
- **Use entirely at your own risk.** The author of this repo assumes no
  liability for any damage, data loss, instability, or other
  consequences.
- **Read the scripts before running them** — they modify the ALSA
  mixer, install systemd services, a kernel module parameter, and a PCI
  power-management setting.
- If something goes wrong: `sudo ./uninstall.sh` (see below).

---

## Summary

On this hardware, sound randomly stops working under Linux — on first
boot, after sleep, after the audio controller's PCI autosuspend kicks
in during idle time, or after repeated pause/play cycles in a browser
tab — while Windows on the same machine shows no such issues.

Four **independent** causes were identified and fixed, plus one
remaining unresolved issue:

| # | Cause | Fix | Status |
|---|-------|-----|--------|
| 1 | Inverted headphone jack detection at boot (motherboard missing from the kernel's DMI quirk table) | Kernel module quirk (`quirk=64`, JD_INVERTED) | ✅ Fixed |
| 2 | Codec mixer reverts to "muted / wrong routing" after sleep | Continuous ALSA watchdog | ✅ Mitigated |
| 3 | Automatic PCI autosuspend of the audio controller | Autosuspend permanently disabled | ✅ Fixed |
| 4 | PipeWire pipeline hangs even when the ALSA mixer is correct | Watchdog based on the PipeWire error counter | ✅ Mitigated |
| 5 | A single browser tab (observed with TikTok on Brave) loses its audio stream | — | ❌ Unfixed — see [Future work](#future-work) |

None of these fixes is a "real" upstream kernel/driver patch — they're
practical workarounds (a documented kernel quirk, plus monitoring
scripts that detect and correct drift) that make the machine usable
day to day.

---

## Covered hardware

| Component | Details |
|---|---|
| **Model** | UNOWHY Y13G011S4EI |
| **Motherboard** | `EM_IG116_200B_ENE_F_V2.0` — UNOWHY |
| **CPU** | Intel Celeron N4120 @ 1.10 GHz — Gemini Lake, 4 cores |
| **RAM** | 4 GiB LPDDR4 |
| **Audio controller** | Intel *Celeron/Pentium Silver Processor HD Audio* (`8086:3198`) |
| **Subsystem** | `2782:0220` — Emdoor Digital Technology |
| **PCI address** | `0000:00:0e.0` |
| **Audio driver** | `sof-audio-pci-intel-apl` (Sound Open Firmware) |
| **Codec** | ES8336 — `snd_soc_sof_es8336` |
| **ALSA card** | `sof-essx8336` |
| **OS tested** | Lubuntu 26.04 LTS, kernel `7.0.0-29-generic` |

**Compatibility:** if your machine reports the same
`sof-audio-pci-intel-apl` driver and the same `sof-essx8336` card
(`lspci -nnk | grep -A3 -i audio` and `cat /proc/asound/cards`), these
fixes very likely apply to you too, even on a different motherboard
model.

---

## Technical explanation of the issues

### 1. Inverted jack detection at boot

The `snd_soc_sof_es8336` driver uses a DMI-based quirk table to
interpret its jack-detection signal according to the exact motherboard.
Boards missing from this table get `quirk mask 0x0`
(`dmesg | grep -i quirk`): no correction is applied, and the driver
permanently believes a headphone is plugged in (`Headphone Jack` shows
`on` even with nothing connected), cutting the internal speaker right
from cold boot.

Confirmed by testing: plugging in an actual headphone produced sound
correctly — only *the jack polarity interpretation* is wrong. Forcing
quirk bit 6 (`SOF_ES8336_JD_INVERTED`, value 64) fixes this on every
boot.

### 2. Mixer reset after sleep / idle / pause-play

The codec's ALSA controls (`Speaker`, `SPKL`/`SPKR`, and especially
`HPVol SPKVol`, which selects the DAC channels feeding the speaker)
reset after a system sleep, PCI autosuspend, or simply several
video pause/play cycles — **with no sleep involved at all**. Since the
triggers are multiple and independent, `audio-watchdog.sh` continuously
polls these controls and corrects any drift within a fraction of a
second, regardless of the cause.

Subtlety: `amixer sget 'HPVol SPKVol'` always lists all 4 possible
values on its `Items:` line — only the `Item0:` line indicates which
one is actually active. A `grep` over the whole output can wrongly
match the wrong line.

### 3. PCI autosuspend

The kernel itself can put the PCI audio device to sleep
(`power/control = auto`) after idle time, contributing to issue #2. A
systemd service permanently forces `power/control = on` (a udev rule
proved unreliable, racing with SOF driver init), at a negligible power
cost.

### 4. PipeWire hangs independent of the ALSA mixer

Even with a correct mixer and `runtime_status active`, playback can
stay silent. `pw-top` confirms this via the `ERR` column of the
`alsa_output...sof-essx8336...` node: `0` when it works, `1`+ when
sound has died silently. This counter is **cumulative** (never resets
to 0), so `pipewire-watchdog.sh` only reacts to an *increase* in its
value, and then restarts PipeWire/WirePlumber.

### 5. Unresolved: per-browser-tab audio bug

Observed once: a TikTok tab lost all audio (no PipeWire stream) while
a YouTube tab in the same browser (Brave) worked normally. With the
device, mixer, and pipeline otherwise fully functional, this appears
to be a browser/site-specific issue, **outside the scope of these
scripts**.

---

## Installation (Lubuntu / Ubuntu)

```bash
git clone https://github.com/<your-username>/unowhy-y13g011s4ei-lubuntu-audio-fix.git
cd unowhy-y13g011s4ei-lubuntu-audio-fix
sudo ./install.sh
sudo reboot
```

`install.sh` checks that your hardware matches, installs the kernel
quirk, the scripts, and the 3 systemd services, then enables them. A
reboot is required for the quirk (`quirk=64`) to take effect.

> PCI address different from `0000:00:0e.0`? Edit it in
> `scripts/audio-no-runtime-pm.service` and
> `scripts/pipewire-watchdog.sh` before running `install.sh`.

**Quick check** after rebooting:

```bash
cat /sys/module/snd_soc_sof_es8336/parameters/quirk   # -> 64
systemctl status audio-watchdog.service                # -> active (running)
speaker-test -c2 -Dhw:0,0 -t wav
```

**Emergency button** for the per-tab bug (§5) — bind it to a keyboard
shortcut if needed (`pkexec /usr/local/bin/audio-fix-all.sh`):

```bash
sudo /usr/local/bin/audio-fix-all.sh
```

---

## Uninstall

```bash
sudo ./uninstall.sh
sudo reboot
```

Removes the 3 services, the scripts, and the kernel quirk — back to
the original configuration.

---

## Future work

- **Per-tab audio bug (§5).** To investigate: Brave's background-tab
  throttling, a TikTok-specific bug, or WirePlumber dropping a node
  without recreating it. Does it happen on Firefox/Chromium too?
- **Headphone support.** The jack-detection signal is unreliable in
  both directions (`SW_HEADPHONE_INSERT` stays stuck "inserted" even
  when unplugged): currently impossible to distinguish a real
  headphone from a false positive. Manual workaround: stop
  `audio-watchdog.service`, switch `HPVol SPKVol` to headphone
  routing, restart the service when done.
- **CPU/battery.** `INTERVAL` in `audio-watchdog.sh` (0.5s by default)
  is a responsiveness/power tradeoff — increase it if needed.
- **Other distributions.** The approach should be transposable to
  Debian/Fedora/Arch, but the SOF firmware package name differs
  (`sof-firmware`, `alsa-sof-firmware`) and may require regenerating
  the initramfs (`dracut --force`, `mkinitcpio -P`).
- **Upstream fix.** Nothing has been submitted to the SOF/ALSA
  maintainers — a proper entry in their quirk table would be
  preferable to a watchdog. Contributions welcome on
  [thesofproject](https://github.com/thesofproject).

---

## License

Provided as-is, with no warranty of any kind (see
[Warning](#-warning-prototype-under-development--use-at-your-own-risk)).
