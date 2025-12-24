import { image } from "@kit.ImageKit";

export interface ImageInfoWithPixelMap {
  folder: string;
  filename: string;
  pixelMap: image.PixelMap | null;
  thumbnail?: ArrayBuffer;
}

export interface PhotoMeta {
  folder: string;
  filename: string;
  size?: number;
}

export interface BigImageParams {
  imageInfo: ImageInfoWithPixelMap;
}

export interface ScanProgressInfo {
  scanning: boolean;
  current: number;
  total: number;
  cached: boolean;
  count?: number;
}