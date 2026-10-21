# Upgrading

## To Hakushi 0.3

Hakushi 0.3 runs on [Issho](https://hex.pm/packages/issho) 0.3: the canvas
is a block of an Issho page, its agents move with Issho's motion, and
following someone is the room's. A canvas that is not shared needs nothing.

### What changes

| 0.2 | 0.3 |
| --- | --- |
| `{:issho, "~> 0.2"}` | `{:issho, "~> 0.3"}` |
| an agent's moves were the canvas's own | they are Issho's motion: only when someone sees the canvas, within a tool call's budget |
| the canvas drew every cursor on it | on a page with Issho's pointers, they draw everyone's pointer on the canvas too, at the same point of the canvas for each person; alone, the canvas draws its own |
| the avatars were images | they are buttons that follow someone, in the room |

### Steps

1. **Update** `{:hakushi, "~> 0.3"}` and `{:issho, "~> 0.3"}`.
2. **On a page of several blocks**, add Issho's pointers and people list
   (`Issho.Components.pointers/1`, `Issho.Components.people/1`): one
   pointer for each person across the page, the canvas included, and
   following from the page.
3. **If you styled `.hakushi-person`**, it is a `<button>` now, with
   `aria-pressed` on the one followed.
