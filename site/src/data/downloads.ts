// Single source of truth for downloads. The release pipeline
// (.github/workflows/release.yml) publishes these exact asset names, and the
// buttons link to /releases/latest/download/<file>, so a new tag updates the
// site without a redeploy.

export const REPO_URL = "https://github.com/dev-fcastro/local-board";
export const RELEASES_URL = `${REPO_URL}/releases`;
export const SITE_URL = "https://localboard-one.vercel.app";

export const release = {
  version: "v0.1.0",
  name: "Local Canvas",
};

export const installCommand = `curl -fsSL ${SITE_URL}/install.sh | sh`;
export const uninstallCommand = `curl -fsSL ${SITE_URL}/install.sh | sh -s -- --uninstall`;

export type PlatformId = "linux" | "windows" | "macos";

export interface Platform {
  id: PlatformId;
  name: string;
  detail: string;
  format: string;
  file: string;
  available: boolean;
  /** Shown instead of a download when not available. */
  status: string;
}

// Windows and Linux are released. macOS is not available yet.
export const platforms: Platform[] = [
  {
    id: "linux",
    name: "Linux",
    detail: "64-bit · any modern distro",
    format: ".AppImage",
    file: "LocalBoard-x86_64.AppImage",
    available: true,
    status: "Available",
  },
  {
    id: "windows",
    name: "Windows",
    detail: "Windows 10 and 11 · 64-bit",
    format: ".exe installer",
    file: "LocalBoard-Setup-x64.exe",
    available: true,
    status: "Available",
  },
  {
    id: "macos",
    name: "macOS",
    detail: "Apple silicon and Intel",
    format: ".dmg",
    file: "LocalBoard.dmg",
    available: false,
    status: "Not available yet",
  },
];

export const windowsExtras = [
  { label: "Portable .zip", file: "LocalBoard-windows-x64.zip" },
  { label: "SHA256 checksums", file: "SHA256SUMS" },
];

export const linuxExtras = [
  { label: "Portable .tar.gz", file: "LocalBoard-linux-x86_64.tar.gz" },
  { label: "SHA256 checksums", file: "SHA256SUMS" },
];

export const downloadUrl = (file: string) => `${RELEASES_URL}/latest/download/${file}`;

export const firstReleaseScope = [
  "Infinite canvas",
  "Pan and zoom",
  "Pen and eraser",
  "Rectangles, ellipses, lines and arrows",
  "Text and sticky notes",
  "Select, move, resize and delete",
  "Undo and redo",
  "Automatic saving with crash recovery",
  "Reopens exactly where you left it",
  "Export to PNG, SVG and .whiteboard",
  "Works without internet",
];
