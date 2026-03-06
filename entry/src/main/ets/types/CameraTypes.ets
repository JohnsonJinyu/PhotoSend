import { image } from "@kit.ImageKit";

@Observed
export class ImageInfoWithPixelMap {
  folder: string;
  filename: string;
  pixelMap: image.PixelMap | null;
  thumbnail?: ArrayBuffer;
  
  constructor(folder: string, filename: string, pixelMap: image.PixelMap | null = null, thumbnail?: ArrayBuffer) {
    this.folder = folder;
    this.filename = filename;
    this.pixelMap = pixelMap;
    this.thumbnail = thumbnail;
  }
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
}