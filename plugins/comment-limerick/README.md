# comment-limerick

A gate for your prose, comment-bound:
every block must in limericks be found.
  Five lines is the shape,
  from which none can escape —
lines one, two, and five share a sound.

Enforced when you write, and again
at the commit, the push, and the PR's blend,
  the very same source —
  a real CMU force —
so what passes once passes to the end.

No jury of jokes to convene;
the gate does not care what you mean.
  It scores just the shape:
  the rhyme, and the tape
of syllables — form, and nothing between.

## Rule

A comment in prose has one home:
`/** ... */`, never to roam.
  A lone `//` line
  is refused by design —
one line cannot build AABBA alone.

Inside of a block, prose divides
into limericks, five lines each, side by side,
  and read start to end
  in the order they send:

| Line | Role | Rhymes with | Meter |
|---|---|---|---|
| 1 | A | 2, 5 | anapestic, 7-10 syllables |
| 2 | A | 1, 5 | anapestic, 7-10 syllables |
| 3 | B | 4 | anapestic, 5-7 syllables |
| 4 | B | 3 | anapestic, 5-7 syllables |
| 5 | A | 1, 2 | anapestic, 7-10 syllables |

A block can chain limericks on through,
so its prose-line count must divide five clean too.
  Lines past the last set
  are a tail, flagged in debt —
finish the verse, or fold into its view.

One `/** ... */` line on its own
still counts toward that same five-line unknown —
  it can't be complete,
  AABBA's not neat
from a soloist standing alone.

The judge of each rhyme and each beat
is the oracle `comment-in-the-hat` can't cheat —
  `cmudict.mjs`,
  gzipped, terse,
backed by real speech, not a guess at the feet.

## The `nantucket:` hatch

A line the oracle can't ever say —
a URL, a number, an ID astray —
  just drops out of view,
  scored not false, not true,
unless it sits tangled in verse on its way.

Then `nantucket:` pulls it aside,
free to sit anywhere, nothing denied —
  not pinned like the hat's
  `cat-in-the-hat:` stats.
Shared markers get this pass too, codified:
`TODO`, `FIXME`, `NOTE`, `HACK`, `XXX`,
lint directives, an `@tag`, a URL's mess.

## No humor requirement

The gate has one job, and it's plain:
score the rhyme and the meter, no more to explain.
  A limerick that's dry,
  scanning true, rhyming spry,
still passes — no wit need remain.

## Skill

`nantucket` takes prose gone astray
and rebuilds it in full AABBA array —
  completes a short set,
  fixes meter, rhyme debt,
and re-hoists stray tokens back out of the way.

Each fix it reports is verified
through that same real oracle, not eyeballed, not tried
  by ear or by guess —
  `scanMeter`, no less,
and `rhymes`, with the changes all clearly supplied.

## Turning Off The Gate

Set `COMMENT_LIMERICK_OFF=1` to silence the write and commit/PR gates
without disabling the plugin — the `nantucket` skill stays available.

- **Session only:** `export COMMENT_LIMERICK_OFF=1` before launching Claude Code.
- **Persistent:** add it to `.claude/settings.json`, then delete the line to
  re-arm the gate:
  ```json
  { "env": { "COMMENT_LIMERICK_OFF": "1" } }
  ```

## Compatibility

One verse form is all it allows,
so it clashes with siblings who'd force other vows —
  `comment-bard`, `-haijin`,
  `-in-the-hat` — pick one champion,
just a single fixed form on each house.

And `comment-reaper` won't get along either:
"why, not what" is a rule form can't wither —
  a fixed shape and a prune
  are two different tunes,
sometimes matched, sometimes pulling in neither.

## Development

`vendor/comment-core` mirrors the true
canonical `packages/comment-core` view —
  edit that one instead,
  then let sync run ahead:
`node scripts/sync-comment-core.mjs` will do.

`vendor/cmudict-map.txt.gz`,
`LICENSE-cmudict`, and `VENDOR.md` stay
  plugin-local and still,
  untouched by that drill —
see `VENDOR.md` if the pin drifts away.

`tests/run.sh` is the spec, cast as tests,
oracle-backed, against the map it invests —
  run it after each change
  to keep the gate's range
honest, verified, passing its quests.
