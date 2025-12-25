// PhotoScanner.h
// Created on 2025/12/25.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef PHOTOSEND_PHOTOSCANNER_H
#define PHOTOSEND_PHOTOSCANNER_H

#include <string>
#include <vector>
#include <mutex>
#include <atomic>
#include <thread>

struct PhotoMeta {
    std::string folder;
    std::string fileName;
    size_t fileSize = 0;
};


#endif //PHOTOSEND_PHOTOSCANNER_H
