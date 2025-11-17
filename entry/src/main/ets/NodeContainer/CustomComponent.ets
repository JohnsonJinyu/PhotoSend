import { BuilderNode, FrameNode, NodeController, UIContext } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';

// 接收GridItem的图片数据和唯一标识（index）
interface CardParams {
  pixelMap: image.PixelMap | null; // 图片PixelMap（和你的ImageInfoWithPixelMap对应）
  uniqueKey: string; // 唯一标识：用GridItem的index转字符串
}

// 转场用的图片Builder（和GridItem中的图片样式一致，保证转场视觉连贯）
@Builder
function CardBuilder(params: CardParams) {
  Image(params.pixelMap || $r('app.media.ic_placeholder'))
    .width('100%')
    .height('100%')
    .objectFit(ImageFit.Cover)
    .borderRadius(0) // 和GridItem图片圆角一致（你的GridItem没设圆角，这里设0）
    .clip(true)
}

// 单个NodeController（对应一个GridItem）
export class MyNodeController extends NodeController {
  private cardNode: BuilderNode<[CardParams]> | null = null;
  private wrapBuilder: WrappedBuilder<[CardParams]> = wrapBuilder(CardBuilder);
  private isRemove: boolean = false;
  private params: CardParams;

  // 构造函数接收唯一标识和图片数据
  constructor(params: CardParams) {
    super();
    this.params = params;
  }

  // 创建节点（转场载体）
  makeNode(uiContext: UIContext): FrameNode | null {
    if (this.isRemove) return null;
    if (!this.cardNode) {
      this.cardNode = new BuilderNode(uiContext);
      this.cardNode.build(this.wrapBuilder, this.params); // 绑定当前GridItem的图片数据
    }
    return this.cardNode.getFrameNode()!;
  }

  // 节点下树（转场时调用）
  onRemove() {
    this.isRemove = true;
    this.rebuild();
    this.isRemove = false;
  }

  // 初始化节点（和你的原有逻辑兼容）
  init(uiContext: UIContext) {
    this.cardNode = new BuilderNode(uiContext);
    this.cardNode.build(this.wrapBuilder, this.params);
  }
}

// 核心：多例管理Map（key=uniqueKey，value=对应NodeController）
const nodeMap = new Map<string, MyNodeController>();

// 1. 创建NodeController（CameraPicturesPage中GridItem循环时调用）
export const createMyNode = (
  uiContext: UIContext,
  uniqueKey: string, // GridItem的index转字符串
  pixelMap: image.PixelMap | null // 当前GridItem的图片数据
) => {
  const params: CardParams = { uniqueKey, pixelMap };
  const node = new MyNodeController(params);
  node.init(uiContext);
  nodeMap.set(uniqueKey, node); // 存入Map，后续通过key获取
};

// 2. 获取NodeController（CameraPicturesPage点击时、BigImagePage加载时调用）
export const getMyNode = (uniqueKey: string): MyNodeController | undefined => {
  return nodeMap.get(uniqueKey);
};

// 3. 删除NodeController（页面卸载时清理，避免内存泄漏）
export const deleteMyNode = (uniqueKey: string) => {
  nodeMap.delete(uniqueKey);
};

// 4. 清空所有NodeController（页面卸载时调用）
export const clearAllMyNodes = () => {
  nodeMap.clear();
};