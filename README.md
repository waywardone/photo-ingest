
# photo-ingest
![GitHub license](https://img.shields.io/github/license/waywardone/photo-ingest) [![GitHub issues](https://img.shields.io/github/issues/waywardone/photo-ingest)](https://github.com/waywardone/photo-ingest/issues)

Tool(s) I personally use to organize photographs I take using various cameras and phones. This covers the gamut of renaming, losslessly rotating, adding copyright notices and storing them in a personally appealing folder structure.
## Usage - bash

```bash
Usage: ./photo-ingest.sh [-h]
        -a <artist>     name to use in copyright notices.
        -c <comment>    optional - suffix for destdir.
        -d <destdir>    optional - specify a destination directory. Defaults to PhotosTODO-YYYYmmdd.
        -g grouping     optional - 'm' or 'md'. Defaults to 'md'.
        -h              print this help screen.
        -s <srcdir>     specify source directory with images/videos.
        -t <h>          optional - offset picture dates by <h> hours (int or float). +h to jump forward and -h to fall back.
```

## Usage - PowerShell

```powershell
     -srcdir            specify source directory with images/videos.
     -artist            name to use in copyright notices.
     -destdir           optional - specify a destination directory. Defaults to PhotosTODO-YYYYmmdd.
     -groupby           optional - 'm' or 'md' for group by month or month-day. Defaults to 'md'. 
     -device            optional - suffix for destdir.
     -fallBackTime      optional - specify number of hours to fall back in timestamps.
     -springForwardTime optional - specify number of hours to spring forward in timestamps.
     -skipCopyright     skip updating copyright notices.
     -skipRotate        skip lossless rotation of images.
```

## Examples
Assuming a source directory with the following contents:

```bash
~/Desktop/DCIM
├── 136APPLE
│   ├── IMG_6442.JPG
│   ├── IMG_6443.JPG
│   ├── IMG_6444.JPG
│   ├── IMG_6445.JPG
│   └── IMG_6819.MOV
└── 137APPLE
    ├── IMG_7001.JPG
    ├── IMG_7002.JPG
    ├── IMG_7003.JPG
    ├── IMG_7004.JPG
    └── IMG_7005.JPG

```
the following invocations: 
```bash
./photo-ingest.sh -s ~/Desktop/DCIM -a "John Doe" -g md -c "iPhone"
``` 

```powershell
.\photo-ingest.ps1 -srcdir C:\Users\User\Desktop\DCIM -artist "John Doe" -groupby md -device "iPhone"
```
will produce a directory structure of:

```
~/Desktop/PhotosTODO-20210505-iPhone
└── 2021
    ├── 0313
    │   ├── 20210313-113149-IMG_6442-001-iP6s.jpg
    │   ├── 20210313-113200-IMG_6443-001-iP6s.jpg
    │   ├── 20210313-113200-IMG_6444-001-iP6s.jpg
    │   └── 20210313-113202-IMG_6445-001-iP6s.jpg
    ├── 0325
    │   └── 20210325-163318-IMG_6819-001-iP6s.mov
    └── 0326
        ├── 20210326-171414-IMG_7001-001-iP6s.jpg
        ├── 20210326-171414-IMG_7002-001-iP6s.jpg
        ├── 20210326-171414-IMG_7003-001-iP6s.jpg
        ├── 20210326-171414-IMG_7004-001-iP6s.jpg
        └── 20210326-171414-IMG_7005-001-iP6s.jpg

```
where each of the files has been losslessly rotated and metadata updated with copyright notices for `John Doe`.
## Acknowledgements

 - [exiftool](https://exiftool.org)
  
## Contributing

Any contributions you make are **greatly appreciated**.

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request


## License

Distributed under the MIT License. See `LICENSE` for more information.


