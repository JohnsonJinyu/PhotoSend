// PhotoScanner.h
// Created on 2025/12/25.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef PHOTO_SCANNER_H
#define PHOTO_SCANNER_H

#include <string>
#include <vector>
#include <mutex>
#include <atomic>
#include <thread>

// libgphoto2头文件
#include <gphoto2/gphoto2.h>
#include <gphoto2/gphoto2-camera.h>

struct PhotoMeta;

/**
 * @brief 照片扫描器类，负责扫描相机中的照片文件
 */
class PhotoScanner {
public:
    /**
     * @brief 构造函数
     */
    PhotoScanner();

    /**
     * @brief 析构函数
     */
    ~PhotoScanner();

    /**
     * @brief 初始化扫描器
     * @param camera libgphoto2相机对象
     * @param context libgphoto2上下文对象
     */
    void Init(Camera* camera, GPContext* context);

    /**
     * @brief 清理资源
     */
    void Cleanup();

    /**
     * @brief 获取照片总数
     * @return 照片总数，如果正在扫描返回0
     */
    int GetPhotoTotalCount();

    /**
     * @brief 分页获取照片元信息
     * @param pageIndex 页码（从0开始）
     * @param pageSize 每页大小
     * @return 照片元信息列表
     */
    std::vector<PhotoMeta> GetPhotoMetaList(int pageIndex, int pageSize);

    /**
     * @brief 启动异步扫描
     * @return 是否成功启动
     */
    bool StartAsyncScan();

    /**
     * @brief 检查扫描是否完成
     * @return 是否完成
     */
    bool IsScanComplete() const;

    /**
     * @brief 获取扫描进度
     * @param current 当前进度（输出参数）
     * @param total 总进度（输出参数）
     * @param cached 是否已缓存（输出参数）
     * @return 是否正在扫描
     */
    bool GetScanProgress(int& current, int& total, bool& cached) const;

    /**
     * @brief 取消扫描
     */
    void CancelScan();

    /**
     * @brief 清理缓存
     */
    void ClearCache();

    /**
     * @brief 判断是否为照片文件
     * @param fileName 文件名
     * @return 是否为照片文件
     */
    static bool IsPhotoFile(const char* fileName);

private:
    /**
     * @brief 异步扫描内部实现
     */
    void AsyncScanInternal();

    /**
     * @brief 查找DCIM目录
     * @return DCIM目录路径，未找到返回空字符串
     */
    std::string FindDcimFolder();

    /**
     * @brief 查找照片目录
     * @param dcimFolder DCIM目录
     * @return 照片目录路径，未找到返回空字符串
     */
    std::string FindPhotoFolder(const std::string& dcimFolder);

    /**
     * @brief 仅扫描照片文件，不下载缩略图
     * @return 照片元信息列表
     */
    std::vector<PhotoMeta> ScanPhotoFilesOnly();

private:
    Camera* camera_;                   // libgphoto2相机对象
    GPContext* context_;               // libgphoto2上下文对象
    
    std::vector<PhotoMeta> cachedFileList_;    // 缓存的文件列表
    std::atomic<bool> isFileListCached_;       // 文件列表是否已缓存
    std::atomic<bool> isScanning_;             // 是否正在扫描
    std::atomic<bool> scanCancelled_;          // 扫描是否被取消
    std::thread scanThread_;                   // 扫描线程
    
    mutable std::mutex cacheMutex_;            // 缓存互斥锁
    std::atomic<int> scanProgressCurrent_;     // 扫描当前进度
    std::atomic<int> scanProgressTotal_;       // 扫描总进度
};

#endif // PHOTO_SCANNER_H
