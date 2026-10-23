# Where these wallpapers come from

**They are not mine, and this file says what is known about each one.** The repo
is GPL-3.0, and that licence covers the code and the configuration — it does not
and cannot cover these images. They are here as a starting set so a fresh
install comes up with something on screen rather than a flat colour.

If you are the author of any of these and would rather it were not here, open an
issue and it goes.

## Established provenance

| File | Source |
|---|---|
| `art-sunset-after-a-storm-on-the-coast-of-s-437975.jpg` | Andreas Achenbach (1815–1910), *Sunset after a Storm on the Coast of Sicily*. The JPEG comment carries the attribution and the suffix is the object number at the Metropolitan Museum of Art, whose Open Access programme publishes public-domain works under CC0 |
| `art-an-eruption-of-vesuvius-438159.jpg` | Same collection, object 438159 |

Those two are the only ones whose licence can be stated with confidence.

## Everything else: provenance not established

Fourteen of the remaining names end in a six-character alphanumeric code, which
is the shape of a [wallhaven.cc](https://wallhaven.cc) ID. Wallhaven aggregates
work uploaded by its users; it grants no redistribution licence, and each image
belongs to whoever made it. The original upload pages were not recorded when
these were downloaded, so the trail stops there.

Three of them (`dark-gwmxp3.jpg`, `dark-medusa-rqpxm7.jpg`, `dark-vpdvq3.jpg`)
carry embedded XMP naming their author as **Can**, produced in Affinity in July
2026. That is a living, identifiable author and the metadata is all there is —
no URL, no licence.

And several are recognisably **commercial intellectual property**: a chromed
Darth Vader helmet (Lucasfilm / Disney), Monkey D. Luffy (*One Piece*, Shueisha
/ Toei) and Satoru Gojo (*Jujutsu Kaisen*, Shueisha / MAPPA). Fan wallpapers of
copyrighted characters, redistributed here without permission.

## If you are cloning this

The safe move is to delete the lot and drop in your own:

```sh
rm -f ~/Pictures/wallpapers/*
cp /path/to/your/images ~/Pictures/wallpapers/
```

The desktop does not care which images are there. `Super+Shift+W` opens the
picker, and everything — bar, terminal, GTK, Qt, Spotify, lock screen, login —
is recoloured from whichever one you choose.
