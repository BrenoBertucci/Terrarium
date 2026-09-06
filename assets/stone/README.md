# The crypt's surfaces

The inside of the Pokemon Tower (`lib/CryptKit.lua`, `lib/Crypt.lua`, the
CRYPT-FX row) wears these on its walls, headstones and floor: albedo and a
DirectX-convention tangent-space normal map each, mapped in world space by
the face's own axis.

| file | source | use |
| --- | --- | --- |
| `crypt_wall.jpg`, `crypt_wall_n.jpg` | Poly Haven **castle_wall_slates** (1k) | the ring walls, 256 world px per cycle |
| `crypt_granite.jpg`, `crypt_granite_n.jpg` | Poly Haven **granite_tile_03** (1k, one slab's interior) | the headstones |
| `../floor/crypt.jpg`, `../floor/crypt_n.jpg` | Poly Haven **monastery_stone_floor** (1k) | the floor (`lib/FloorArt.lua`, profile `crypt`) |

All three are **CC0** (public domain) from https://polyhaven.com -- no
attribution required, given anyway. They were desaturated and cooled toward
the crypt's grey and their means normalised to what the scene shader
expects (`tools`: the session's `prep_polyhaven.py`; the shader multiplies
the wall's albedo by 1.94 and the granite's by 2.2 to bring a mean of
0.515 / 0.45 back to unity, so the art is the DETAIL and the geometry's own
light stays the tone).

The wall's HEIGHT (`crypt_wall_h.png`) is not only a bump: `lib/CryptKit.lua`
stands each stone of it in depth -- proud of its joint, two voxels into the
room at the highest -- so replacing the albedo without the height, or the
other way around, will leave the silhouette disagreeing with the picture.

Drop-in contract like the rest of `assets/`: replace a file and it is used,
delete the wall's and the materials fall back to plain stone.
