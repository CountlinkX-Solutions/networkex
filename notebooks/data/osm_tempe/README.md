# OpenStreetMap streets of the Tempe sample area

409 street ways (OSM `highway` = motorway to residential and their links, `living_street` and
`unclassified`) in the box 33.405-33.425 N, 111.842-111.820 W, which covers the geodanet sample
(`../geodanet`). Longitude / latitude (EPSG:4326), with the OSM id, the `highway` class and the
name of each way.

Downloaded from the Overpass API (https://overpass-api.de) on 2026-10-25 (OSM data as of
2026-10-25T22:36Z) with the query

```
[out:json];
way["highway"~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|motorway_link|trunk_link|primary_link|secondary_link|tertiary_link)$"]
  (33.405,-111.842,33.425,-111.820);
out geom;
```

**© OpenStreetMap contributors**, available under the Open Database License (ODbL 1.0,
https://opendatacommons.org/licenses/odbl/). See https://www.openstreetmap.org/copyright. Used by
the notebooks only; not part of the Networkex package.
