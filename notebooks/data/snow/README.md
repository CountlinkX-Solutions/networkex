# John Snow's cholera map, London 1854

A digitization of John Snow's map of the 1854 cholera outbreak in Soho, London: the addresses
with deaths (`SohoPeople`, with `Count` deaths per address), the 13 public water pumps
(`SohoWater`) and the street network (`Soho_Network`). Distributed with libpysal
(`libpysal.examples`, dataset `snow_maps`, "Public water pumps and Cholera deaths in London 1854
(John Snow's Cholera Map)").

Source: Snow, J. (1855). *On the Mode of Communication of Cholera*, 2nd edition. London: John
Churchill. (libpysal cites the 1849 first edition; the map appeared in the second.)

All layers are in Web Mercator (EPSG:3857, `.prj` included). A copy of
[Spatex's `notebooks/data/snow`](https://github.com/CountlinkX-Solutions/spatex/tree/v0.2.1/notebooks/data/snow)
(Spatex 0.2.1), used by `notebooks/snow_network_case.livemd` and
`notebooks/es/caso_snow_red.livemd`. Not part of the Networkex Hex package.

The files are byte-for-byte copies of those in libpysal 4.15.1 (`libpysal/examples/snow_maps`),
which names no digitizer and no license other than its own. They are a subset of that
directory: its `README.md` and the spatial index files (`.sbn`, `.sbx`) are left out; it holds
no metadata (`.xml`) files. Copyright (c) 2007-, PySAL Developers. Redistributed under libpysal's
BSD 3-Clause License, reproduced in
[LICENSES/BSD-3-Clause-libpysal.txt](../../../LICENSES/BSD-3-Clause-libpysal.txt); see also
[THIRD_PARTY_NOTICES.md](../../../THIRD_PARTY_NOTICES.md), section (c).
