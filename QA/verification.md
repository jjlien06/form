# Verification — September 17, 2026

- Xcode 26.6 / iOS 26.5 SDK; deployment target iOS 17.
- iPhone simulator build succeeded.
- Signed physical iPhone build succeeded using the existing development team.
- Five unit tests passed: rotated/translated bounds, invalid/sparse clouds, isolated outliers, unit conversion and persistence/deletion with demo provenance.
- Two UI tests passed: demo labeling, cm/in toggle, saving and library; resetting a measurement and opening/dismissing the guide.
- Simulator screenshot inspected: `demo.png`. This is synthetic example data, not a device scan.
- Final package includes a custom app icon and iPhone-only device family.

Not validated: physical sensor accuracy, real object segmentation, mask/depth alignment, multi-view fusion quality, or AR label stability. Use the device validation checklist in README.md before relying on measurements.
