// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.
#include "angle_surface_manager.h"

#include <iostream>

#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "d3d11.lib")

#define FAIL(message)                                                 \
  std::cout << "media_kit: ANGLESurfaceManager: Failure: " << message \
            << std::endl;                                             \
  return false

#define CHECK_HRESULT(message) \
  if (FAILED(hr)) {            \
    FAIL(message);             \
  }

int ANGLESurfaceManager::instance_count_ = 0;

ANGLESurfaceManager::ANGLESurfaceManager(int32_t width, int32_t height)
    : width_(width), height_(height) {
  mutex_ = ::CreateMutex(NULL, FALSE, NULL);
  Create();
  instance_count_++;
}

ANGLESurfaceManager::~ANGLESurfaceManager() {
  CleanUp(true);
  ::ReleaseMutex(mutex_);
  ::CloseHandle(mutex_);
  instance_count_--;
}

void ANGLESurfaceManager::SetSize(int32_t width, int32_t height) {
  if (width == width_ && height == height_) {
    return;
  }
  width_ = width;
  height_ = height;
  Create();
}

void ANGLESurfaceManager::Draw(std::function<void()> callback) {
  ::WaitForSingleObject(mutex_, INFINITE);
  MakeCurrent(true);
  callback();
  // WonderFlix: upstream copied in |Read| (Flutter's raster thread), on
  // another device, and only flushed. With the GPU busy (a game in the
  // foreground) the copy could run after mpv had started the next frame on
  // the internal texture, and Flutter showed a black frame. Copy here, once
  // per rendered frame.
  if (angle_context_ != nullptr) {
    // Same device as the rendering: the copy runs after this frame and before
    // the next one, and the single |glFinish| waits for both.
    glFlush();
    angle_context_->CopyResource(angle_texture_.Get(),
                                 angle_internal_texture_.Get());
    SwapBuffers();
    MakeCurrent(false);
    ::ReleaseMutex(mutex_);
    return;
  }
  SwapBuffers();
  MakeCurrent(false);
  // No D3D 11 device behind ANGLE: copy on our device and wait for it before
  // the next |Draw| can start.
  if (d3d_11_device_context_ != nullptr) {
    d3d_11_device_context_->CopyResource(d3d_11_texture_2D_.Get(),
                                         internal_d3d_11_texture_2D_.Get());
    Microsoft::WRL::ComPtr<ID3D11Query> query;
    const D3D11_QUERY_DESC query_desc{D3D11_QUERY_EVENT, 0};
    if (SUCCEEDED(d3d_11_device_->CreateQuery(&query_desc, &query))) {
      d3d_11_device_context_->End(query.Get());
      d3d_11_device_context_->Flush();
      // Bounded: a lost device must not hang the render thread.
      const auto deadline = ::GetTickCount64() + 100;
      BOOL done = FALSE;
      while (d3d_11_device_context_->GetData(query.Get(), &done, sizeof(done),
                                             0) == S_FALSE &&
             ::GetTickCount64() < deadline) {
        ::Sleep(0);
      }
    } else {
      d3d_11_device_context_->Flush();
    }
  }
  ::ReleaseMutex(mutex_);
}

void ANGLESurfaceManager::Read() {
  // WonderFlix: nothing to do, |Draw| already copied the frame. Flutter's
  // raster thread no longer waits for the GPU or for a |Draw| in progress.
}

void ANGLESurfaceManager::MakeCurrent(bool value) {
  if (value) {
    eglMakeCurrent(display_, surface_, surface_, context_);
  } else {
    eglMakeCurrent(display_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
  }
}

void ANGLESurfaceManager::SwapBuffers() {
  glFinish();
}

void ANGLESurfaceManager::Create() {
  CleanUp(false);
  if (!CreateD3DTexture()) {
    throw std::runtime_error("Unable to create Windows Direct3D device.");
    return;
  }
  if (!CreateEGLDisplay()) {
    throw std::runtime_error("Unable to create ANGLE EGL display.");
    return;
  }
  if (!CreateAndBindEGLSurface()) {
    throw std::runtime_error("Unable to create ANGLE EGL surface.");
    return;
  }
  if (internal_handle_ == nullptr || handle_ == nullptr) {
    throw std::runtime_error("Unable to retrieve Direct3D shared HANDLE.");
    return;
  }
}

void ANGLESurfaceManager::CleanUp(bool release_context) {
  // WonderFlix: drop what we hold on ANGLE's device before |eglTerminate|.
  angle_context_.Reset();
  angle_internal_texture_.Reset();
  angle_texture_.Reset();
  if (release_context) {
    if (display_ != EGL_NO_DISPLAY && surface_ != EGL_NO_SURFACE) {
      eglReleaseTexImage(display_, surface_, EGL_BACK_BUFFER);
    }
    if (display_ != EGL_NO_DISPLAY && context_ != EGL_NO_CONTEXT) {
      eglDestroyContext(display_, context_);
      context_ = EGL_NO_CONTEXT;
    }
    if (surface_ != EGL_NO_SURFACE) {
      eglDestroySurface(display_, surface_);
      surface_ = EGL_NO_SURFACE;
    }
    if (instance_count_ == 1) {
      eglTerminate(display_);
    }
    display_ = EGL_NO_DISPLAY;
    // Release D3D device & context if the instance is being destroyed.
    if (d3d_11_device_context_) {
      d3d_11_device_context_->Release();
      d3d_11_device_context_ = nullptr;
    }
    if (d3d_11_device_) {
      d3d_11_device_->Release();
      d3d_11_device_ = nullptr;
    }
  } else {
    // Clear context & destroy existing |surface_|.
    eglMakeCurrent(display_, EGL_NO_SURFACE, EGL_NO_SURFACE, context_);
    if (display_ != EGL_NO_DISPLAY && surface_ != EGL_NO_SURFACE) {
      eglDestroySurface(display_, surface_);
    }
    surface_ = EGL_NO_SURFACE;
  }
  // Release D3D 11 texture(s).
  if (internal_d3d_11_texture_2D_) {
    internal_d3d_11_texture_2D_->Release();
    internal_d3d_11_texture_2D_ = nullptr;
  }
  if (d3d_11_texture_2D_) {
    d3d_11_texture_2D_->Release();
    d3d_11_texture_2D_ = nullptr;
  }
}

bool ANGLESurfaceManager::CreateD3DTexture() {
  if (d3d_11_device_ == nullptr) {
    // NOTE: Not enabling Feature Level 12. It crashes directly on Windows 7.
    const auto feature_levels = {
        D3D_FEATURE_LEVEL_11_0,
        D3D_FEATURE_LEVEL_10_1,
        D3D_FEATURE_LEVEL_10_0,
        D3D_FEATURE_LEVEL_9_3,
    };

    IDXGIAdapter* adapter = nullptr;
    D3D_DRIVER_TYPE driver_type = D3D_DRIVER_TYPE_UNKNOWN;

    // NOTE: Automatically selecting adapter on Windows 10 RTM or greater.
    if (Utils::IsWindows10RTMOrGreater()) {
      adapter = NULL;
      driver_type = D3D_DRIVER_TYPE_HARDWARE;
    } else {
      IDXGIFactory* dxgi = nullptr;
      ::CreateDXGIFactory(__uuidof(IDXGIFactory), (void**)&dxgi);
      // As far as my experience goes, this is the safest approach. Passing NULL
      // (so-called default) seems to cause issues on Windows 7 or maybe some
      // older graphics drivers. First adapter is the default.
      // D3D_DRIVER_TYPE_UNKNOWN| must be passed with manual adapter selection.
      dxgi->EnumAdapters(0, &adapter);
      dxgi->Release();
    }

    auto hr = ::D3D11CreateDevice(
        adapter, driver_type, 0, 0, feature_levels.begin(),
        static_cast<UINT>(feature_levels.size()), D3D11_SDK_VERSION,
        &d3d_11_device_, 0, &d3d_11_device_context_);
    CHECK_HRESULT("D3D11CreateDevice");
  }

  Microsoft::WRL::ComPtr<IDXGIDevice> dxgi_device = nullptr;
  auto dxgi_device_success = d3d_11_device_->QueryInterface(
      __uuidof(IDXGIDevice), (void**)&dxgi_device);
  if (SUCCEEDED(dxgi_device_success) && dxgi_device != nullptr) {
    dxgi_device->SetGPUThreadPriority(5);  // Must be in interval [-7, 7].
  }

  auto level = d3d_11_device_->GetFeatureLevel();
  std::cout << "media_kit: ANGLESurfaceManager: Direct3D Feature Level: "
            << (((unsigned)level) >> 12) << "_"
            << ((((unsigned)level) >> 8) & 0xf) << std::endl;
  auto d3d11_texture2D_desc = D3D11_TEXTURE2D_DESC{0};
  d3d11_texture2D_desc.Width = width_;
  d3d11_texture2D_desc.Height = height_;
  d3d11_texture2D_desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  d3d11_texture2D_desc.MipLevels = 1;
  d3d11_texture2D_desc.ArraySize = 1;
  d3d11_texture2D_desc.SampleDesc.Count = 1;
  d3d11_texture2D_desc.SampleDesc.Quality = 0;
  d3d11_texture2D_desc.Usage = D3D11_USAGE_DEFAULT;
  d3d11_texture2D_desc.BindFlags =
      D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
  d3d11_texture2D_desc.CPUAccessFlags = 0;
  d3d11_texture2D_desc.MiscFlags = D3D11_RESOURCE_MISC_SHARED;

  // The general idea is to create two textures, one that is used to |Draw|
  // using ANGLE & another one that is used for |Read| the rendered content
  // using |handle|.
  // WonderFlix: the internal texture is copied to the public texture by
  // |Draw|, once per rendered frame (upstream: by |Read|, once per Flutter
  // frame).

  // Internal.
  auto hr = d3d_11_device_->CreateTexture2D(&d3d11_texture2D_desc, nullptr,
                                            &internal_d3d_11_texture_2D_);
  CHECK_HRESULT("ID3D11Device::CreateTexture2D");
  auto resource = Microsoft::WRL::ComPtr<IDXGIResource>{};
  hr = internal_d3d_11_texture_2D_.As(&resource);
  CHECK_HRESULT("ID3D11Texture2D::As");
  // Retrieve the shared |HANDLE| for interop.
  hr = resource->GetSharedHandle(&internal_handle_);
  CHECK_HRESULT("IDXGIResource::GetSharedHandle");
  internal_d3d_11_texture_2D_->AddRef();

  // External.
  hr = d3d_11_device_->CreateTexture2D(&d3d11_texture2D_desc, nullptr,
                                       &d3d_11_texture_2D_);
  CHECK_HRESULT("ID3D11Device::CreateTexture2D");
  hr = d3d_11_texture_2D_.As(&resource);
  CHECK_HRESULT("ID3D11Texture2D::As");
  // Retrieve the shared |HANDLE| for interop.
  hr = resource->GetSharedHandle(&handle_);
  CHECK_HRESULT("IDXGIResource::GetSharedHandle");
  d3d_11_texture_2D_->AddRef();

  return true;
}

bool ANGLESurfaceManager::CreateEGLDisplay() {
  if (display_ == EGL_NO_DISPLAY) {
    auto eglGetPlatformDisplayEXT =
        reinterpret_cast<PFNEGLGETPLATFORMDISPLAYEXTPROC>(
            eglGetProcAddress("eglGetPlatformDisplayEXT"));
    if (eglGetPlatformDisplayEXT) {
      display_ = eglGetPlatformDisplayEXT(EGL_PLATFORM_ANGLE_ANGLE,
                                          EGL_DEFAULT_DISPLAY,
                                          kD3D11DisplayAttributes);
      if (eglInitialize(display_, 0, 0) == EGL_FALSE) {
        display_ = eglGetPlatformDisplayEXT(EGL_PLATFORM_ANGLE_ANGLE,
                                            EGL_DEFAULT_DISPLAY,
                                            kD3D11_9_3DisplayAttributes);
        if (eglInitialize(display_, 0, 0) == EGL_FALSE) {
          display_ = eglGetPlatformDisplayEXT(EGL_PLATFORM_ANGLE_ANGLE,
                                              EGL_DEFAULT_DISPLAY,
                                              kD3D9DisplayAttributes);
          if (eglInitialize(display_, 0, 0) == EGL_FALSE) {
            display_ = eglGetPlatformDisplayEXT(EGL_PLATFORM_ANGLE_ANGLE,
                                                EGL_DEFAULT_DISPLAY,
                                                kWrapDisplayAttributes);
            if (eglInitialize(display_, 0, 0) == EGL_FALSE) {
              FAIL("eglGetPlatformDisplayEXT");
            }
          }
        }
      }
    } else {
      FAIL("eglGetProcAddress");
    }
  }
  return true;
}

bool ANGLESurfaceManager::CreateAndBindEGLSurface() {
  // Do not create |context_| again, likely due to |Resize|.
  if (context_ == EGL_NO_CONTEXT) {
    // First time from the constructor itself.
    auto count = 0;
    auto result = eglChooseConfig(display_, kEGLConfigurationAttributes,
                                  &config_, 1, &count);
    if (result == EGL_FALSE || count == 0) {
      FAIL("eglChooseConfig");
    }
    context_ = eglCreateContext(display_, config_, EGL_NO_CONTEXT,
                                kEGLContextAttributes);
    if (context_ == EGL_NO_CONTEXT) {
      FAIL("eglCreateContext");
    }
  }
  EGLint buffer_attributes[] = {
      EGL_WIDTH,          width_,         EGL_HEIGHT,         height_,
      EGL_TEXTURE_TARGET, EGL_TEXTURE_2D, EGL_TEXTURE_FORMAT, EGL_TEXTURE_RGBA,
      EGL_NONE,
  };
  surface_ = eglCreatePbufferFromClientBuffer(
      display_, EGL_D3D_TEXTURE_2D_SHARE_HANDLE_ANGLE, internal_handle_,
      config_, buffer_attributes);
  if (surface_ == EGL_NO_SURFACE) {
    FAIL("eglCreatePbufferFromClientBuffer");
  }
  // WonderFlix: open both textures on ANGLE's device (see |Draw|). On any
  // failure |angle_context_| stays null and |Draw| copies on our device.
  auto query_display = reinterpret_cast<PFNEGLQUERYDISPLAYATTRIBEXTPROC>(
      eglGetProcAddress("eglQueryDisplayAttribEXT"));
  auto query_device = reinterpret_cast<PFNEGLQUERYDEVICEATTRIBEXTPROC>(
      eglGetProcAddress("eglQueryDeviceAttribEXT"));
  EGLAttrib egl_device = 0;
  EGLAttrib angle_device = 0;
  if (query_display && query_device &&
      query_display(display_, EGL_DEVICE_EXT, &egl_device) == EGL_TRUE &&
      query_device(reinterpret_cast<EGLDeviceEXT>(egl_device),
                   EGL_D3D11_DEVICE_ANGLE, &angle_device) == EGL_TRUE &&
      angle_device != 0) {
    auto device = reinterpret_cast<ID3D11Device*>(angle_device);
    if (SUCCEEDED(device->OpenSharedResource(
            internal_handle_, IID_PPV_ARGS(&angle_internal_texture_))) &&
        SUCCEEDED(device->OpenSharedResource(handle_,
                                             IID_PPV_ARGS(&angle_texture_)))) {
      device->GetImmediateContext(&angle_context_);
    } else {
      angle_internal_texture_.Reset();
      angle_texture_.Reset();
    }
  }
  std::cout << "media_kit: ANGLESurfaceManager: copy on "
            << (angle_context_ ? "ANGLE's device" : "own device") << std::endl;
  GLuint t;
  glGenTextures(1, &t);
  glBindTexture(GL_TEXTURE_2D, t);
  eglBindTexImage(display_, surface_, EGL_BACK_BUFFER);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  return true;
}
