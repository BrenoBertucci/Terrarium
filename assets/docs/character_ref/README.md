# Character turnaround reference

`trainer_turnaround.png` — front / left profile / back, A-pose, flat lighting,
neutral background. Generated with Meshy (`nano-banana-pro`, 9 credits,
2026-08-27).

## What it is for, and what it is not

**It is not the reference for how a character is rendered.** The diorama draws
the game's own 16×16 sprite on a card. That art is the authority on colour,
silhouette and readability, and no generated image outranks it. If a character
looks wrong on screen, the comparison to make is against a frame with the
SM64CAM row off — not against this.

**It is the reference for proportions and for the angles the sprites do not
have.** Gen 1 draws four facings: up, down, left, right. Before the orbital
camera those were the only four angles anyone could ever see, because the
camera was nailed to the south. Now the camera can stop anywhere — 45° between
two facings is an ordinary place for it to be — and the card still shows one of
those four drawings, turned to face you.

That is not a bug and the billboard fix did not change it. It is the ceiling of
the billboard: a flat card of a front-facing sprite has no three-quarter view
in it to show. This sheet is what a three-quarter view would look like if the
art existed, which makes it the starting point for either of the two ways past
that ceiling:

- **Per-angle sprite art** — draw the four diagonals, pick the nearest of eight
  by the angle between the camera and the entity's facing. Cheap, stays pixel
  art, and the seams between rungs are visible if the drawings do not match.
- **A real 3D character** — this sheet is already in the shape `image-to-3d`
  wants (clean turnaround, A-pose, plain background). Solves the angle problem
  outright and costs the pixel-art look, which is most of why this mod exists.

Neither is started. This is the reference they would begin from.

## What it deliberately is not

A likeness of any specific protagonist. It is the archetype — young trainer,
cap, jacket, backpack — at diorama proportions, which is all a proportion and
angle reference needs to be.
