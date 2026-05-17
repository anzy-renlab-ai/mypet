Drop Jimeng-generated PNG stickers here. Required (per state, at least one):

  cat-idle.png      — sitting / looking forward, mouth closed
  cat-eating.png    — mouth open, mid-chomp, happy
  cat-excited.png   — jumping / paws up, sparkles
  cat-purring.png   — eyes closed, soft smile, ♡
  cat-sleepy.png    — eyes closed, head tilted, drooping
  cat-hungry.png    — sad / pleading, tear

Optional multi-variant packs: add `cat-<state>-2.png` ... `cat-<state>-9.png`
to give the cat a random pick when it enters that state. Example: bundle
`cat-idle.png`, `cat-idle-2.png`, `cat-idle-3.png` and the cat will pick one
of the three at random each time it returns to idle.

Requirements: square 1:1, transparent background, consistent character across
all variants.

The runtime auto-detects each file via Bundle.module and falls back to the
matching cat emoji if no PNG is found for that state.
