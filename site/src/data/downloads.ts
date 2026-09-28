// Single source of truth for downloads. When a release is published on GitHub
// with these asset names, set `available: true` and the buttons go live.

export const REPO_URL = "https://github.com/dev-fcastro/Local-Board";
export const RELEASES_URL = `${REPO_URL}/releases`;

export const release = {
  version: "v0.1",
  name: "Local Canvas",
};

export type PlatformId = "windows" | "macos" | "linux";

export interface Platform {
  id: PlatformId;
  name: string;
  detail: string;
  format: string;
  file: string;
  available: boolean;
  eta: string;
}

export const platforms: Platform[] = [
  {
    id: "windows",
    name: "Windows",
    detail: "64-bit installer",
    format: ".exe",
    file: "LocalBoard-Setup-x64.exe",
    available: false,
    eta: "With v0.1",
  },
  {
    id: "macos",
    name: "macOS",
    detail: "Apple silicon and Intel",
    format: ".dmg",
    file: "LocalBoard.dmg",
    available: false,
    eta: "After v0.1",
  },
  {
    id: "linux",
    name: "Linux",
    detail: "64-bit",
    format: ".AppImage",
    file: "LocalBoard-x86_64.AppImage",
    available: false,
    eta: "After v0.1",
  },
];

export const downloadUrl = (p: Platform) => `${RELEASES_URL}/latest/download/${p.file}`;

export const firstReleaseScope = [
  "Infinite canvas",
  "Pan and zoom",
  "Pen",
  "Rectangles, circles and lines",
  "Text",
  "Select, move and delete",
  "Undo and redo",
  "Automatic saving",
  "Reopens exactly where you left it",
  "Works without internet",
];
