#!/usr/bin/env python3
"""Erzeugt src/strings.inc: alle Texte im GEOS-Zeichensatz (entspricht Mac Roman: ä=8Ah ö=9Ah ü=9Fh ß=A7h)."""
import os
S = [
 ('s_title',   'PIXELFEHLER-JAGD'),
 ('s_t1',      'Die Treiber laufen - aber die Bugs krabbeln noch!'),
 ('s_t2',      'Klick sie weg, bevor sie sich vermehren. 60 Sekunden.'),
 ('s_l1',      'Bug: 10 Punkte'),
 ('s_l2',      'Turbo-Bug: 20 Punkte'),
 ('s_l3',      'Goldkäfer: 50 Punkte (haut schnell ab!)'),
 ('s_l4',      'Bluescreen-Bug: NICHT klicken! (-25)'),
 ('s_t3',      'Treffer hintereinander geben Combo-Bonus bis x5.'),
 ('s_start',   '>>> Klick ins Bild zum Starten <<<'),
 ('s_pts',     'Punkte:'),
 ('s_time',    'Zeit:'),
 ('s_combo',   'Combo x'),
 ('s_go',      "Los geht's! Klick die Bugs!"),
 ('s_end',     'ZEIT UM!'),
 ('s_endpts',  'Punkte: '),
 ('s_hits',    'Treffer: '),
 ('s_miss',    '   Daneben: '),
 ('s_r1',      'Pixel-Praktikant. Üben, üben, üben!'),
 ('s_r2',      'Bug-Basher. Solide Arbeit!'),
 ('s_r3',      'Treiber-Flüsterer! Respekt.'),
 ('s_r4',      'GeoWorks-Gott! Kein Bug überlebt.'),
 ('s_endfun',  "Der Treiber war's nicht - du warst es!"),
 ('s_again',   'Klick = neue Runde'),
 ('s_bs0',     ' GEOS '),
 ('s_bs1',     'Ein Bluescreen-Bug wurde angeklickt.'),
 ('s_bs2',     'Schwerer Fehler 0E: Finger-Ausnahme bei 0028:C0FFEE'),
 ('s_bs3',     '* Bitte nichts drücken. Es geht gleich weiter.'),
 ('s_bs4',     '* Strafe: -25 Punkte. Combo weg.'),
 ('s_gold',    'GOLDKÄFER! Jackpot!'),
 ('s_goldgone','Goldkäfer entkommen...'),
 ('s_blue',    'Finger weg vom Bluescreen!'),
 ('s_pause',   'Pause. Die Bugs warten.'),
 ('s_resume',  "Weiter geht's!"),
]
HIT = ["Der Treiber war's nicht!", 'Zack! Ein Pixel weniger.', 'Bank 127? Nie gehört!',
       'Papa testet weiter!', 'Gesquasht!', 'Bug gefixt. Glaub ich.', 'Kein Absturz heute!',
       'Das war kein Feature.', 'GeoWorks sagt danke.', 'Weg mit dem Grauschleier!',
       'Wieder ein Pixel sauber.', 'Patch erfolgreich!']
MISS = ['Daneben! Der Bug lacht.', 'Knapp vorbei!', 'Das war nur Staub.', 'Brille putzen?']
out = ['; automatisch erzeugt von tools/genstrings.py']
def emit(lbl, s):
    b = s.encode('mac_roman')
    out.append('%s: db %s,0' % (lbl, ','.join('%d' % c for c in b)))
for l, s in S: emit(l, s)
for i, s in enumerate(HIT): emit('s_hit%d' % i, s)
for i, s in enumerate(MISS): emit('s_miss%d' % i, s)
out.append('NHIT equ %d' % len(HIT)); out.append('NMISS equ %d' % len(MISS))
out.append('hitTab: dw ' + ','.join('s_hit%d' % i for i in range(len(HIT))))
out.append('missTab: dw ' + ','.join('s_miss%d' % i for i in range(len(MISS))))
open(os.path.join(os.path.dirname(__file__), '..', 'src', 'strings.inc'), 'w').write('\n'.join(out) + '\n')
print('strings.inc ok')
