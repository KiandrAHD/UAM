# Database migrations

No SQLite migrations exist in Phase 0. The application data layer and schema
migrations begin in Phase 3, after the local persistence boundary is selected
and the preset interchange contract has been exercised.

Do not add a live database file here. Migration filenames use a sequential
numeric prefix, for example `0001_initial.sql`. Applied migrations must never be
edited; add a new migration instead.