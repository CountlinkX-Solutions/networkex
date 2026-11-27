# geodanet

Streets (293 lines), crimes (287 points) and schools (8 points) of Tempe, Arizona, in NAD 1983
StatePlane Arizona Central (US feet). Distributed with libpysal (`libpysal.examples`, dataset
`geodanet`, "Datasets from GeoDaNet for network analysis") and used in the spaghetti tutorials. A
copy of `test/reference/data`, for the notebooks. Not part of the Networkex Hex package.

The files are byte-for-byte copies of those in libpysal 4.15.1 (`libpysal/examples/geodanet`),
a subset of that directory: its `README.md`, the spatial index files (`.sbn`, `.sbx`) and the
unfilled metadata template `crimes.shp.xml` are left out. Copyright (c) 2007-, PySAL Developers.
Redistributed under libpysal's BSD 3-Clause License, reproduced in
[LICENSES/BSD-3-Clause-libpysal.txt](../../../LICENSES/BSD-3-Clause-libpysal.txt).

The schools layer comes with its metadata, `schools.shp.xml` (title "ADEQ_AZ_SCHOOLS_2008"). It
names as origin the "Arizona Department of Environmental Quality, Arizona Department of Health
Services" and credits the Arizona Department of Education, the Arizona Department of Health
Services, the Arizona State Land Department and the Arizona State Cartographers Office. Its
access constraint reads: "Access to these data are allowed for non-commercial applications
without charge. Commercial uses require payment." Its use constraint is a disclaimer by the
Arizona Department of Environmental Quality. See
[THIRD_PARTY_NOTICES.md](../../../THIRD_PARTY_NOTICES.md), section (c).
