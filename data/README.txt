Place your raw datasets here.

Each dataset must be a directory whose name ends with _raw and contains
.stack files, for example:

    data/
      tm_20250601_raw/
        TM0000001_CM0_CHN00.stack
        TM0000002_CM0_CHN00.stack
        ...
        stack_dimension.log

The script scans for data\*_raw automatically and processes each one.
