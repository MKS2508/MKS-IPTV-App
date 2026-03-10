export interface FeatureData {
  id: string;
  title: string;
  description: string;
  icon: string;
  color: string;
}

export interface ScreenshotData {
  id: string;
  title: string;
  description: string;
  platform: 'iOS' | 'macOS' | 'tvOS';
  src: string;
  thumbnail: string;
  width: number;
  height: number;
}

export interface DownloadData {
  id: string;
  platform: 'iOS' | 'macOS' | 'tvOS';
  version: string;
  size: string;
  url: string;
  requirements: string;
  isDirectDownload: boolean;
}